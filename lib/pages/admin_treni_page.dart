import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
import 'package:organizzazione_personale_cronos/services/notification_sender.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

const List<String> kStatiTreno = ['IN_ATTESA', 'CONFERMATA', 'RIFIUTATA'];

class AdminTreniPage extends StatefulWidget {
  final int adminId;
  const AdminTreniPage({super.key, required this.adminId});

  @override
  State<AdminTreniPage> createState() => _AdminTreniPageState();
}

class _AdminTreniPageState extends State<AdminTreniPage> {
  static const String kTable = 'bookings_treno';

  bool loading = true;
  bool _showAllBookings = false;

  // Filtri
  String? statoF, personaleF, commessaF, partenzaF, dtF;

  // Dizionari
  final Map<String, String> personaleMap = {};
  final Map<String, String> commessaMap = {};
  final Map<String, String> dtMap = {};
  final Map<String, String> utentiIdMap = {}; // users.id (int) -> label
  final Map<String, String> utentiRoleByIdMap = {}; // users.id (int) -> role db
  final Map<String, String> personaleEmailMap = {}; // personale id -> email
  final Map<String, String> utentiEmailByIdMap = {}; // users.id -> email o username
  final Map<String, String> utentiEmailByUuidMap = {}; // users.id_uuid -> email o username
  final List<String> stazioni = []; // <== TUTTE (paginazione)

  // Opzioni filtrate/safe come Pernotti
  final List<Map<String, String>> personaleOpt = [];
  final List<Map<String, String>> commessaOpt = [];
  final List<Map<String, String>> dtOpt = [];

  List<_TrenoRow> rows = [];
  final Set<String> _selectedIds = <String>{};

  String personaleCol = 'id_uuid';
  String commessaCol = 'id_uuid';

  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    statoF = 'IN_ATTESA';
    _bootstrap();
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  // ===== INIT =====
  Future<void> _bootstrap() async {
    try {
      await _resolveCols();
      await _loadMaps();
      await _loadRows();
    } catch (e) {
      _snack("Errore init: $e", error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resolveCols() async {
    try {
      await SupabaseService.client.from('personale').select('id_uuid').limit(1);
      personaleCol = 'id_uuid';
    } catch (_) {
      personaleCol = 'id';
    }

    try {
      await SupabaseService.client.from('commesse').select('id_uuid').limit(1);
      commessaCol = 'id_uuid';
    } catch (_) {
      commessaCol = 'id';
    }
  }

  // ===== UTILS =====
  List<Map<String, String>> _toOptions(Map<String, String> m) {
    final tmp = <String, String>{};
    for (final e in m.entries) {
      if (e.key.isNotEmpty) tmp[e.key] = e.value;
    }
    final list = tmp.entries.map((e) => {'id': e.key, 'label': e.value}).toList();
    list.sort((a, b) => a['label']!.compareTo(b['label']!));
    return list;
  }

  String? _safeMapVal(String? v, Map<String, String> map) =>
      (v != null && map.containsKey(v)) ? v : null;

  String? _safeListVal(String? v, List<String> list) =>
      (v != null && list.contains(v)) ? v : null;

  String _iso(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
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

  /// Email del richiedente mostrato in tabella (assistente DT vs DT della prenotazione).
  String? _richiedenteEmail(_TrenoRow r) {
    final reqId = r.requestedByUserId.trim();
    final isAssistant = reqId.isNotEmpty &&
        (utentiRoleByIdMap[reqId]?.toLowerCase().trim() == 'assistente_dt');
    if (isAssistant && reqId.isNotEmpty) {
      return utentiEmailByIdMap[reqId];
    }
    final dt = r.dtId.trim();
    if (dt.isNotEmpty) {
      return utentiEmailByUuidMap[dt] ?? utentiEmailByIdMap[dt];
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

  String _notifTargetsLabel(_TrenoRow r) {
    final dt = (dtMap[r.dtId] ?? '').trim();
    final dip = (personaleMap[r.personaleId] ?? '').trim();
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

  // ---------- NEW: scarica TUTTE le stazioni a blocchi da 1000 ----------
  Future<List<String>> _fetchAllStazioni({bool soloAttive = true}) async {
    const pageSize = 1000;
    int from = 0;
    final List<String> acc = [];

    while (true) {
      final base = SupabaseService.client
          .from('stazioni')
          .select('nome, attiva');

      // filtro PRIMA di order/range (altrimenti .eq non è disponibile)
      final filtered = soloAttive ? base.eq('attiva', true) : base;

      final page = await filtered
          .order('nome', ascending: true)
          .range(from, from + pageSize - 1);

      final list = List<Map<String, dynamic>>.from(page as List);
      if (list.isEmpty) break;

      acc.addAll(list.map((e) => (e['nome'] ?? '').toString()));

      if (list.length < pageSize) break; // ultima pagina
      from += pageSize;
    }

    return acc;
  }

  // ===== LOAD DIZIONARI =====
  Future<void> _loadMaps() async {
    // personale
    List<dynamic> pRows;
    try {
      pRows = await SupabaseService.client
          .from('personale')
          .select('$personaleCol, full_name, active, email')
          .eq('active', true)
          .order('full_name') as List<dynamic>;
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      pRows = await SupabaseService.client
          .from('personale')
          .select('$personaleCol, full_name, active')
          .eq('active', true)
          .order('full_name') as List<dynamic>;
    }
    personaleMap.clear();
    personaleEmailMap.clear();
    final pList = pRows
        .map((e) => MapEntry(
              (e[personaleCol] ?? '').toString(),
              (e['full_name'] ?? '').toString(),
            ))
        .toList()
      ..sort((a, b) =>
          a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()));
    personaleMap.addEntries(pList);
    for (final e in pRows) {
      final k = (e[personaleCol] ?? '').toString();
      final em = (e['email'] ?? '').toString().trim();
      if (k.isNotEmpty && em.isNotEmpty) personaleEmailMap[k] = em;
    }

    // commesse
    final c = await SupabaseService.client
        .from('commesse')
        .select('$commessaCol, nome, active')
        .eq('active', true)
        .order('nome');
    commessaMap
      ..clear()
      ..addEntries(
        ((c as List)
              .map((e) => MapEntry(
                    (e[commessaCol] ?? '').toString(),
                    (e['nome'] ?? '').toString(),
                  ))
              .toList()
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );

    // utenti (DT)
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

    dtMap.clear();
    utentiIdMap.clear();
    utentiRoleByIdMap.clear();
    utentiEmailByIdMap.clear();
    utentiEmailByUuidMap.clear();
    for (final e in uRows) {
      final m = e as Map<String, dynamic>;
      final id = (m['id'] ?? '').toString();
      final uuid = (m['id_uuid'] ?? '').toString();
      final label = (m['full_name'] ?? m['username'] ?? '').toString();
      final roleDb = (m['role'] ?? '').toString().toLowerCase().trim();
      final mail =
          (m['email'] ?? m['username'] ?? '').toString().trim();
      // dtMap usa anche chiavi UUID (più affidabile per dt_user_uuid),
      // ma per "Richiedente" useremo anche users.id (int) -> label.
      if (id.isNotEmpty) utentiIdMap[id] = label;
      if (id.isNotEmpty && roleDb.isNotEmpty) utentiRoleByIdMap[id] = roleDb;
      if (id.isNotEmpty && mail.isNotEmpty) utentiEmailByIdMap[id] = mail;
      if (uuid.length >= 32 && mail.isNotEmpty) utentiEmailByUuidMap[uuid] = mail;
      if (id.length >= 32) dtMap[id] = label;
      if (uuid.length >= 32) dtMap[uuid] = label;
    }

    // ---------- NEW: stazioni (TUTTE, paginate) ----------
    final sAll = await _fetchAllStazioni(soloAttive: true);
    stazioni
      ..clear()
      ..addAll(sAll);

    // opzioni ordinate
    personaleOpt
      ..clear()
      ..addAll(_toOptions(personaleMap));
    commessaOpt
      ..clear()
      ..addAll(_toOptions(commessaMap));
    dtOpt
      ..clear()
      ..addAll(_toOptions(dtMap));
  }

  /// Query filtrata (senza order/range): serve per paginare oltre il max_rows di PostgREST.
  dynamic _treniRowsQuery() {
    dynamic q = SupabaseService.client.from(kTable).select();

    // Mostra solo prenotazioni già inoltrate agli admin (workflow nuovo).
    // Se la colonna non esiste (schema vecchio), ignoriamo il filtro.
    try {
      q = q.eq('workflow_status', 'INVIATA_ADMIN');
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
    } catch (_) {}

    if (statoF?.isNotEmpty == true) q = q.eq('status', statoF);
    if (partenzaF?.isNotEmpty == true) q = q.eq('stazione_partenza', partenzaF);
    if (commessaF?.isNotEmpty == true) q = q.eq('commessa_id', commessaF);
    if (personaleF?.isNotEmpty == true) q = q.eq('personale_id', personaleF);
    if (dtF?.isNotEmpty == true) q = q.eq('dt_user_uuid', dtF);
    return q;
  }

  // ===== LOAD ROWS =====
  Future<void> _loadRows() async {
    rows = [];
    _selectedIds.clear();
    setState(() => loading = true);

    try {
      const pageSize = 1000;
      int from = 0;
      final res = <dynamic>[];
      while (true) {
        final page = await _treniRowsQuery()
            .order('data', ascending: false)
            .range(from, from + pageSize - 1);
        final list = List<dynamic>.from(page as List);
        if (list.isEmpty) break;
        res.addAll(list);
        from += list.length;
      }

      for (final r in res) {
        rows.add(_TrenoRow(
          id: (r['id'] ?? '').toString(),
          createdAt: (r['created_at'] ?? '').toString(),
          data: (r['data'] ?? '').toString(),
          orario: (r['orario'] ?? '').toString(),
          dataRitorno: (r['data_ritorno'] ?? '').toString(),
          orarioRitorno: (r['orario_ritorno'] ?? '').toString(),
          personaleId: (r['personale_id'] ?? '').toString(),
          partenza: (r['stazione_partenza'] ?? '').toString(),
          arrivo: (r['stazione_arrivo'] ?? '').toString(),
          partenzaRitorno: (r['stazione_partenza_ritorno'] ?? '').toString(),
          arrivoRitorno: (r['stazione_arrivo_ritorno'] ?? '').toString(),
          commessaId: (r['commessa_id'] ?? '').toString(),
          stato: (r['status'] ?? '').toString(),
          note: (r['master_note'] ?? '').toString(),
          requestedByUserId: (r['requested_by_user_id'] ?? '').toString(),
          dtId: (r['dt_user_uuid'] ?? '').toString(),
        ));
      }
    } catch (e) {
      _snack("Errore caricamento: $e", error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggleQuickLoadMode({required bool showAll}) async {
    setState(() {
      _showAllBookings = showAll;
      statoF = showAll ? null : 'IN_ATTESA';
      _selectedIds.clear();
    });
    await _loadRows();
  }

  List<_TrenoRow> get _selectedRows =>
      rows.where((r) => _selectedIds.contains(r.id)).toList();

  // ===== EXPORT EXCEL =====
  Future<void> _exportExcel() async {
    try {
      if (rows.isEmpty) {
        _snack("Nessun dato da esportare", error: true);
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel['Treni'];

      sheet.appendRow([
        'Data',
        'Orario andata',
        'Data ritorno',
        'Orario ritorno',
        'Personale',
        'Partenza',
        'Arrivo',
        'Ritorno diverso',
        'Commessa',
        'Stato',
        'Note',
        'Richiedente',
        'Inserita il',
      ]);

      for (final r in rows) {
        final ritornoDiverso =
            (r.arrivoRitorno.trim().isNotEmpty && r.arrivoRitorno.trim() != r.partenza.trim());
        final reqId = r.requestedByUserId.trim();
        final isAssistant = reqId.isNotEmpty &&
            (utentiRoleByIdMap[reqId]?.toLowerCase().trim() == 'assistente_dt');
        final richText = isAssistant
            ? (utentiIdMap[reqId] ?? reqId)
            : (dtMap[r.dtId] ?? r.dtId);
        sheet.appendRow([
          r.data,
          r.orario,
          r.dataRitorno,
          r.orarioRitorno,
          (personaleMap[r.personaleId] ?? r.personaleId),
          r.partenza,
          r.arrivo,
          ritornoDiverso ? r.arrivoRitorno : '',
          (commessaMap[r.commessaId] ?? r.commessaId),
          r.stato,
          r.note,
          (richText).trim(),
          _insertedAtLabel(r.createdAt),
        ]);
      }

      final bytes = Uint8List.fromList(excel.encode()!);

      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Treni',
        bytes: bytes,
      );
      if (!saved) return;
      _snack("Export Excel completato: ${ExcelExportHelper.lastSavedPath ?? ''}");
    } catch (e) {
      _snack("Errore export: $e", error: true);
    }
  }

  // ===== AZIONI =====
  Future<void> _updateStato(_TrenoRow r, String nuovo) async {
    if (!await ensureCanPersist(context)) return;
    try {
      await SupabaseService.client
          .from(kTable)
          .update({'status': nuovo}).eq('id', r.id);
      final action = nuovo.toUpperCase().trim() == 'CONFERMATA' ? 'confirm' : 'update';
      final title = nuovo.toUpperCase().trim() == 'CONFERMATA'
          ? 'Prenotazione treno confermata'
          : 'Prenotazione treno aggiornata';
      await NotificationSender.notifyUserForBooking(
        dtUserId: r.dtId,
        bookingId: int.parse(r.id),
        action: action,
        title: title,
        bookingType: 'treno',
      );
      _snack("Stato aggiornato. Notifica inviata a: ${_notifTargetsLabel(r)}");
      await _loadRows();
    } catch (e) {
      _snack("Errore aggiornamento: $e", error: true);
    }
  }

  Future<void> _delete(_TrenoRow r) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Elimina prenotazione treno"),
        content: const Text("Confermi l'eliminazione?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annulla")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Elimina")),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // Allineato ad Admin Aerei: stesso helper dell'eliminazione singola.
      await NotificationSender.notifyUserForBooking(
        dtUserId: r.dtId,
        bookingId: int.parse(r.id),
        action: 'delete',
        title: 'Prenotazione treno eliminata',
        bookingType: 'treno',
      );
      // Notifica PRIMA della cancellazione: l'Edge Function legge la prenotazione
      // dal DB per costruire testo (Per/Tipo/Data). Se cancelliamo prima otteniamo N/D.
      await SupabaseService.client.from(kTable).delete().eq('id', r.id);
      _snack("Prenotazione eliminata. Notifica inviata a: ${_notifTargetsLabel(r)}");
      await _loadRows();
    } catch (e) {
      _snack("Errore eliminazione: $e", error: true);
    }
  }

  // ===== DIALOG MODIFICA (DropdownSearch con ricerca — usa stazioni TUTTE) =====
  Future<void> _edit(_TrenoRow r) async {
    if (!await ensureCanPersist(context)) return;
    String? personaleSel = r.personaleId;
    String? partenzaSel = r.partenza;
    String? arrivoSel = r.arrivo;
    String? partenzaRitornoSel =
        r.partenzaRitorno.trim().isNotEmpty ? r.partenzaRitorno : r.arrivo;
    String? arrivoRitornoSel =
        r.arrivoRitorno.trim().isNotEmpty ? r.arrivoRitorno : r.partenza;
    String? commessaSel = r.commessaId;

    DateTime dataSel = DateTime.tryParse(r.data) ?? DateTime.now();

    // Parsing orario robusto
    TimeOfDay? orarioSel;
    try {
      final parts = (r.orario).split(':');
      final hh = int.tryParse(parts[0]) ?? 0;
      final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      orarioSel = TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
    } catch (_) {
      orarioSel = TimeOfDay.now();
    }

    String statoSel = kStatiTreno.contains(r.stato) ? r.stato : 'IN_ATTESA';
    String noteSel = r.note;
    DateTime? dataRitornoSel;
    if (r.dataRitorno.trim().isNotEmpty) {
      try {
        dataRitornoSel = DateTime.parse(r.dataRitorno);
      } catch (_) {}
    }
    TimeOfDay? orarioRitornoSel;
    if (r.orarioRitorno.trim().isNotEmpty) {
      try {
        final parts = r.orarioRitorno.split(':');
        final hh = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        orarioRitornoSel =
            TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
      } catch (_) {}
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) {
          return AlertDialog(
            title: const Text("Modifica prenotazione treno"),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // PERSONALE (id -> label)
                    DropdownSearch<String>(
                      items: personaleOpt.map((e) => e['id']!).toList(),
                      selectedItem: _safeMapVal(personaleSel, personaleMap),
                      itemAsString: (id) => personaleMap[id] ?? id,
                      onChanged: (v) => setSt(() => personaleSel = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: "Personale",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // PARTENZA (stringa semplice) — usa stazioni (tutte)
                    DropdownSearch<String>(
                      items: stazioni,
                      selectedItem: _safeListVal(partenzaSel, stazioni),
                      onChanged: (v) => setSt(() => partenzaSel = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: "Stazione di partenza",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ARRIVO (stringa semplice) — usa stazioni (tutte)
                    DropdownSearch<String>(
                      items: stazioni,
                      selectedItem: _safeListVal(arrivoSel, stazioni),
                      onChanged: (v) => setSt(() => arrivoSel = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: "Stazione di arrivo",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // COMMESSA (id -> label)
                    DropdownSearch<String>(
                      items: commessaOpt.map((e) => e['id']!).toList(),
                      selectedItem: _safeMapVal(commessaSel, commessaMap),
                      itemAsString: (id) => commessaMap[id] ?? id,
                      onChanged: (v) => setSt(() => commessaSel = v),
                      popupProps: const PopupProps.menu(showSearchBox: true),
                      clearButtonProps: const ClearButtonProps(isVisible: true),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: "Commessa",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // DATA
                    Row(
                      children: [
                        Expanded(
                          child: Text("Data: ${_displayDate(dataSel)}"),
                        ),
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
                          child: const Text("Cambia"),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ORARIO
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Orario andata: ${orarioSel?.format(context) ?? '--:--'}",
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: orarioSel ?? TimeOfDay.now(),
                            );
                            if (t != null) setSt(() => orarioSel = t);
                          },
                          child: const Text("Orario andata"),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    // DATA RITORNO
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Data ritorno: ${dataRitornoSel == null ? '--' : _displayDate(dataRitornoSel!)}",
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
                          child: const Text("Data ritorno"),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setSt(() => dataRitornoSel = null),
                          child: const Text("Azzera"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ORARIO RITORNO
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Orario ritorno: ${orarioRitornoSel?.format(context) ?? '--:--'}",
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: orarioRitornoSel ?? TimeOfDay.now(),
                            );
                            if (t != null) setSt(() => orarioRitornoSel = t);
                          },
                          child: const Text("Orario ritorno"),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setSt(() => orarioRitornoSel = null),
                          child: const Text("Azzera"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // STAZIONI RITORNO (solo se ritorno presente)
                    if (dataRitornoSel != null || orarioRitornoSel != null) ...[
                      DropdownSearch<String>(
                        items: stazioni,
                        selectedItem: _safeListVal(partenzaRitornoSel, stazioni),
                        onChanged: (v) => setSt(() => partenzaRitornoSel = v),
                        popupProps: const PopupProps.menu(showSearchBox: true),
                        clearButtonProps: const ClearButtonProps(isVisible: true),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: "Stazione partenza ritorno",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownSearch<String>(
                        items: stazioni,
                        selectedItem: _safeListVal(arrivoRitornoSel, stazioni),
                        onChanged: (v) => setSt(() => arrivoRitornoSel = v),
                        popupProps: const PopupProps.menu(showSearchBox: true),
                        clearButtonProps: const ClearButtonProps(isVisible: true),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: "Stazione arrivo ritorno",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // STATO
                    DropdownSearch<String>(
                      items: kStatiTreno,
                      selectedItem: kStatiTreno.contains(statoSel) ? statoSel : 'IN_ATTESA',
                      onChanged: (v) => setSt(() => statoSel = v ?? 'IN_ATTESA'),
                      popupProps: const PopupProps.menu(),
                      clearButtonProps: const ClearButtonProps(isVisible: false),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: "Stato",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // NOTE
                    TextFormField(
                      initialValue: noteSel,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: "Note",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => noteSel = v,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annulla"),
              ),
              AsyncFilledButton(
                onPressed: () async {
                  if (personaleSel == null ||
                      partenzaSel == null ||
                      arrivoSel == null ||
                      commessaSel == null ||
                      orarioSel == null) {
                    _snack("Compila tutti i campi", error: true);
                    return;
                  }

                  if (partenzaSel == arrivoSel) {
                    _snack("Partenza e arrivo devono essere diversi", error: true);
                    return;
                  }
                  final hasDataRitorno = dataRitornoSel != null;
                  final hasOrarioRitorno = orarioRitornoSel != null;
                  if (hasDataRitorno != hasOrarioRitorno) {
                    _snack(
                      "Compila entrambi i campi ritorno (data e orario) oppure lasciali entrambi vuoti.",
                      error: true,
                    );
                    return;
                  }
                  final hasRitorno = hasDataRitorno && hasOrarioRitorno;
                  if (hasRitorno) {
                    if (partenzaRitornoSel == null ||
                        arrivoRitornoSel == null ||
                        partenzaRitornoSel!.trim().isEmpty ||
                        arrivoRitornoSel!.trim().isEmpty) {
                      _snack("Compila anche le stazioni di ritorno.", error: true);
                      return;
                    }
                    if (partenzaRitornoSel == arrivoRitornoSel) {
                      _snack("Partenza e arrivo ritorno devono essere diversi", error: true);
                      return;
                    }
                  }

                  final orarioStr =
                      "${orarioSel!.hour.toString().padLeft(2,'0')}:${orarioSel!.minute.toString().padLeft(2,'0')}";
                  final orarioRitornoStr = orarioRitornoSel == null
                      ? null
                      : "${orarioRitornoSel!.hour.toString().padLeft(2,'0')}:${orarioRitornoSel!.minute.toString().padLeft(2,'0')}";

                  try {
                    await SupabaseService.client.from(kTable).update({
                      'personale_id': personaleSel,
                      'stazione_partenza': partenzaSel,
                      'stazione_arrivo': arrivoSel,
                      'data': _iso(dataSel),
                      'orario': orarioStr,
                      'data_ritorno': hasRitorno ? _iso(dataRitornoSel!) : null,
                      'orario_ritorno': hasRitorno ? orarioRitornoStr : null,
                      'stazione_partenza_ritorno': hasRitorno ? partenzaRitornoSel : null,
                      'stazione_arrivo_ritorno': hasRitorno ? arrivoRitornoSel : null,
                      'commessa_id': commessaSel,
                      'status': statoSel,
                      'master_note': noteSel,
                    }).eq('id', r.id);
                    await NotificationSender.notifyTrenoAereoAdminChange(
                      bookingType: 'treno',
                      bookingId: int.parse(r.id),
                      action: 'update',
                      title: 'Prenotazione treno aggiornata',
                      dtUserUuid: r.dtId,
                    );

                    if (context.mounted) Navigator.pop(context);
                    _snack("Prenotazione aggiornata. Notifica inviata a: ${_notifTargetsLabel(r)}");
                    await _loadRows();
                  } catch (e) {
                    _snack("Errore aggiornamento: $e", error: true);
                  }
                },
                child: const Text("Salva"),
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
    final noteCtrl = TextEditingController();
    bool applyNote = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: Text('Modifica multipla (${_selectedIds.length})'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownSearch<String>(
                    items: kStatiTreno,
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
                    items: commessaOpt.map((e) => e['id']!).toList(),
                    selectedItem: _safeMapVal(commessaSel, commessaMap),
                    itemAsString: (id) => commessaMap[id] ?? id,
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
    if (statoSel == null && commessaSel == null && !applyNote) {
      _snack('Seleziona almeno un campo da modificare.', error: true);
      return;
    }

    try {
      setState(() => loading = true);
      final selected = _selectedRows;
      int updated = 0;
      for (final r in selected) {
        final payload = <String, dynamic>{};
        if (statoSel != null) payload['status'] = statoSel;
        if (commessaSel != null) payload['commessa_id'] = commessaSel;
        if (applyNote) payload['master_note'] = noteText;
        await SupabaseService.client.from(kTable).update(payload).eq('id', r.id);
        try {
          await NotificationSender.notifyTrenoAereoAdminChange(
            bookingType: 'treno',
            bookingId: int.parse(r.id),
            action: 'update',
            title: 'Prenotazione treno aggiornata',
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
      if (mounted) setState(() => loading = false);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == rows.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(rows.map((r) => r.id));
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
      setState(() => loading = true);
      int deleted = 0;
      for (final r in _selectedRows) {
        try {
          await NotificationSender.notifyTrenoAereoAdminChange(
            bookingType: 'treno',
            bookingId: int.parse(r.id),
            action: 'delete',
            title: 'Prenotazione treno eliminata',
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
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _buildMobileRows(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = rows[i];
        final persona = (personaleMap[r.personaleId] ?? r.personaleId).trim();
        final comm = (commessaMap[r.commessaId] ?? r.commessaId).trim();
        final reqId = r.requestedByUserId.trim();
        final isAssistant = reqId.isNotEmpty &&
            (utentiRoleByIdMap[reqId]?.toLowerCase().trim() == 'assistente_dt');
        final rich = isAssistant ? (utentiIdMap[reqId] ?? reqId) : (dtMap[r.dtId] ?? r.dtId);
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
                    _atCopyButton(personaleEmailMap[r.personaleId]),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Data: ${r.data}  |  Orario: ${r.orario}'),
                if (r.dataRitorno.trim().isNotEmpty || r.orarioRitorno.trim().isNotEmpty)
                  Text('Ritorno: ${r.dataRitorno} ${r.orarioRitorno}'.trim()),
                Text('Da ${r.partenza} a ${r.arrivo}'),
                if (ritornoDiverso) Text('Ritorno diverso: ${r.arrivoRitorno}'),
                Text('Commessa: ${comm.isEmpty ? r.commessaId : comm}'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      onSelected: (v) => _updateStato(r, v),
                      itemBuilder: (_) => kStatiTreno
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

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final safePersonale = _safeMapVal(personaleF, personaleMap);
    final safeCommessa = _safeMapVal(commessaF, commessaMap);
    final safeDt = _safeMapVal(dtF, dtMap);
    final safePartenza = _safeListVal(partenzaF, stazioni);
    final isMobileLayout = useCompactPageLayout(context);

    final compactTheme = Theme.of(context).copyWith(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Theme(
      data: compactTheme,
      child: Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(
          title: const ResponsiveAppBarTitle(title: 'Admin Treni'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: _selectedIds.length == rows.length && rows.isNotEmpty
                  ? 'Deseleziona tutto'
                  : 'Seleziona tutto',
              icon: Icon(
                _selectedIds.length == rows.length && rows.isNotEmpty
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              onPressed: rows.isEmpty ? null : _toggleSelectAll,
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
              tooltip: "Esporta Excel",
              icon: const Icon(Icons.file_download),
              onPressed: _exportExcel,
            ),
            IconButton(
              tooltip: "Ricarica",
              icon: const Icon(Icons.refresh),
              onPressed: _loadRows,
            ),
            const SizedBox(width: 8),
          ],
        )),
        body: PageWithTopLogo(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // ===== FILTRI =====
                    Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
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
                        // STATO
                        SizedBox(
                          width: 150,
                          child: DropdownSearch<String>(
                            items: kStatiTreno,
                            selectedItem: statoF,
                            onChanged: (v) async {
                              setState(() => statoF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => statoF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: "Stato",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        // PARTENZA
                        SizedBox(
                          width: 190,
                          child: DropdownSearch<String>(
                            items: stazioni, // <== lista completa, paginata
                            selectedItem: safePartenza,
                            onChanged: (v) async {
                              setState(() => partenzaF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => partenzaF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: "Partenza",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        // COMMESSA
                        SizedBox(
                          width: 200,
                          child: DropdownSearch<String>(
                            items: commessaOpt.map((o) => o['id']!).toList(),
                            selectedItem: safeCommessa,
                            itemAsString: (id) => commessaMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => commessaF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => commessaF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: "Commessa",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        // PERSONALE
                        SizedBox(
                          width: 200,
                          child: DropdownSearch<String>(
                            items: personaleOpt.map((o) => o['id']!).toList(),
                            selectedItem: safePersonale,
                            itemAsString: (id) => personaleMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => personaleF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => personaleF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: "Personale",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        // RICHIEDENTE
                        SizedBox(
                          width: 200,
                          child: DropdownSearch<String>(
                            items: dtOpt.map((o) => o['id']!).toList(),
                            selectedItem: safeDt,
                            itemAsString: (id) => dtMap[id] ?? id,
                            onChanged: (v) async {
                              setState(() => dtF = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => dtF = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: "Richiedente",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        TextButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text("Pulisci"),
                          onPressed: () async {
                            setState(() {
                              _showAllBookings = true;
                              statoF = partenzaF = commessaF = personaleF = dtF = null;
                            });
                            await _loadRows();
                          },
                        ),
                      ],
                    ),
                  ),

                  // ===== TABELLA / LISTA =====
                  Expanded(
                    child: isMobileLayout
                        ? _buildMobileRows(context)
                        : Scrollbar(
                            controller: _vCtrl,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _vCtrl,
                              scrollDirection: Axis.vertical,
                              child: Scrollbar(
                                controller: _hCtrl,
                                notificationPredicate: (n) =>
                                    n.metrics.axis == Axis.horizontal,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _hCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: DefaultTextStyle.merge(
                                    style: const TextStyle(fontSize: 12),
                                    child: DataTable(
                                columnSpacing: 8,
                                headingRowHeight: 34,
                                dataRowMinHeight: 34,
                                dataRowMaxHeight: 44,
                                columns: const [
                                  DataColumn(label: Text("Data")),
                                  DataColumn(label: Text("Orario andata")),
                                  DataColumn(label: Text("Data ritorno")),
                                  DataColumn(label: Text("Orario ritorno")),
                                  DataColumn(label: Text("Personale")),
                                  DataColumn(label: Text("Partenza")),
                                  DataColumn(label: Text("Arrivo")),
                                  DataColumn(label: Text("Ritorno diverso")),
                                  DataColumn(label: Text("Commessa")),
                                  DataColumn(label: Text("Stato")),
                                  DataColumn(label: Text("Note")),
                                  DataColumn(label: Text("Azioni")),
                                  DataColumn(label: Text("Richiedente")),
                                  DataColumn(label: Text("Inserita il")),
                                ],
                                rows: rows.map((r) {
                                  final persona =
                                      (personaleMap[r.personaleId] ?? r.personaleId).trim();
                                  final comm =
                                      (commessaMap[r.commessaId] ?? r.commessaId).trim();
                                  final reqId = r.requestedByUserId.trim();
                                  final isAssistant = reqId.isNotEmpty &&
                                      (utentiRoleByIdMap[reqId]
                                              ?.toLowerCase()
                                              .trim() ==
                                          'assistente_dt');
                                  final rich = isAssistant
                                      ? (utentiIdMap[reqId] ?? reqId)
                                      : (dtMap[r.dtId] ?? r.dtId);
                                  final color = _statusColor(r.stato);
                                  final ritornoDiverso =
                                      (r.arrivoRitorno.trim().isNotEmpty &&
                                          r.arrivoRitorno.trim() != r.partenza.trim());

                                  final insertedAtLabel = _insertedAtLabel(r.createdAt);
                                  return DataRow(cells: [
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
                                            constraints:
                                                const BoxConstraints(maxWidth: 150),
                                            child: Text(
                                              persona.isEmpty
                                                  ? r.personaleId
                                                  : persona,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _atCopyButton(
                                              personaleEmailMap[r.personaleId]),
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
                                    DataCell(Text(
                                      ritornoDiverso ? r.arrivoRitorno : '',
                                    )),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 140),
                                        child: Text(
                                          comm.isEmpty ? r.commessaId : comm,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      PopupMenuButton<String>(
                                        onSelected: (v) => _updateStato(r, v),
                                        itemBuilder: (_) => kStatiTreno
                                            .map((s) => PopupMenuItem(
                                                value: s, child: Text(s)))
                                            .toList(),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            r.stato,
                                            style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                                            tooltip: 'Modifica',
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 30,
                                              minHeight: 30,
                                            ),
                                            iconSize: 16,
                                            icon: const Icon(Icons.edit_outlined),
                                            onPressed: () => _edit(r),
                                          ),
                                          const SizedBox(width: 2),
                                          IconButton(
                                            tooltip: 'Elimina',
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 30,
                                              minHeight: 30,
                                            ),
                                            iconSize: 16,
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
                                            constraints:
                                                const BoxConstraints(maxWidth: 120),
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
                                  ].map((c) => _decorateCellWithInsertedAtTooltip(c, insertedAtLabel)).toList(), selected: _selectedIds.contains(r.id), onSelectChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(r.id);
                                      } else {
                                        _selectedIds.remove(r.id);
                                      }
                                    });
                                  });
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ),
      ),
    );
  }
}

// ===== MODEL =====
class _TrenoRow {
  final String id,
      createdAt,
      data,
      orario,
      dataRitorno,
      orarioRitorno,
      personaleId,
      partenza,
      arrivo,
      partenzaRitorno,
      arrivoRitorno,
      commessaId,
      stato,
      note,
      requestedByUserId,
      dtId;

  _TrenoRow({
    required this.id,
    required this.createdAt,
    required this.data,
    required this.orario,
    required this.dataRitorno,
    required this.orarioRitorno,
    required this.personaleId,
    required this.partenza,
    required this.arrivo,
    required this.partenzaRitorno,
    required this.arrivoRitorno,
    required this.commessaId,
    required this.stato,
    required this.note,
    required this.requestedByUserId,
    required this.dtId,
  });
}
