import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart'; // <-- AGGIUNTO
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
import 'package:organizzazione_personale_cronos/services/notification_sender.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/mobile_navigation.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Stati ammessi (coerenti con tabella)
const List<String> kStatiAereo = [
  'IN_ATTESA',
  'CONFERMATA',
  'RIFIUTATA',
];

class AdminAereiPage extends StatefulWidget {
  final int adminId;

  const AdminAereiPage({super.key, required this.adminId});

  @override
  State<AdminAereiPage> createState() => _AdminAereiPageState();
}

class _AdminAereiPageState extends State<AdminAereiPage> {
  static const String kTable = 'bookings_aereo';

  /// Sotto questa larghezza la tabella (17 colonne) non è leggibile: vista card.
  static const double _kMinWidthForTable = 1580;

  bool _loading = true;
  bool _showAllBookings = false;

  // ===== FILTRI =====
  String? _statoF;
  String? _personaleF;
  String? _commessaF;
  String? _dtF;
  String? _partenzaF;

  // ===== Dizionari e opzioni =====
  final Map<String, String> _personaleMap = {}; // id -> full_name
  final Map<String, String> _commessaMap = {};  // id -> nome
  final Map<String, String> _dtMap = {};        // users.id/id_uuid -> label
  final Map<String, String> _utentiIdMap = {}; // users.id (int) -> label
  final Map<String, String> _utentiRoleByIdMap = {}; // users.id (int) -> role db
  final Map<String, String> _personaleEmailMap = {};
  final Map<String, String> _utentiEmailByIdMap = {};
  final Map<String, String> _utentiEmailByUuidMap = {};
  final List<String> _aeroporti = [];

  // Opzioni (UUID, deduplicate e ordinate)
  final List<Map<String, String>> _personaleOptions = [];
  final List<Map<String, String>> _commessaOptions = [];
  final List<Map<String, String>> _dtOptions = [];

  // Righe tabella
  List<_AereoRow> _rows = [];
  final Set<String> _selectedIds = <String>{};

  // Scroll controllers
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();

  // Rilevazioni colonne
  String _personaleIdCol = 'id_uuid';
  String _commesseIdCol = 'id_uuid';

  @override
  void initState() {
    super.initState();
    _statoF = 'IN_ATTESA';
    _bootstrap();
  }

  // ===== Bootstrap =====
  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _resolveKeyColumns();
      await _loadDizionari();
      await _loadRows();
    } catch (e) {
      _snack('Errore inizializzazione: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Utils =====
  List<Map<String, String>> _toOptions(Map<String, String> m) {
    final uniq = <String, String>{};
    for (final e in m.entries) {
      if (e.key.isNotEmpty) uniq[e.key] = e.value;
    }
    final list = uniq.entries
        .map((e) => {'id': e.key, 'label': e.value})
        .toList();
    list.sort((a, b) => a['label']!.compareTo(b['label']!));
    return list;
  }

  String? _safeMapValue(String? v, Map<String, String> m) {
    if (v == null) return null;
    return m.containsKey(v) ? v : null;
  }

  String? _safeListValue(String? v, List<String> list) {
    if (v == null) return null;
    return list.contains(v) ? v : null;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);

  DateTime? _tryParseDate(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _toTimeOfDay(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _copyEmailToClipboard(String? email) async {
    final e = (email ?? '').trim();
    if (e.isEmpty) {
      _snack('Nessuna email disponibile', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: e));
    if (mounted) _snack('Email copiata negli appunti');
  }

  String? _richiedenteEmail(_AereoRow r) {
    final reqId = r.requestedByUserId.trim();
    final isAssistant = reqId.isNotEmpty &&
        (_utentiRoleByIdMap[reqId]?.toLowerCase().trim() == 'assistente_dt');
    if (isAssistant && reqId.isNotEmpty) {
      return _utentiEmailByIdMap[reqId];
    }
    final dt = r.dtId.trim();
    if (dt.isNotEmpty) {
      return _utentiEmailByUuidMap[dt] ?? _utentiEmailByIdMap[dt];
    }
    return null;
  }

  Widget _atCopyButton(String? email) {
    final ok = (email ?? '').trim().isNotEmpty;
    return IconButton(
      tooltip: ok ? 'Copia email' : 'Email non disponibile',
      icon: const Text(
        '@',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, height: 1),
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      onPressed: ok ? () => _copyEmailToClipboard(email) : null,
    );
  }

  String _notifTargetsLabel(_AereoRow r) {
    final dt = (_dtMap[r.dtId] ?? '').trim();
    final dip = (_personaleMap[r.personaleId] ?? '').trim();
    final parts = <String>['DT${dt.isNotEmpty ? ' ($dt)' : ''}', 'assistenti DT autorizzati'];
    if (dip.isNotEmpty) parts.add('dipendente ($dip)');
    return parts.join(', ');
  }

  Widget _buildCompactNoteCell(String note) {
    final clean = note.trim();
    if (clean.isEmpty) return const Text('');
    final short = clean.length <= 10 ? clean : '${clean.substring(0, 10)}...';
    return Tooltip(
      message: clean,
      waitDuration: const Duration(milliseconds: 250),
      child: Text(
        short,
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  }

  String _insertedAtLabel(String createdAt) =>
      formatDateTimeItFromSupabase(createdAt);

  DataCell _decorateCellWithInsertedAtTooltip(DataCell cell, String insertedAt) {
    return DataCell(
      Tooltip(
        message: 'Inserita il: $insertedAt',
        waitDuration: const Duration(milliseconds: 220),
        child: cell.child,
      ),
      placeholder: cell.placeholder,
      showEditIcon: cell.showEditIcon,
      onTap: cell.onTap,
      onDoubleTap: cell.onDoubleTap,
      onLongPress: cell.onLongPress,
      onTapDown: cell.onTapDown,
      onTapCancel: cell.onTapCancel,
    );
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN_ATTESA':
        return Colors.orange;
      case 'CONFERMATA':
        return Colors.green;
      case 'RIFIUTATA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // ===== Rilevazione colonne =====
  Future<void> _resolveKeyColumns() async {
    try {
      await SupabaseService.client.from('personale').select('id_uuid').limit(1);
      _personaleIdCol = 'id_uuid';
    } catch (_) {
      _personaleIdCol = 'id';
    }

    try {
      await SupabaseService.client.from('commesse').select('id_uuid').limit(1);
      _commesseIdCol = 'id_uuid';
    } catch (_) {
      _commesseIdCol = 'id';
    }
  }

  // ===== Dizionari =====
  Future<void> _loadDizionari() async {
    List<dynamic> pRows;
    try {
      pRows = await SupabaseService.client
          .from('personale')
          .select('$_personaleIdCol, full_name, active, email')
          .eq('active', true)
          .order('full_name') as List<dynamic>;
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      pRows = await SupabaseService.client
          .from('personale')
          .select('$_personaleIdCol, full_name, active')
          .eq('active', true)
          .order('full_name') as List<dynamic>;
    }

    _personaleMap.clear();
    _personaleEmailMap.clear();
    final pList = pRows
        .map((e) => MapEntry(
              (e[_personaleIdCol] ?? '').toString(),
              (e['full_name'] ?? '').toString(),
            ))
        .toList()
      ..sort((a, b) =>
          a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()));
    _personaleMap.addEntries(pList);
    for (final e in pRows) {
      final k = (e[_personaleIdCol] ?? '').toString();
      final em = (e['email'] ?? '').toString().trim();
      if (k.isNotEmpty && em.isNotEmpty) _personaleEmailMap[k] = em;
    }

    // Commesse
    final c = await SupabaseService.client
        .from('commesse')
        .select('$_commesseIdCol, nome, active')
        .eq('active', true)
        .order('nome');

    _commessaMap
      ..clear()
      ..addEntries(
        ((c as List)
              .map((e) => MapEntry(
                    (e[_commesseIdCol] ?? '').toString(),
                    (e['nome'] ?? '').toString(),
                  ))
              .toList()
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );

    List<dynamic> uRows;
    try {
      uRows = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, username, full_name, role, email')
          .order('username') as List<dynamic>;
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      uRows = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, username, full_name, role')
          .order('username') as List<dynamic>;
    }

    _dtMap.clear();
    _utentiIdMap.clear();
    _utentiRoleByIdMap.clear();
    _utentiEmailByIdMap.clear();
    _utentiEmailByUuidMap.clear();
    for (final e in uRows) {
      final m = e as Map<String, dynamic>;
      final id = (m['id'] ?? '').toString();
      final uuid = (m['id_uuid'] ?? '').toString();
      final label = (m['full_name'] ?? m['username'] ?? '').toString();
      final roleDb = (m['role'] ?? '').toString().toLowerCase().trim();
      final mail = (m['email'] ?? m['username'] ?? '').toString().trim();

      if (id.isNotEmpty) _utentiIdMap[id] = label;
      if (id.isNotEmpty && roleDb.isNotEmpty) _utentiRoleByIdMap[id] = roleDb;
      if (id.isNotEmpty && mail.isNotEmpty) _utentiEmailByIdMap[id] = mail;
      if (uuid.length >= 32 && mail.isNotEmpty) {
        _utentiEmailByUuidMap[uuid] = mail;
      }
      if (id.length >= 32) _dtMap[id] = label;
      if (uuid.length >= 32) _dtMap[uuid] = label;
    }

    // Aeroporti
    final a = await SupabaseService.client
        .from('aeroporti')
        .select('nome, attiva')
        .order('nome');

    _aeroporti
      ..clear()
      ..addAll((a as List)
          .where((e) => (e['attiva'] ?? false) == true)
          .map((e) => (e['nome'] ?? '').toString()));

    // Opzioni (ordinate)
    _personaleOptions
      ..clear()
      ..addAll(_toOptions(_personaleMap));
    _commessaOptions
      ..clear()
      ..addAll(_toOptions(_commessaMap));
    _dtOptions
      ..clear()
      ..addAll(_toOptions(_dtMap));
  }

  /// Query filtrata (senza order/range): paginazione oltre il max_rows di PostgREST.
  dynamic _aereiRowsQuery() {
    dynamic q = SupabaseService.client.from(kTable).select();

    // Mostra solo prenotazioni già inoltrate agli admin (workflow nuovo).
    // Se la colonna non esiste (schema vecchio), ignoriamo il filtro.
    try {
      q = q.eq('workflow_status', 'INVIATA_ADMIN');
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
    } catch (_) {}

    if (_statoF?.isNotEmpty == true) q = q.eq('status', _statoF);
    if (_partenzaF?.isNotEmpty == true) q = q.eq('aeroporto_partenza', _partenzaF);
    if (_personaleF?.isNotEmpty == true) q = q.eq('personale_id', _personaleF);
    if (_commessaF?.isNotEmpty == true) q = q.eq('commessa_id', _commessaF);
    if (_dtF?.isNotEmpty == true) q = q.eq('dt_user_uuid', _dtF);
    return q;
  }

  // ===== Dati =====
  Future<void> _loadRows() async {
    _rows = [];
    _selectedIds.clear();
    setState(() => _loading = true);

    try {
      const pageSize = 1000;
      int from = 0;
      final res = <dynamic>[];
      while (true) {
        final page = await _aereiRowsQuery()
            .order('data', ascending: false)
            .range(from, from + pageSize - 1);
        final list = List<dynamic>.from(page as List);
        if (list.isEmpty) break;
        res.addAll(list);
        from += list.length;
      }

      for (final r in res) {
        _rows.add(_AereoRow(
          id: (r['id'] ?? '').toString(),
          createdAt: (r['created_at'] ?? '').toString(),
          data: (r['data'] ?? '').toString(),
          orario: (r['orario'] ?? '').toString(),
          dataRitorno: (r['data_ritorno'] ?? '').toString(),
          orarioRitorno: (r['orario_ritorno'] ?? '').toString(),
          personaleId: (r['personale_id'] ?? '').toString(),
          requestedByUserId: (r['requested_by_user_id'] ?? '').toString(),
          partenza: (r['aeroporto_partenza'] ?? '').toString(),
          arrivo: (r['aeroporto_arrivo'] ?? '').toString(),
          partenzaRitorno: (r['aeroporto_partenza_ritorno'] ?? '').toString(),
          arrivoRitorno: (r['aeroporto_arrivo_ritorno'] ?? '').toString(),
          commessaId: (r['commessa_id'] ?? '').toString(),
          bagaglio: (r['bagaglio'] ?? '').toString(),
          parcheggio: r['parcheggio'] == true,
          targa: (r['targa_veicolo'] ?? '').toString(),
          stato: (r['status'] ?? '').toString(),
          note: (r['master_note'] ?? '').toString(),
          dtId: (r['dt_user_uuid'] ?? '').toString(),
        ));
      }
    } catch (e) {
      _snack('Errore caricamento: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleQuickLoadMode({required bool showAll}) async {
    setState(() {
      _showAllBookings = showAll;
      _statoF = showAll ? null : 'IN_ATTESA';
      _selectedIds.clear();
    });
    await _loadRows();
  }

  List<_AereoRow> get _selectedRows =>
      _rows.where((r) => _selectedIds.contains(r.id)).toList();

  // ===== Export XLSX =====
  Future<void> _exportExcel() async {
    try {
      if (_rows.isEmpty) {
        _snack('Nessun dato da esportare', error: true);
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel['Aerei'];

      // Header
      sheet.appendRow([
        'Data',
        'Orario andata',
        'Data ritorno',
        'Orario ritorno',
        'Personale',
        'Aeroporto partenza',
        'Aeroporto arrivo',
        'Ritorno diverso',
        'Commessa',
        'Bagaglio',
        'Parcheggio',
        'Targa',
        'Stato',
        'Note',
        'Richiedente',
        'Inserita il',
      ]);

      // Mappe per label
      final pers = _personaleMap;
      final comm = _commessaMap;
      final dt = _dtMap;
      final user = _utentiIdMap;
      // Richiedente: se assistente_dt mostriamo assistente, altrimenti DT.
      final userRole = _utentiRoleByIdMap;

      // Righe
      for (final r in _rows) {
        final ritornoDiverso =
            (r.arrivoRitorno.trim().isNotEmpty && r.arrivoRitorno.trim() != r.partenza.trim());
        sheet.appendRow([
          r.data,
          r.orario,
          r.dataRitorno,
          r.orarioRitorno,
          (pers[r.personaleId] ?? r.personaleId).trim().isEmpty
              ? r.personaleId
              : (pers[r.personaleId] ?? r.personaleId),
          r.partenza,
          r.arrivo,
          ritornoDiverso ? r.arrivoRitorno : '',
          (comm[r.commessaId] ?? r.commessaId).trim().isEmpty
              ? r.commessaId
              : (comm[r.commessaId] ?? r.commessaId),
          r.bagaglio == 'stiva' ? 'In stiva' : 'A mano',
          r.parcheggio ? 'SI' : 'No',
          r.targa,
          r.stato,
          r.note,
          (() {
            final reqId = r.requestedByUserId.trim();
            final isAssistant = reqId.isNotEmpty &&
                (userRole[reqId]?.toLowerCase().trim() == 'assistente_dt');
            return (isAssistant
                    ? (user[reqId] ?? reqId)
                    : (dt[r.dtId] ?? r.dtId))
                .trim();
          })(),
          _insertedAtLabel(r.createdAt),
        ]);
      }

      final bytes = Uint8List.fromList(excel.encode()!);

      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Aerei',
        bytes: bytes,
      );
      if (!saved) return;
      _snack('Export XLSX completato: ${ExcelExportHelper.lastSavedPath ?? ''}');
    } catch (e) {
      _snack('Errore export Excel: $e', error: true);
    }
  }

  // ===== Azioni =====
  Future<void> _updateStato(_AereoRow r, String nuovo) async {
    if (!await ensureCanPersist(context)) return;
    try {
      await SupabaseService.client.from(kTable).update({'status': nuovo}).eq('id', r.id);
      final action = nuovo.toUpperCase().trim() == 'CONFERMATA' ? 'confirm' : 'update';
      final title = nuovo.toUpperCase().trim() == 'CONFERMATA'
          ? 'Prenotazione aerea confermata'
          : 'Prenotazione aerea aggiornata';
      await NotificationSender.notifyUserForBooking(
        dtUserId: r.dtId,
        bookingId: int.parse(r.id),
        action: action,
        title: title,
        bookingType: 'aereo',
      );
      _snack('Stato aggiornato a $nuovo. Notifica inviata a: ${_notifTargetsLabel(r)}');
      await _loadRows();
    } catch (e) {
      _snack('Errore aggiornamento: $e', error: true);
    }
  }

  Future<void> _delete(_AereoRow r) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina prenotazione'),
        content: const Text('Confermi l\'eliminazione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await NotificationSender.notifyUserForBooking(
        dtUserId: r.dtId,
        bookingId: int.parse(r.id),
        action: 'delete',
        title: 'Prenotazione aerea eliminata',
        bookingType: 'aereo',
      );
      // Notifica PRIMA della cancellazione: l'Edge Function legge la prenotazione
      // dal DB per costruire testo (Per/Tipo/Data). Se cancelliamo prima otteniamo N/D.
      await SupabaseService.client.from(kTable).delete().eq('id', r.id);
      _snack('Prenotazione eliminata. Notifica inviata a: ${_notifTargetsLabel(r)}');
      await _loadRows();
    } catch (e) {
      _snack('Errore eliminazione: $e', error: true);
    }
  }

  /// ======== MODIFICA COMPLETA (con DropdownSearch) ========
  Future<void> _edit(_AereoRow r) async {
    if (!await ensureCanPersist(context)) return;
    // Valori correnti
    String? personaleSel = r.personaleId;
    String? cp = r.partenza;
    String? ca = r.arrivo;
    String? cpRitorno =
        r.partenzaRitorno.trim().isNotEmpty ? r.partenzaRitorno : r.arrivo;
    String? caRitorno =
        r.arrivoRitorno.trim().isNotEmpty ? r.arrivoRitorno : r.partenza;
    String? commessaSel = r.commessaId;
    DateTime dataSel = _tryParseDate(r.data) ?? DateTime.now();
    String? orarioSel = (r.orario.isEmpty) ? null : r.orario;
    DateTime? dataRitornoSel = _tryParseDate(r.dataRitorno);
    String? orarioRitornoSel = (r.orarioRitorno.isEmpty) ? null : r.orarioRitorno;

    String stato = kStatiAereo.contains(r.stato) ? r.stato : 'IN_ATTESA';
    String note = r.note;
    String bag = (r.bagaglio == 'stiva') ? 'stiva' : 'mano';
    bool park = r.parcheggio;
    String targa = r.targa;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) {
          return AlertDialog(
            title: const Text('Modifica prenotazione aerea'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Personale (id -> label)
                    DropdownSearch<String>(
                      items: _personaleOptions.map((e) => e['id']!).toList(),
                      selectedItem: _safeMapValue(personaleSel, _personaleMap),
                      itemAsString: (id) => _personaleMap[id] ?? id,
                      onChanged: (v) => setSt(() => personaleSel = v),
                      popupProps: const PopupProps.menu(
                        showSearchBox: true,
                        fit: FlexFit.loose,
                      ),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Personale',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Partenza (stringa semplice)
                    DropdownSearch<String>(
                      items: _aeroporti,
                      selectedItem: _safeListValue(cp, _aeroporti),
                      onChanged: (v) => setSt(() => cp = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Aeroporto di partenza',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Arrivo (stringa semplice)
                    DropdownSearch<String>(
                      items: _aeroporti,
                      selectedItem: _safeListValue(ca, _aeroporti),
                      onChanged: (v) => setSt(() => ca = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Aeroporto di arrivo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Commessa (id -> label)
                    DropdownSearch<String>(
                      items: _commessaOptions.map((e) => e['id']!).toList(),
                      selectedItem: _safeMapValue(commessaSel, _commessaMap),
                      itemAsString: (id) => _commessaMap[id] ?? id,
                      onChanged: (v) => setSt(() => commessaSel = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Commessa',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Data
                    Row(
                      children: [
                        Expanded(child: Text('Data: ${(_displayDate(dataSel))}')),
                        ElevatedButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: dataSel,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setSt(() => dataSel = d);
                          },
                          child: const Text('Cambia data'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Orario andata
                    Row(
                      children: [
                        Expanded(child: Text('Orario andata: ${orarioSel ?? '--:--'}')),
                        ElevatedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: _toTimeOfDay(orarioSel) ?? TimeOfDay.now(),
                            );
                            if (t != null) {
                              setSt(() {
                                orarioSel =
                                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                          child: const Text('Orario andata'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Data ritorno
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Data ritorno: ${dataRitornoSel == null ? '--' : _displayDate(dataRitornoSel!)}',
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: dataRitornoSel ?? dataSel,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setSt(() => dataRitornoSel = d);
                          },
                          child: const Text('Data ritorno'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setSt(() => dataRitornoSel = null),
                          child: const Text('Azzera'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Orario ritorno
                    Row(
                      children: [
                        Expanded(child: Text('Orario ritorno: ${orarioRitornoSel ?? '--:--'}')),
                        ElevatedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: _toTimeOfDay(orarioRitornoSel) ?? TimeOfDay.now(),
                            );
                            if (t != null) {
                              setSt(() {
                                orarioRitornoSel =
                                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                          child: const Text('Orario ritorno'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setSt(() => orarioRitornoSel = null),
                          child: const Text('Azzera'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Aeroporti ritorno (solo se ritorno presente)
                    if (dataRitornoSel != null ||
                        (orarioRitornoSel != null && orarioRitornoSel!.trim().isNotEmpty)) ...[
                      DropdownSearch<String>(
                        items: _aeroporti,
                        selectedItem: _safeListValue(cpRitorno, _aeroporti),
                        onChanged: (v) => setSt(() => cpRitorno = v),
                        popupProps: const PopupProps.menu(showSearchBox: true),
                        clearButtonProps: const ClearButtonProps(isVisible: true),
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration: const InputDecoration(
                            labelText: 'Aeroporto partenza ritorno',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownSearch<String>(
                        items: _aeroporti,
                        selectedItem: _safeListValue(caRitorno, _aeroporti),
                        onChanged: (v) => setSt(() => caRitorno = v),
                        popupProps: const PopupProps.menu(showSearchBox: true),
                        clearButtonProps: const ClearButtonProps(isVisible: true),
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration: const InputDecoration(
                            labelText: 'Aeroporto arrivo ritorno',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Bagaglio
                    DropdownSearch<String>(
                      items: const ['mano', 'stiva'],
                      selectedItem: bag,
                      itemAsString: (v) => v == 'stiva' ? 'Bagaglio in stiva' : 'Bagaglio a mano',
                      onChanged: (v) => setSt(() => bag = (v ?? 'mano')),
                      popupProps: const PopupProps.menu(),
                      clearButtonProps: const ClearButtonProps(isVisible: false),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Bagaglio',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Parcheggio + targa
                    SwitchListTile(
                      dense: true,
                      title: const Text('Parcheggio'),
                      value: park,
                      onChanged: (v) => setSt(() => park = v),
                    ),
                    if (park) ...[
                      TextField(
                        controller: TextEditingController(text: targa),
                        onChanged: (v) => targa = v,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Targa veicolo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Stato
                    DropdownSearch<String>(
                      items: kStatiAereo,
                      selectedItem: kStatiAereo.contains(stato) ? stato : 'IN_ATTESA',
                      onChanged: (v) => setSt(() => stato = v ?? 'IN_ATTESA'),
                      popupProps: const PopupProps.menu(),
                      clearButtonProps: const ClearButtonProps(isVisible: false),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: const InputDecoration(
                          labelText: 'Stato',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Note
                    TextField(
                      controller: TextEditingController(text: note),
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (v) => note = v,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
              AsyncFilledButton(
                onPressed: () async {
                  // Validazioni
                  if (personaleSel == null ||
                      cp == null ||
                      ca == null ||
                      commessaSel == null ||
                      orarioSel == null ||
                      orarioSel!.trim().isEmpty) {
                    _snack('Compila: Personale, Partenza, Arrivo, Commessa, Data e Orario andata.', error: true);
                    return;
                  }
                  if (cp == ca) {
                    _snack('Partenza e arrivo devono essere diversi.', error: true);
                    return;
                  }
                  if (park && (targa.trim().isEmpty)) {
                    _snack('Inserisci la targa (parcheggio attivo).', error: true);
                    return;
                  }
                  final hasDataRitorno = dataRitornoSel != null;
                  final hasOrarioRitorno =
                      orarioRitornoSel != null && orarioRitornoSel!.trim().isNotEmpty;
                  if (hasDataRitorno != hasOrarioRitorno) {
                    _snack(
                      'Compila entrambi i campi ritorno (data e orario) oppure lasciali entrambi vuoti.',
                      error: true,
                    );
                    return;
                  }
                  final hasRitorno = hasDataRitorno && hasOrarioRitorno;
                  if (hasRitorno) {
                    if (cpRitorno == null ||
                        caRitorno == null ||
                        cpRitorno!.trim().isEmpty ||
                        caRitorno!.trim().isEmpty) {
                      _snack('Compila anche gli aeroporti di ritorno.', error: true);
                      return;
                    }
                    if (cpRitorno == caRitorno) {
                      _snack('Partenza e arrivo ritorno devono essere diversi.', error: true);
                      return;
                    }
                  }

                  try {
                    await SupabaseService.client.from(kTable).update({
                      'personale_id': personaleSel,
                      'aeroporto_partenza': cp,
                      'aeroporto_arrivo': ca,
                      'data': _iso(dataSel),
                      'orario': orarioSel,
                      'data_ritorno': hasRitorno ? _iso(dataRitornoSel!) : null,
                      'orario_ritorno': hasRitorno ? orarioRitornoSel : null,
                      'aeroporto_partenza_ritorno': hasRitorno ? cpRitorno : null,
                      'aeroporto_arrivo_ritorno': hasRitorno ? caRitorno : null,
                      'commessa_id': commessaSel,
                      'bagaglio': bag,
                      'parcheggio': park,
                      'targa_veicolo': park ? targa : null,
                      'status': stato,
                      'master_note': note,
                    }).eq('id', r.id);
                    await NotificationSender.notifyTrenoAereoAdminChange(
                      bookingType: 'aereo',
                      bookingId: int.parse(r.id),
                      action: 'update',
                      title: 'Prenotazione aerea aggiornata',
                      dtUserUuid: r.dtId,
                    );

                    if (context.mounted) Navigator.pop(context);
                    _snack('Prenotazione aggiornata. Notifica inviata a: ${_notifTargetsLabel(r)}');
                    await _loadRows();
                  } catch (e) {
                    _snack('Errore: $e', error: true);
                  }
                },
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bulkEditSelected() async {
    if (_selectedIds.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    String? statoSel;
    String? commessaSel;
    String? bagSel;
    bool? parkSel;
    final noteCtrl = TextEditingController();
    bool applyNote = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: Text('Modifica multipla (${_selectedIds.length})'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownSearch<String>(
                    items: kStatiAereo,
                    selectedItem: statoSel,
                    onChanged: (v) => setSt(() => statoSel = v),
                    popupProps: const PopupProps.menu(),
                    clearButtonProps: const ClearButtonProps(isVisible: true),
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Nuovo stato (opzionale)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownSearch<String>(
                    items: _commessaOptions.map((e) => e['id']!).toList(),
                    selectedItem: _safeMapValue(commessaSel, _commessaMap),
                    itemAsString: (id) => _commessaMap[id] ?? id,
                    onChanged: (v) => setSt(() => commessaSel = v),
                    popupProps: const PopupProps.menu(showSearchBox: true),
                    clearButtonProps: const ClearButtonProps(isVisible: true),
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Nuova commessa (opzionale)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownSearch<String>(
                    items: const ['mano', 'stiva'],
                    selectedItem: bagSel,
                    itemAsString: (v) => v == 'stiva' ? 'Bagaglio in stiva' : 'Bagaglio a mano',
                    onChanged: (v) => setSt(() => bagSel = v),
                    popupProps: const PopupProps.menu(),
                    clearButtonProps: const ClearButtonProps(isVisible: true),
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Nuovo bagaglio (opzionale)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownSearch<String>(
                    items: const ['SI', 'NO'],
                    selectedItem: parkSel == null ? null : (parkSel! ? 'SI' : 'NO'),
                    onChanged: (v) => setSt(() => parkSel = v == null ? null : (v == 'SI')),
                    popupProps: const PopupProps.menu(),
                    clearButtonProps: const ClearButtonProps(isVisible: true),
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Parcheggio (opzionale)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: applyNote,
                    onChanged: (v) => setSt(() => applyNote = v),
                    title: const Text('Sovrascrivi note'),
                  ),
                  if (applyNote)
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Nuove note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Applica')),
          ],
        ),
      ),
    );
    final noteText = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true) return;
    if (statoSel == null && commessaSel == null && bagSel == null && parkSel == null && !applyNote) {
      _snack('Seleziona almeno un campo da modificare.', error: true);
      return;
    }

    try {
      setState(() => _loading = true);
      int updated = 0;
      for (final r in _selectedRows) {
        final payload = <String, dynamic>{};
        if (statoSel != null) payload['status'] = statoSel;
        if (commessaSel != null) payload['commessa_id'] = commessaSel;
        if (bagSel != null) payload['bagaglio'] = bagSel;
        if (parkSel != null) payload['parcheggio'] = parkSel;
        if (applyNote) payload['master_note'] = noteText;
        await SupabaseService.client.from(kTable).update(payload).eq('id', r.id);
        try {
          await NotificationSender.notifyTrenoAereoAdminChange(
            bookingType: 'aereo',
            bookingId: int.parse(r.id),
            action: 'update',
            title: 'Prenotazione aerea aggiornata',
            dtUserUuid: r.dtId,
          );
        } catch (_) {}
        updated++;
      }
      _snack('Modifica multipla completata ($updated).');
      await _loadRows();
    } catch (e) {
      _snack('Errore modifica multipla: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _rows.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_rows.map((r) => r.id));
      }
    });
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Elimina selezionati (${_selectedIds.length})'),
        content: const Text(
          "Confermi l'eliminazione delle prenotazioni selezionate? L'azione è irreversibile.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() => _loading = true);
      int deleted = 0;
      for (final r in _selectedRows) {
        try {
          await NotificationSender.notifyTrenoAereoAdminChange(
            bookingType: 'aereo',
            bookingId: int.parse(r.id),
            action: 'delete',
            title: 'Prenotazione aerea eliminata',
            dtUserUuid: r.dtId,
          );
        } catch (_) {}
        await SupabaseService.client.from(kTable).delete().eq('id', r.id);
        deleted++;
      }
      _snack('Eliminazione multipla completata ($deleted).');
      await _loadRows();
    } catch (e) {
      _snack('Errore eliminazione multipla: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildMobileRows(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final persona = (_personaleMap[r.personaleId] ?? r.personaleId).trim();
        final commessa = (_commessaMap[r.commessaId] ?? r.commessaId).trim();
        final reqId = r.requestedByUserId.trim();
        final isAssistant = reqId.isNotEmpty &&
            (_utentiRoleByIdMap[reqId]?.toLowerCase().trim() == 'assistente_dt');
        final rich = isAssistant ? (_utentiIdMap[reqId] ?? reqId) : (_dtMap[r.dtId] ?? r.dtId);
        final color = _statusColor(r.stato);
        final ritornoDiverso =
            (r.arrivoRitorno.trim().isNotEmpty && r.arrivoRitorno.trim() != r.partenza.trim());

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _selectedIds.contains(r.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(r.id);
                          } else {
                            _selectedIds.remove(r.id);
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Text(
                        persona.isEmpty ? r.personaleId : persona,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _atCopyButton(_personaleEmailMap[r.personaleId]),
                  ],
                ),
                Text('Data: ${r.data}  |  Orario: ${r.orario}'),
                if (r.dataRitorno.trim().isNotEmpty || r.orarioRitorno.trim().isNotEmpty)
                  Text('Ritorno: ${r.dataRitorno} ${r.orarioRitorno}'.trim()),
                Text('Da ${r.partenza} a ${r.arrivo}'),
                if (ritornoDiverso) Text('Ritorno diverso: ${r.arrivoRitorno}'),
                Text('Commessa: ${commessa.isEmpty ? r.commessaId : commessa}'),
                Text('Bagaglio: ${r.bagaglio == 'stiva' ? 'In stiva' : 'A mano'}'),
                Text('Parcheggio: ${r.parcheggio ? 'SI' : 'No'}${r.targa.trim().isEmpty ? '' : ' · Targa: ${r.targa}'}'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Modifica stato',
                      onSelected: (v) => _updateStato(r, v),
                      itemBuilder: (_) => kStatiAereo
                          .map((s) => PopupMenuItem(value: s, child: Text(s)))
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          r.stato,
                          style: TextStyle(color: color, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Modifica',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(r),
                    ),
                    IconButton(
                      tooltip: 'Elimina',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _delete(r),
                    ),
                  ],
                ),
                if (r.note.trim().isNotEmpty)
                  NotePreviewText(
                    note: r.note,
                    prefix: 'Note: ',
                    maxChars: 10,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Richiedente: ${rich.isEmpty ? r.dtId : rich}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _atCopyButton(_richiedenteEmail(r)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Inserita il: ${_insertedAtLabel(r.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _useCardLayout(BuildContext context, double contentWidth) =>
      useMobileUi(context) || contentWidth < _kMinWidthForTable;

  double _filterFieldWidth(double contentWidth) {
    const gap = 10.0;
    final w = contentWidth - 16;
    if (w < 520) return w;
    if (w < 860) return (w - gap) / 2;
    if (w < 1200) return (w - gap * 2) / 3;
    return 200;
  }

  List<Widget> _buildAppBarActions({required bool compact}) {
    if (compact) {
      return [
        PopupMenuButton<String>(
          tooltip: 'Azioni',
          onSelected: (key) {
            switch (key) {
              case 'select':
                if (_rows.isNotEmpty) _toggleSelectAll();
                break;
              case 'edit':
                if (_selectedIds.isNotEmpty) _bulkEditSelected();
                break;
              case 'delete':
                if (_selectedIds.isNotEmpty) _bulkDeleteSelected();
                break;
              case 'export':
                _exportExcel();
                break;
              case 'refresh':
                _loadRows();
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'select',
              enabled: _rows.isNotEmpty,
              child: Row(
                children: [
                  Icon(
                    _selectedIds.length == _rows.length && _rows.isNotEmpty
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _selectedIds.length == _rows.length && _rows.isNotEmpty
                        ? 'Deseleziona tutto'
                        : 'Seleziona tutto',
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              enabled: _selectedIds.isNotEmpty,
              child: const Row(
                children: [
                  Icon(Icons.edit_note),
                  SizedBox(width: 10),
                  Text('Modifica selezionati'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: _selectedIds.isNotEmpty,
              child: const Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Elimina selezionati'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_download),
                  SizedBox(width: 10),
                  Text('Esporta Excel'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 10),
                  Text('Ricarica'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ];
    }
    return [
      IconButton(
        tooltip: _selectedIds.length == _rows.length && _rows.isNotEmpty
            ? 'Deseleziona tutto'
            : 'Seleziona tutto',
        icon: Icon(
          _selectedIds.length == _rows.length && _rows.isNotEmpty
              ? Icons.deselect
              : Icons.select_all,
        ),
        onPressed: _rows.isEmpty ? null : _toggleSelectAll,
      ),
      IconButton(
        tooltip: 'Modifica selezionati',
        icon: const Icon(Icons.edit_note),
        onPressed: _selectedIds.isEmpty ? null : _bulkEditSelected,
      ),
      IconButton(
        tooltip: 'Elimina selezionati',
        icon: const Icon(Icons.delete_sweep, color: Colors.red),
        onPressed: _selectedIds.isEmpty ? null : _bulkDeleteSelected,
      ),
      IconButton(
        tooltip: 'Esporta Excel',
        icon: const Icon(Icons.file_download),
        onPressed: _exportExcel,
      ),
      IconButton(
        tooltip: 'Ricarica',
        icon: const Icon(Icons.refresh),
        onPressed: _loadRows,
      ),
      const SizedBox(width: 8),
    ];
  }

  Widget _buildFiltersPanel({
    required double contentWidth,
    required String? safePersonaleF,
    required String? safeCommessaF,
    required String? safeDtF,
    required String? safePartenzaF,
  }) {
    final fw = _filterFieldWidth(contentWidth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: _showAllBookings
                ? () async => _toggleQuickLoadMode(showAll: false)
                : null,
            icon: const Icon(Icons.hourglass_top),
            label: const Text('Solo in attesa'),
          ),
          FilledButton.icon(
            onPressed: !_showAllBookings
                ? () async => _toggleQuickLoadMode(showAll: true)
                : null,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Visualizza Confermate'),
          ),
          SizedBox(
            width: fw,
            child: DropdownSearch<String>(
                            items: kStatiAereo,
                            selectedItem: _statoF,
                            onChanged: (v) async {
                              setState(() => _statoF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => _statoF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Stato',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
            ),
          ),
          SizedBox(
            width: fw,
            child: DropdownSearch<String>(
                            items: _aeroporti,
                            selectedItem: safePartenzaF,
                            onChanged: (v) async {
                              setState(() => _partenzaF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => _partenzaF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Partenza',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
            ),
          ),
          SizedBox(
            width: fw,
            child: DropdownSearch<String>(
                            items: _commessaOptions.map((e) => e['id']!).toList(),
                            selectedItem: safeCommessaF,
                            itemAsString: (id) => _commessaMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => _commessaF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => _commessaF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Commessa',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
            ),
          ),
          SizedBox(
            width: fw,
            child: DropdownSearch<String>(
                            items: _personaleOptions.map((e) => e['id']!).toList(),
                            selectedItem: safePersonaleF,
                            itemAsString: (id) => _personaleMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => _personaleF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => _personaleF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Personale',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
            ),
          ),
          SizedBox(
            width: fw,
            child: DropdownSearch<String>(
                            items: _dtOptions.map((e) => e['id']!).toList(),
                            selectedItem: safeDtF,
                            itemAsString: (id) => _dtMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => _dtF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => _dtF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Richiedente',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.clear_all),
            label: const Text('Pulisci'),
            onPressed: () async {
              setState(() {
                _showAllBookings = true;
                _statoF = _personaleF = _commessaF = _dtF = _partenzaF = null;
              });
              await _loadRows();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            'Scorri orizzontalmente per vedere tutte le colonne',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
          ),
        ),
        Expanded(
          child: Scrollbar(
                                  controller: _vCtrl,
                                  thumbVisibility: true,
                                  trackVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _vCtrl,
                                    scrollDirection: Axis.vertical,
                                    child: Scrollbar(
                                      controller: _hCtrl,
                                      thumbVisibility: true,
                                      trackVisibility: true,
                                      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                                      child: SingleChildScrollView(
                                        controller: _hCtrl,
                                        scrollDirection: Axis.horizontal,
                                        child: DefaultTextStyle.merge(
                                          style: const TextStyle(fontSize: 13),
                                          child: DataTable(
                                columnSpacing: 10,
                                horizontalMargin: 12,
                                headingRowHeight: 38,
                                dataRowMinHeight: 40,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Data')),
                                  DataColumn(label: Text('Orario andata')),
                                  DataColumn(label: Text('Data ritorno')),
                                  DataColumn(label: Text('Orario ritorno')),
                                  DataColumn(label: Text('Personale')),
                                  DataColumn(label: Text('Partenza')),
                                  DataColumn(label: Text('Arrivo')),
                                  DataColumn(label: Text('Ritorno diverso')),
                                  DataColumn(label: Text('Commessa')),
                                  DataColumn(label: Text('Bagaglio')),
                                  DataColumn(label: Text('Parcheggio')),
                                  DataColumn(label: Text('Targa')),
                                  DataColumn(label: Text('Stato')),
                                  DataColumn(label: Text('Note')),
                                  DataColumn(label: Text('Azioni')),
                                  DataColumn(label: Text('Richiedente')),
                                  DataColumn(label: Text('Inserita il')),
                                ],
                                rows: _rows.map((r) {
                                  final persona = (_personaleMap[r.personaleId] ?? r.personaleId).trim();
                                  final commessa = (_commessaMap[r.commessaId] ?? r.commessaId).trim();
                                  final reqId = r.requestedByUserId.trim();
                                  final isAssistant = reqId.isNotEmpty &&
                                      (_utentiRoleByIdMap[reqId]
                                              ?.toLowerCase()
                                              .trim() ==
                                          'assistente_dt');
                                  final rich = isAssistant
                                      ? (_utentiIdMap[reqId] ?? reqId)
                                      : (_dtMap[r.dtId] ?? r.dtId);

                                  final color = _statusColor(r.stato);
                                  final ritornoDiverso = (r.arrivoRitorno.trim().isNotEmpty &&
                                      r.arrivoRitorno.trim() != r.partenza.trim());

                                  final insertedAtLabel = _insertedAtLabel(r.createdAt);
                                  return DataRow(
                                    selected: _selectedIds.contains(r.id),
                                    onSelectChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selectedIds.add(r.id);
                                        } else {
                                          _selectedIds.remove(r.id);
                                        }
                                      });
                                    },
                                    cells: [
                                      DataCell(
                                        Tooltip(
                                          message:
                                              'Inserita il: ${(() {
                                            final dt = DateTime.tryParse(r.createdAt);
                                            return dt == null ? '—' : formatDateTimeIt(dt);
                                          })()}',
                                          waitDuration:
                                              const Duration(milliseconds: 220),
                                          child: Text(formatDateDdMmYyyy(r.data)),
                                        ),
                                      ),
                                      DataCell(Text(r.orario)),
                                      DataCell(Text(formatDateDdMmYyyy(r.dataRitorno))),
                                      DataCell(Text(r.orarioRitorno)),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 200),
                                              child: Text(
                                                persona.isEmpty
                                                    ? r.personaleId
                                                    : persona,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            _atCopyButton(
                                                _personaleEmailMap[r.personaleId]),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 120),
                                          child: Text(
                                            r.partenza,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 120),
                                          child: Text(
                                            r.arrivo,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          ritornoDiverso ? r.arrivoRitorno : '',
                                        ),
                                      ),
                                      DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 140),
                                          child: Text(
                                            commessa.isEmpty ? r.commessaId : commessa,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(r.bagaglio == 'stiva' ? 'In stiva' : 'A mano')),
                                      DataCell(Text(r.parcheggio ? 'SI' : 'No')),
                                      DataCell(Text(r.targa)),
                                      // Stato con badge + popup per modifica
                                      DataCell(
                                        PopupMenuButton<String>(
                                          tooltip: 'Modifica stato',
                                          onSelected: (v) => _updateStato(r, v),
                                          itemBuilder: (_) => kStatiAereo
                                              .map((s) => PopupMenuItem(value: s, child: Text(s)))
                                              .toList(),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              r.stato,
                                              style: TextStyle(color: color, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(_buildCompactNoteCell(r.note)),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Modifica (dialog)',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                              iconSize: 20,
                                              icon: const Icon(Icons.edit_outlined),
                                              onPressed: () => _edit(r),
                                            ),
                                            const SizedBox(width: 2),
                                            IconButton(
                                              tooltip: 'Elimina',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                              iconSize: 20,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                              ),
                                              onPressed: () => _delete(r),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 120),
                                              child: Text(
                                                rich.isEmpty ? r.dtId : rich,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            _atCopyButton(_richiedenteEmail(r)),
                                          ],
                                        ),
                                      ),
                                      DataCell(Text(insertedAtLabel)),
                                    ].map((c) => _decorateCellWithInsertedAtTooltip(c, insertedAtLabel)).toList(),
                                  );
                                }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
        ),
      ],
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final safePersonaleF = _safeMapValue(_personaleF, _personaleMap);
    final safeCommessaF = _safeMapValue(_commessaF, _commessaMap);
    final safeDtF = _safeMapValue(_dtF, _dtMap);
    final safePartenzaF = _safeListValue(_partenzaF, _aeroporti);
    final compactAppBar = useMobileUi(context);

    final compactTheme = Theme.of(context).copyWith(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Theme(
      data: compactTheme,
      child: Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(
          title: const ResponsiveAppBarTitle(title: 'Admin Aerei'),
          leading: IconButton(
            tooltip: 'Indietro',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            },
          ),
          actions: _buildAppBarActions(compact: compactAppBar),
        )),
        body: PageWithTopLogo(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth;
                    final useCards = _useCardLayout(context, contentWidth);

                    return Column(
                      children: [
                        _buildFiltersPanel(
                          contentWidth: contentWidth,
                          safePersonaleF: safePersonaleF,
                          safeCommessaF: safeCommessaF,
                          safeDtF: safeDtF,
                          safePartenzaF: safePartenzaF,
                        ),
                        Expanded(
                          child: useCards
                              ? _buildMobileRows(context)
                              : _buildDesktopTable(),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ---- MODEL identico ----
class _AereoRow {
  final String id;
  final String createdAt;
  final String data;
  final String orario;
  final String dataRitorno;
  final String orarioRitorno;
  final String personaleId;
  final String requestedByUserId;
  final String partenza;
  final String arrivo;
  final String partenzaRitorno;
  final String arrivoRitorno;
  final String commessaId;
  final String bagaglio;
  final bool parcheggio;
  final String targa;
  final String stato;
  final String note;
  final String dtId;

  _AereoRow({
    required this.id,
    required this.createdAt,
    required this.data,
    required this.orario,
    required this.dataRitorno,
    required this.orarioRitorno,
    required this.personaleId,
    required this.requestedByUserId,
    required this.partenza,
    required this.arrivo,
    required this.partenzaRitorno,
    required this.arrivoRitorno,
    required this.commessaId,
    required this.bagaglio,
    required this.parcheggio,
    required this.targa,
    required this.stato,
    required this.note,
    required this.dtId,
  });
}