import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart'; // <-- AGGIUNTO

import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';
import '../services/notification_sender.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../utils/booking_inserted_by.dart';
import '../utils/date_formatters.dart';
import '../utils/mailto_launcher.dart';
import '../utils/roles.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Stati consentiti (unico punto di verità)
const List<String> kStatiAmmessi = <String>[
  'IN_ATTESA',
  'CONFERMATA',
  'ANNULLATA',
  'RIFIUTATA',
  'RICHIESTA_MODIFICA',
  'CONFERMA_MODIFICA',
];

/// Admin – Gestione Pernottamenti (autodetect colonne, stato editabile, doppio scroll, lookup robusto)
class AdminPernottiPage extends StatefulWidget {
  const AdminPernottiPage({super.key});
  @override
  State<AdminPernottiPage> createState() => _AdminPernottiPageState();
}

class _AdminPernottiPageState extends State<AdminPernottiPage> {
  static const String kTable = 'bookings';

  bool loading = false;
  bool _insertOrSaveInFlight = false;
  bool _showAllBookings = false;

  // === Nomi colonna (autodetect su bookings) ===
  String colPersonale = 'personale_id';   // verificati a runtime
  String colStruttura = 'structure_id';
  String colCommessa  = 'commessa_id';

  // Filtri (tutti su UUID; usano i nomi colonna risolti)
  String? statoFilter;      // IN_ATTESA | CONFERMATA | ANNULLATA | RIFIUTATA
  String? strutturaFilter;  // structures.id_uuid
  String? commessaFilter;   // commesse.id_uuid
  String? personaleFilter;  // personale.id_uuid
  String? dtFilter;         // users.id_uuid (Richiedente / dt_user_uuid)
  String _search = '';

  // Dizionari (UUID → etichetta)
  final Map<String, String> personaleNames = {}; // personale.id_uuid → full_name
  final Map<String, String> structureNames = {}; // structures.id_uuid → name
  final Map<String, String> structureEmails = {}; // structures.id_uuid → email
  final Map<String, String> commessaNames  = {}; // commesse.id_uuid → nome
  final Map<String, String> dtNamesByUuid  = {}; // users.id/id_uuid → full_name/username
  final Map<String, String> _authorByUuid = {};
  final Map<String, String> _authorById = {};

  // Opzioni filtri (UUID, deduplicate e ordinate)
  final List<Map<String, String>> strutturaOptions = [];
  final List<Map<String, String>> commessaOptions  = [];
  final List<Map<String, String>> personaleOptions = [];
  final List<Map<String, String>> dtOptions        = [];

  // Dati tabella
  List<_PernottoRow> rows = [];
  final Set<String> _selectedIds = <String>{};

  // Scroll controllers (orizzontale + verticale)
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();
  Timer? _alertBlinkTimer;
  bool _alertBlinkOn = true;

  @override
  void initState() {
    super.initState();
    statoFilter = 'IN_ATTESA';
    _alertBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _alertBlinkOn = !_alertBlinkOn);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _alertBlinkTimer?.cancel();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      await _resolveBookingsColumns(); // ← autodetect nomi colonna
      await _loadDizionari();
      await _loadRows();
    } catch (e) {
      _snack('Errore inizializzazione: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ===== Utils =====
  List<Map<String, String>> _toOptions(Map<String, String> m) {
    final uniq = <String, String>{};
    for (final e in m.entries) {
      if (e.key.isNotEmpty) uniq[e.key] = e.value;
    }
    final list = uniq.entries.map((e) => {'id': e.key, 'label': e.value}).toList();
    list.sort((a, b) => a['label']!.compareTo(b['label']!));
    return list;
  }

  String? _safeValue(String? v, Map<String, String> m) {
    if (v == null) return null;
    return m.containsKey(v) ? v : null;
  }

  bool _isAllowedRequester(Map<String, dynamic> userRow) {
    final primary = (userRow['role'] ?? '').toString();
    final secondary = (userRow['secondary_role'] ?? '').toString();
    if (isDtSelectableRole(primary, secondary)) return true;
    final role = primary.toLowerCase().trim().replaceAll(' ', '_');
    return role.startsWith('admin');
  }

  Future<String> _probeCol(String preferred, List<String> candidates) async {
    for (final c in <String>[preferred, ...candidates.where((x) => x != preferred)]) {
      try {
        await SupabaseService.client.from(kTable).select('id,$c').limit(1);
        return c; // se non lancia, la colonna esiste
      } catch (_) { /* prova il prossimo */ }
    }
    return preferred; // fallback
  }

  /// Rileva i nomi colonna reali su bookings (gestisce differenze come 'structure_id' vs 'struttura_id')
  Future<void> _resolveBookingsColumns() async {
    colStruttura = await _probeCol('structure_id', ['struttura_id', 'structure_uuid']);
    colPersonale = await _probeCol('personale_id', ['personale_uuid', 'id_personale']);
    colCommessa  = await _probeCol('commessa_id',  ['commessa_uuid',  'id_commessa']);
  }

  // ===== Dizionari (UUID) =====
  Future<void> _loadDizionari() async {
    // Personale
    final p = await SupabaseService.client
        .from('personale')
        .select('id_uuid, full_name, active')
        .eq('active', true)
        .order('full_name');

    personaleNames
      ..clear()
      ..addEntries(
        ((p as List)
              .map((e) => MapEntry(
                    (e['id_uuid'] ?? '').toString(),
                    (e['full_name'] ?? '').toString(),
                  ))
              .toList()
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );
    personaleOptions
      ..clear()
      ..addAll(_toOptions(personaleNames));

    // Strutture
    final s = await SupabaseService.client
        .from('structures')
        .select('id_uuid, name, email, active')
        .eq('active', true)
        .order('name');

    structureNames
      ..clear()
      ..addEntries(
        ((s as List)
              .map((e) => MapEntry(
                    (e['id_uuid'] ?? '').toString(),
                    (e['name'] ?? '').toString(),
                  ))
              .toList()
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );

    structureEmails
      ..clear()
      ..addEntries((s as List).map((e) => MapEntry(
            (e['id_uuid'] ?? '').toString(),
            (e['email'] ?? '').toString(),
          )));
    strutturaOptions
      ..clear()
      ..addAll(_toOptions(structureNames));

    // Commesse
    final c = await SupabaseService.client
        .from('commesse')
        .select('id_uuid, nome, active')
        .eq('active', true)
        .order('nome');

    commessaNames
      ..clear()
      ..addEntries(
        ((c as List)
              .map((e) => MapEntry(
                    (e['id_uuid'] ?? '').toString(),
                    (e['nome'] ?? '').toString(),
                  ))
              .toList()
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );
    commessaOptions
      ..clear()
      ..addAll(_toOptions(commessaNames));

    // Richiedenti (users) – risoluzione etichetta da id e id_uuid (se presenti)
    final u = await SupabaseService.client
        .from('users')
        .select('id, id_uuid, username, full_name, role, secondary_role')
        .order('username');

    dtNamesByUuid.clear();
    _authorByUuid.clear();
    _authorById.clear();
    for (final e in (u as List)) {
      final row = Map<String, dynamic>.from(e as Map);
      final id     = (row['id'] ?? '').toString();
      final idUuid = (row['id_uuid'] ?? '').toString();
      final fn     = (row['full_name'] ?? '').toString();
      final un     = (row['username']  ?? '').toString();
      final label  = fn.isNotEmpty ? fn : un;
      if (id.trim().isNotEmpty) _authorById[id.trim()] = label;
      if (idUuid.length >= 32) _authorByUuid[idUuid] = label;
      if (!_isAllowedRequester(row)) continue;
      if (id.length >= 32) dtNamesByUuid[id] = label;
      if (idUuid.length >= 32) dtNamesByUuid[idUuid] = label;
    }
    dtOptions
      ..clear()
      ..addAll(_toOptions(dtNamesByUuid));
  }

  dynamic _pernottiRowsQuery() {
    dynamic q = SupabaseService.client.from(kTable).select();

    if (statoFilter != null && statoFilter!.isNotEmpty) {
      q = q.eq('status', statoFilter);
    }
    if (strutturaFilter != null && strutturaFilter!.isNotEmpty) {
      q = q.eq(colStruttura, strutturaFilter); // usa colonna risolta
    }
    if (commessaFilter != null && commessaFilter!.isNotEmpty) {
      q = q.eq(colCommessa, commessaFilter);
    }
    if (personaleFilter != null && personaleFilter!.isNotEmpty) {
      q = q.eq(colPersonale, personaleFilter);
    }
    if (dtFilter != null && dtFilter!.isNotEmpty) {
      // bookings.dt_user_uuid – in DB è sempre questo
      q = q.eq('dt_user_uuid', dtFilter);
    }
    return q;
  }

  // ===== Dati =====
  Future<void> _loadRows() async {
    rows = [];
    _selectedIds.clear();

    const pageSize = 1000;
    int from = 0;
    final res = <dynamic>[];
    while (true) {
      final page = await _pernottiRowsQuery()
          .order('created_at', ascending: false)
          .range(from, from + pageSize - 1);
      final list = List<dynamic>.from(page as List);
      if (list.isEmpty) break;
      res.addAll(list);
      from += list.length;
    }

    for (final r in res) {
      rows.add(_PernottoRow(
        id:          (r['id']           ?? '').toString(),
        personaleId: (r[colPersonale]   ?? '').toString(),
        structureId: (r[colStruttura]   ?? '').toString(),
        commessaId:  (r[colCommessa]    ?? '').toString(),
        cameraTipo:  (r['camera_tipo']  ?? '').toString(),
        startDate:   _fmtDate(r['start_date']),
        endDate:     _fmtDate(r['end_date']),
        stato:       (r['status']       ?? '').toString().toUpperCase(),
        note:        (r['master_note']  ?? '').toString(),
        dtUserUuid:  (r['dt_user_uuid'] ?? '').toString(),
        createdBy:   (r['created_by'] ?? '').toString(),
        updatedBy:   (r['updated_by'] ?? '').toString(),
        createdAt:   (r['created_at']   ?? '').toString(),
        modificaPayload: (r['modifica_payload'] is Map)
            ? Map<String, dynamic>.from(r['modifica_payload'] as Map)
            : null,
        modificaNote: (r['modifica_note'] ?? '').toString(),
        modificaRequestedAt: (r['modifica_requested_at'] ?? '').toString(),
      ));
    }

    setState(() {});
  }

  Future<void> _toggleQuickLoadMode({required bool showAll}) async {
    setState(() {
      _showAllBookings = showAll;
      statoFilter = showAll ? null : 'IN_ATTESA';
      _selectedIds.clear();
    });
    await _loadRows();
  }

  List<_PernottoRow> get _selectedRows =>
      rows.where((r) => _selectedIds.contains(r.id)).toList();

  List<_PernottoRow> get _visibleRows {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((r) {
      final persona = (personaleNames[r.personaleId] ?? r.personaleId).trim();
      final struttura = (structureNames[r.structureId] ?? r.structureId).trim();
      final commessa = (commessaNames[r.commessaId] ?? r.commessaId).trim();
      final richied = bookingRequesterLabel(
        bookingAuthorFields(
          dtUserUuid: r.dtUserUuid,
          createdBy: r.createdBy,
          updatedBy: r.updatedBy,
        ),
        usersByUuid: _authorByUuid,
        usersById: _authorById,
      ).trim();
      final tokens = <String>[
        persona,
        struttura,
        commessa,
        r.cameraTipo,
        r.stato,
        r.note,
        r.startDate,
        r.endDate,
        _fmtDateTime(r.createdAt),
        richied,
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  // ===== Export to Excel =====
  Future<void> _exportToExcel() async {
    try {
      if (rows.isEmpty) {
        _snack('Nessun dato da esportare', error: true);
        return;
      }

      final excel = Excel.createExcel();
      final String sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final Sheet sheet = excel[sheetName];

      // Header
      final headers = ['Inserita il', 'Dal', 'Al', 'Personale', 'Struttura', 'Commessa', 'Camera', 'Stato', 'Note', 'Richiedente'];
      sheet.appendRow(headers);

      for (final r in rows) {
        final persona   = (personaleNames[r.personaleId] ?? r.personaleId).trim();
        final struttura = (structureNames[r.structureId] ?? r.structureId).trim();
        final commessa  = (commessaNames[r.commessaId]  ?? r.commessaId ).trim();
        final richied = bookingRequesterLabel(
          bookingAuthorFields(
            dtUserUuid: r.dtUserUuid,
            createdBy: r.createdBy,
            updatedBy: r.updatedBy,
          ),
          usersByUuid: _authorByUuid,
          usersById: _authorById,
        ).trim();

        final row = [
          _fmtDateTime(r.createdAt),
          r.startDate,
          r.endDate,
          (persona.isEmpty ? r.personaleId : persona),
          (struttura.isEmpty ? r.structureId : struttura),
          (commessa.isEmpty ? r.commessaId : commessa),
          r.cameraTipo,
          r.stato,
          r.note,
          (richied.isEmpty ? r.dtUserUuid : richied),
        ];
        sheet.appendRow(row);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        _snack('Errore generazione file Excel', error: true);
        return;
      }
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'pernottamenti',
        bytes: Uint8List.fromList(bytes),
      );
      if (!saved) {
        _snack('Export annullato', error: true);
        return;
      }
      _snack('Export Excel completato: ${ExcelExportHelper.lastSavedPath ?? ''}');
    } catch (e) {
      _snack('Errore esportazione: $e', error: true);
    }
  }

  Future<void> _createOutlookDraftForStructure() async {
    if (strutturaFilter == null || strutturaFilter!.trim().isEmpty) {
      _snack('Seleziona una struttura prima di creare la bozza.', error: true);
      return;
    }

    final structId = strutturaFilter!;
    final toEmail = (structureEmails[structId] ?? '').trim();
    if (toEmail.isEmpty) {
      _snack('Questa struttura non ha una email impostata.', error: true);
      return;
    }

    // Prendiamo SOLO IN_ATTESA, anche se l'utente ha altri filtri UI.
    final res = await SupabaseService.client.from(kTable).select().eq(colStruttura, structId).eq('status', 'IN_ATTESA');
    final data = res as List;
    if (data.isEmpty) {
      _snack('Nessun pernottamento IN_ATTESA per questa struttura.', error: true);
      return;
    }

    final structName = (structureNames[structId] ?? structId).trim();
    final subject = 'Richiesta disponibilità camere - $structName';

    final tableBlock = _buildPlainTextRoomsTable(data);

    final plainBody = '''
Buongiorno,

La presente per chiedere la disponibilità per le seguenti camere:

$tableBlock

Grazie per la vostra collaborazione

Rimango in attesa di un gentile riscontro.

Saluti
''';

    final result = await launchMailtoDraft(
      to: toEmail,
      subject: subject,
      body: plainBody,
    );
    switch (result) {
      case MailtoLaunchResult.opened:
        _snack('Bozza email aperta nel client predefinito.');
      case MailtoLaunchResult.openedSubjectOnlyBodyInClipboard:
        _snack(
          'Testo troppo lungo per mailto: corpo copiato negli appunti. '
          'Incollalo nel messaggio (Ctrl+V).',
        );
      case MailtoLaunchResult.failed:
        _snack(
          'Impossibile aprire il client email. Verifica che sia configurato nel browser.',
          error: true,
        );
    }
  }

  // ===== Azioni =====
  Future<void> _updateStato(_PernottoRow r, String nuovoStato) async {
    if (!await ensureCanPersist(context)) return;
    try {
      await SupabaseService.client
          .from(kTable)
          .update({'status': nuovoStato})
          .eq('id', r.id);
      final who = await _notifRecipientsLabel(r, 'update');
      if (!mounted) return;
      _snack('Stato aggiornato: $nuovoStato. Notifica inviata a: $who');
      // Notifica workflow: passa l'identificativo raw (uuid/int/auth_id),
      // la risoluzione robusta avviene in NotificationSender.
      if (r.dtUserUuid.isNotEmpty) {
        try {
          await NotificationSender.notifyUserForBooking(
            dtUserId: r.dtUserUuid,
            bookingId: r.id,
            action: 'update',
            title: 'Prenotazione aggiornata',
            bookingType: 'pernottamento',
          );
        } catch (_) {}
      }
      await _loadRows();
    } catch (e) {
      _snack('Errore aggiornamento stato: $e', error: true);
    }
  }

  // ===== Helpers =====
  /// Tabella in testo semplice (mailto non supporta HTML): colonne allineate.
  String _buildPlainTextRoomsTable(List<dynamic> rows) {
    const headers = ['Persona', 'Dal', 'Al', 'Camera'];
    final cells = <List<String>>[];
    for (final r in rows) {
      final map = r as Map;
      final personaleId = (map[colPersonale] ?? '').toString();
      final personaLabel = (personaleNames[personaleId] ?? personaleId).trim();
      final nome = personaLabel.isEmpty ? personaleId : personaLabel;
      cells.add([
        nome,
        _fmtDate(map['start_date']),
        _fmtDate(map['end_date']),
        (map['camera_tipo'] ?? '').toString(),
      ]);
    }
    final allRows = <List<String>>[headers, ...cells];
    final widths = List<int>.filled(4, 0);
    for (var c = 0; c < 4; c++) {
      for (final row in allRows) {
        final len = row[c].length;
        if (len > widths[c]) widths[c] = len;
      }
    }
    const maxCol = 36;
    for (var c = 0; c < 4; c++) {
      if (widths[c] > maxCol) widths[c] = maxCol;
    }
    String padCell(String s, int w) {
      if (s.length <= w) return s.padRight(w);
      if (w <= 1) return s.substring(0, w);
      return '${s.substring(0, w - 1)}…';
    }

    String line(List<String> row) =>
        List.generate(4, (i) => padCell(row[i], widths[i])).join(' | ');

    final sep = List.generate(4, (i) => '-' * widths[i]).join('-+-');
    final buf = StringBuffer();
    buf.writeln(line(headers));
    buf.writeln(sep);
    for (final row in cells) {
      buf.writeln(line(row));
    }
    return buf.toString().trimRight();
  }

  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  String _fmtDateTime(dynamic iso) => formatDateTimeItFromSupabase(iso);

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

  String _normalizeDateIso(String raw, {String fallback = ''}) {
    final v = raw.trim();
    if (v.isEmpty) return fallback;
    final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (iso.hasMatch(v)) return v;
    final dmy = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v);
    if (dmy != null) {
      return '${dmy.group(3)}-${dmy.group(2)}-${dmy.group(1)}';
    }
    return fallback;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  /// Account che ricevono davvero la push (regole + `personale.user_id`), non solo nomi in griglia.
  Future<String> _notifRecipientsLabel(_PernottoRow r, String action) async {
    if (r.dtUserUuid.isEmpty) return 'nessun destinatario (manca DT)';
    final bid = int.tryParse(r.id);
    if (bid == null || bid <= 0) return 'destinatari non determinabili';
    return NotificationSender.recipientLabelsForUserIds(
      await NotificationSender.recipientUserIdsForAdminBookingAction(
        dtUserId: r.dtUserUuid,
        bookingId: bid,
        action: action,
        bookingType: 'pernottamento',
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN_ATTESA':  return Colors.orange;
      case 'CONFERMATA': return Colors.green;
      case 'ANNULLATA':  return Colors.redAccent;
      case 'RIFIUTATA':  return Colors.red;
      case 'RICHIESTA_MODIFICA': return Colors.deepOrange;
      case 'CONFERMA_MODIFICA':  return Colors.blue;
      default:           return Colors.grey;
    }
  }

  Color? _rowHighlightColor(_PernottoRow r) {
    if (_isOverduePending(r)) {
      return _alertBlinkOn
          ? Colors.red.withValues(alpha: 0.45)
          : Colors.red.withValues(alpha: 0.16);
    }
    if (r.stato != 'IN_ATTESA') return null;
    final startIso = _normalizeDateIso(r.startDate);
    if (startIso.isEmpty) return null;
    final d = DateTime.tryParse(startIso);
    if (d == null) return null;
    final start = DateTime(d.year, d.month, d.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    if (start == today) return Colors.red.withValues(alpha: 0.18);
    if (start == tomorrow) return Colors.yellow.withValues(alpha: 0.22);
    return null;
  }

  bool _isOverduePending(_PernottoRow r) {
    if (r.stato != 'IN_ATTESA') return false;
    final startIso = _normalizeDateIso(r.startDate);
    if (startIso.isEmpty) return false;
    final d = DateTime.tryParse(startIso);
    if (d == null) return false;
    final start = DateTime(d.year, d.month, d.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return start.isBefore(today);
  }

  Future<void> _confirmModify(_PernottoRow r) async {
    if (!await ensureCanPersist(context)) return;
    final payload = r.modificaPayload;
    if (payload == null || payload.isEmpty) {
      _snack('Nessuna modifica proposta trovata.', error: true);
      return;
    }

    final personaNow = (personaleNames[r.personaleId] ?? r.personaleId).trim();
    final strutturaNow = (structureNames[r.structureId] ?? r.structureId).trim();
    final commessaNow = (commessaNames[r.commessaId] ?? r.commessaId).trim();

    String pOr(String key) => (payload[key] ?? '').toString();
    final personaleNew = pOr(colPersonale).isNotEmpty ? pOr(colPersonale) : pOr('personale_id');
    final strutturaNew = pOr(colStruttura).isNotEmpty ? pOr(colStruttura) : (pOr('struttura_id').isNotEmpty ? pOr('struttura_id') : pOr('structure_id'));
    final commessaNew = pOr(colCommessa).isNotEmpty ? pOr(colCommessa) : pOr('commessa_id');
    final cameraNew = pOr('camera_tipo');
    final dalNew = pOr('start_date');
    final alNew = pOr('end_date');
    final noteNew = pOr('master_note');
    final effectiveDalIso = _normalizeDateIso(dalNew, fallback: _normalizeDateIso(r.startDate));
    final effectiveAlIso = _normalizeDateIso(alNew, fallback: _normalizeDateIso(r.endDate));
    final effectiveDalLabel = effectiveDalIso.isEmpty ? '—' : _fmtDate(effectiveDalIso);
    final effectiveAlLabel = effectiveAlIso.isEmpty ? '—' : _fmtDate(effectiveAlIso);

    final personaNewLabel = (personaleNames[personaleNew] ?? personaleNew).trim();
    final strutturaNewLabel = (structureNames[strutturaNew] ?? strutturaNew).trim();
    final commessaNewLabel = (commessaNames[commessaNew] ?? commessaNew).trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conferma modifica'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Applico le modifiche proposte dal DT?'),
              const SizedBox(height: 12),
              Text('Persona: ${personaNow.isEmpty ? '—' : personaNow} → ${personaNewLabel.isEmpty ? '—' : personaNewLabel}'),
              Text('Struttura: ${strutturaNow.isEmpty ? '—' : strutturaNow} → ${strutturaNewLabel.isEmpty ? '—' : strutturaNewLabel}'),
              Text('Commessa: ${commessaNow.isEmpty ? '—' : commessaNow} → ${commessaNewLabel.isEmpty ? '—' : commessaNewLabel}'),
              Text('Dal: ${r.startDate} → $effectiveDalLabel'),
              Text('Al: ${r.endDate} → $effectiveAlLabel'),
              Text('Camera: ${r.cameraTipo} → ${cameraNew.isEmpty ? '—' : cameraNew}'),
              if (noteNew.isNotEmpty)
                NotePreviewText(
                  note: '${r.note} -> $noteNew',
                  prefix: 'Note: ',
                  maxChars: 10,
                ),
              if (r.modificaNote.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Nota richiesta: ${r.modificaNote}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Conferma')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // bookings.modifica_confirmed_by e' integer (users.id), non UUID.
      int? confirmedBy;
      try {
        final sess = SupabaseService.client.auth.currentSession;
        if (sess != null) {
          final u = await SupabaseService.client
              .from('users')
              .select('id')
              .eq('auth_id', sess.user.id)
              .maybeSingle();
          confirmedBy = (u?['id'] as int?);
        }
      } catch (_) {}
      if (confirmedBy == null) {
        _snack(
          'Conferma non eseguita: utente corrente non trovato in anagrafica users.',
          error: true,
        );
        return;
      }

      final update = <String, dynamic>{
        colPersonale: personaleNew.isNotEmpty ? personaleNew : r.personaleId,
        colStruttura: strutturaNew.isNotEmpty ? strutturaNew : r.structureId,
        colCommessa: commessaNew.isNotEmpty ? commessaNew : r.commessaId,
        'camera_tipo': cameraNew.isNotEmpty ? cameraNew : r.cameraTipo,
        'start_date': effectiveDalIso,
        'end_date': effectiveAlIso,
        'master_note': noteNew,
        'status': 'CONFERMA_MODIFICA',
        'modifica_confirmed_at': supabaseNowIsoUtc(),
        'modifica_confirmed_by': confirmedBy,
        // pulizia richiesta
        'modifica_payload': null,
        'modifica_note': null,
        'modifica_requested_at': null,
      };

      await SupabaseService.client.from(kTable).update(update).eq('id', r.id);
      final who = await _notifRecipientsLabel(r, 'update');
      if (!mounted) return;
      _snack('Modifica confermata. Notifica inviata a: $who');

      // Notifica al DT/richiedente usando id raw (uuid/int/auth_id).
      if (r.dtUserUuid.isNotEmpty) {
        try {
          await NotificationSender.notifyUserForBooking(
            dtUserId: r.dtUserUuid,
            bookingId: r.id,
            action: 'update',
            title: 'Pernottamento modificato',
            message: 'La tua richiesta di modifica è stata confermata.',
            bookingType: 'pernottamento',
          );
        } catch (_) {}
      }

      await _loadRows();
    } catch (e) {
      _snack('Errore conferma modifica: $e', error: true);
    }
  }

  Future<void> _bulkEditSelected() async {
    if (_selectedIds.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    String? statoSel;
    String? strutturaSel;
    String? commessaSel;
    final cameraCtrl = TextEditingController();
    bool applyCamera = false;
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
                    items: kStatiAmmessi,
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
                    items: strutturaOptions.map((e) => e['id']!).toList(),
                    selectedItem: _safeValue(strutturaSel, structureNames),
                    itemAsString: (id) => structureNames[id] ?? id,
                    onChanged: (v) => setSt(() => strutturaSel = v),
                    popupProps: const PopupProps.menu(showSearchBox: true),
                    clearButtonProps: const ClearButtonProps(isVisible: true),
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Nuova struttura (opzionale)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownSearch<String>(
                    items: commessaOptions.map((e) => e['id']!).toList(),
                    selectedItem: _safeValue(commessaSel, commessaNames),
                    itemAsString: (id) => commessaNames[id] ?? id,
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
                    value: applyCamera,
                    onChanged: (v) => setSt(() => applyCamera = v),
                    title: const Text('Sovrascrivi tipo camera'),
                  ),
                  if (applyCamera)
                    TextField(
                      controller: cameraCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nuovo tipo camera',
                        border: OutlineInputBorder(),
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
    final cameraText = cameraCtrl.text.trim();
    final noteText = noteCtrl.text.trim();
    cameraCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true) return;
    if (statoSel == null &&
        strutturaSel == null &&
        commessaSel == null &&
        !applyCamera &&
        !applyNote) {
      _snack('Seleziona almeno un campo da modificare.', error: true);
      return;
    }

    try {
      setState(() => loading = true);
      int updated = 0;
      for (final r in _selectedRows) {
        final payload = <String, dynamic>{};
        if (statoSel != null) payload['status'] = statoSel;
        if (strutturaSel != null) payload[colStruttura] = strutturaSel;
        if (commessaSel != null) payload[colCommessa] = commessaSel;
        if (applyCamera) payload['camera_tipo'] = cameraText;
        if (applyNote) payload['master_note'] = noteText;
        await SupabaseService.client.from(kTable).update(payload).eq('id', r.id);
        if (r.dtUserUuid.isNotEmpty) {
          try {
            await NotificationSender.notifyUserForBooking(
              dtUserId: r.dtUserUuid,
              bookingId: r.id,
              action: 'update',
              title: 'Prenotazione aggiornata',
              bookingType: 'pernottamento',
            );
          } catch (_) {}
        }
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
    final visible = _visibleRows;
    setState(() {
      if (visible.isNotEmpty && visible.every((r) => _selectedIds.contains(r.id))) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visible.map((r) => r.id));
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
          "Confermi l'eliminazione dei pernottamenti selezionati? L'azione è irreversibile.",
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
        if (r.dtUserUuid.isNotEmpty) {
          try {
            await NotificationSender.notifyUserForBooking(
              dtUserId: r.dtUserUuid,
              bookingId: r.id,
              action: 'delete',
              title: 'Prenotazione eliminata',
              bookingType: 'pernottamento',
            );
          } catch (_) {}
        }
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

  @override
  Widget build(BuildContext context) {
    // Valori "safe" per evitare assert del Dropdown se il valore non è negli items
    final safeStrutturaFilter = _safeValue(strutturaFilter, structureNames);
    final safeCommessaFilter  = _safeValue(commessaFilter,  commessaNames);
    final safePersonaleFilter = _safeValue(personaleFilter, personaleNames);
    final safeDtFilter        = _safeValue(dtFilter,        dtNamesByUuid);
    final visibleRows = _visibleRows;

    // Tema compatto per "rimpicciolire" la pagina
    final compactTheme = Theme.of(context).copyWith(
      visualDensity: VisualDensity.compact, // meno padding globale
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Theme(
      data: compactTheme,
      child: Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(
          title: const ResponsiveAppBarTitle(title: 'Admin Pernottamenti'),
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
          actions: [
            IconButton(
              tooltip: visibleRows.isNotEmpty &&
                      visibleRows.every((r) => _selectedIds.contains(r.id))
                  ? 'Deseleziona tutto'
                  : 'Seleziona tutto',
              icon: Icon(
                visibleRows.isNotEmpty &&
                        visibleRows.every((r) => _selectedIds.contains(r.id))
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              onPressed: visibleRows.isEmpty ? null : _toggleSelectAll,
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
              icon: const Icon(Icons.refresh),
              tooltip: 'Ricarica',
              onPressed: () async {
                setState(() => loading = true);
                try {
                  await _loadRows();
                } finally {
                  if (mounted) setState(() => loading = false);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Esporta Excel',
              onPressed: () async {
                await _exportToExcel();
              },
            ),
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'Crea bozza Outlook (IN_ATTESA)',
              onPressed: () async {
                await _createOutlookDraftForStructure();
              },
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
                          width: 260,
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            decoration: InputDecoration(
                              labelText: 'Cerca',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: _search.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Azzera ricerca',
                                      onPressed: () => setState(() => _search = ''),
                                      icon: const Icon(Icons.clear),
                                    ),
                            ),
                          ),
                        ),
                        // STATO
                        SizedBox(
                          width: 200,
                          child: DropdownSearch<String>(
                            items: kStatiAmmessi,
                            selectedItem: statoFilter,
                            onChanged: (v) async {
                              setState(() => statoFilter = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => statoFilter = null);
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

                        // STRUTTURA (UUID)
                        SizedBox(
                          width: 220,
                          child: DropdownSearch<String>(
                            items: strutturaOptions.map((e) => e['id']!).toList(),
                            selectedItem: safeStrutturaFilter,
                            itemAsString: (id) => structureNames[id] ?? id,
                            onChanged: (v) async {
                              setState(() => strutturaFilter = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => strutturaFilter = null);
                                await _loadRows();
                              },
                            ),
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: const InputDecoration(
                                labelText: 'Struttura',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),

                        // COMMESSA
                        SizedBox(
                          width: 220,
                          child: DropdownSearch<String>(
                            items: commessaOptions.map((e) => e['id']!).toList(),
                            selectedItem: safeCommessaFilter,
                            itemAsString: (id) => commessaNames[id] ?? id,
                            onChanged: (v) async {
                              setState(() => commessaFilter = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => commessaFilter = null);
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

                        // PERSONALE
                        SizedBox(
                          width: 220,
                          child: DropdownSearch<String>(
                            items: personaleOptions.map((e) => e['id']!).toList(),
                            selectedItem: safePersonaleFilter,
                            itemAsString: (id) => personaleNames[id] ?? id,
                            onChanged: (v) async {
                              setState(() => personaleFilter = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => personaleFilter = null);
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

                        // RICHIEDENTE (DT)
                        SizedBox(
                          width: 220,
                          child: DropdownSearch<String>(
                            items: dtOptions.map((e) => e['id']!).toList(),
                            selectedItem: safeDtFilter,
                            itemAsString: (id) => dtNamesByUuid[id] ?? id,
                            onChanged: (v) async {
                              setState(() => dtFilter = v);
                              await _loadRows();
                            },
                            popupProps: const PopupProps.menu(showSearchBox: true),
                            clearButtonProps: ClearButtonProps(
                              isVisible: true,
                              onPressed: () async {
                                setState(() => dtFilter = null);
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
                      ],
                    ),
                  ),

                  // ===== TABELLA (scroll orizzontale + verticale) =====
                  Expanded(
                    child: Scrollbar(
                      controller: _vCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vCtrl,
                        scrollDirection: Axis.vertical,
                        child: Scrollbar(
                          controller: _hCtrl,
                          thumbVisibility: true,
                          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: _hCtrl,
                            scrollDirection: Axis.horizontal,
                            child: DefaultTextStyle.merge(
                              // font leggermente ridotto per “rimpicciolire” la tabella
                              style: const TextStyle(fontSize: 13),
                              child: DataTable(
                                columnSpacing: 22,     // meno spazio tra colonne
                                headingRowHeight: 38,  // header più basso
                                dataRowMinHeight: 50,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Dal')),
                                  DataColumn(label: Text('Al')),
                                  DataColumn(label: Text('Personale')),
                                  DataColumn(label: Text('Struttura')),
                                  DataColumn(label: Text('Commessa')),
                                  DataColumn(label: Text('Camera')),
                                  DataColumn(label: Text('Stato')),
                                  DataColumn(label: Text('Note')),
                                  DataColumn(label: Text('Richiedente')),
                                  DataColumn(label: Text('Azioni')),
                                  DataColumn(label: Text('Inserita il')),
                                ],
                                rows: visibleRows.map((r) {
                                  final richied = bookingRequesterLabel(
                                    bookingAuthorFields(
                                      dtUserUuid: r.dtUserUuid,
                                      createdBy: r.createdBy,
                                      updatedBy: r.updatedBy,
                                    ),
                                    usersByUuid: _authorByUuid,
                                    usersById: _authorById,
                                  ).trim();
                                  final reqStartRaw = (r.modificaPayload?['start_date'] ?? '').toString();
                                  final reqEndRaw = (r.modificaPayload?['end_date'] ?? '').toString();
                                  final isStartProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      reqStartRaw.trim().isNotEmpty &&
                                      _fmtDate(reqStartRaw) != r.startDate.trim();
                                  final isEndProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      reqEndRaw.trim().isNotEmpty &&
                                      _fmtDate(reqEndRaw) != r.endDate.trim();
                                  final startDateDisplay = (r.stato == 'RICHIESTA_MODIFICA' &&
                                          reqStartRaw.trim().isNotEmpty)
                                      ? _fmtDate(reqStartRaw)
                                      : r.startDate;
                                  final endDateDisplay = (r.stato == 'RICHIESTA_MODIFICA' &&
                                          reqEndRaw.trim().isNotEmpty)
                                      ? _fmtDate(reqEndRaw)
                                      : r.endDate;

                                  String pOr(String key) =>
                                      (r.modificaPayload?[key] ?? '').toString().trim();
                                  final personaleProposedId = pOr(colPersonale).isNotEmpty
                                      ? pOr(colPersonale)
                                      : (pOr('personale_id').isNotEmpty
                                          ? pOr('personale_id')
                                          : pOr('personale_uuid'));
                                  final strutturaProposedId = pOr(colStruttura).isNotEmpty
                                      ? pOr(colStruttura)
                                      : (pOr('struttura_id').isNotEmpty
                                          ? pOr('struttura_id')
                                          : pOr('structure_id'));
                                  final commessaProposedId = pOr(colCommessa).isNotEmpty
                                      ? pOr(colCommessa)
                                      : pOr('commessa_id');
                                  final cameraProposed = pOr('camera_tipo');

                                  final isPersonaProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      personaleProposedId.isNotEmpty &&
                                      personaleProposedId != r.personaleId;
                                  final isStrutturaProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      strutturaProposedId.isNotEmpty &&
                                      strutturaProposedId != r.structureId;
                                  final isCommessaProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      commessaProposedId.isNotEmpty &&
                                      commessaProposedId != r.commessaId;
                                  final isCameraProposed = r.stato == 'RICHIESTA_MODIFICA' &&
                                      cameraProposed.isNotEmpty &&
                                      cameraProposed != r.cameraTipo;

                                  final personaDisplayId = isPersonaProposed ||
                                          (r.stato == 'RICHIESTA_MODIFICA' &&
                                              personaleProposedId.isNotEmpty)
                                      ? personaleProposedId
                                      : r.personaleId;
                                  final strutturaDisplayId = isStrutturaProposed ||
                                          (r.stato == 'RICHIESTA_MODIFICA' &&
                                              strutturaProposedId.isNotEmpty)
                                      ? strutturaProposedId
                                      : r.structureId;
                                  final commessaDisplayId = isCommessaProposed ||
                                          (r.stato == 'RICHIESTA_MODIFICA' &&
                                              commessaProposedId.isNotEmpty)
                                      ? commessaProposedId
                                      : r.commessaId;
                                  final cameraDisplay = isCameraProposed ||
                                          (r.stato == 'RICHIESTA_MODIFICA' &&
                                              cameraProposed.isNotEmpty)
                                      ? cameraProposed
                                      : r.cameraTipo;

                                  final personaDisp = (personaleNames[personaDisplayId] ??
                                          personaDisplayId)
                                      .trim();
                                  final strutturaDisp = (structureNames[strutturaDisplayId] ??
                                          strutturaDisplayId)
                                      .trim();
                                  final commessaDisp = (commessaNames[commessaDisplayId] ??
                                          commessaDisplayId)
                                      .trim();

                                  Widget propostaBadge() => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'proposta',
                                          style: TextStyle(
                                            color: Colors.deepOrange,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                  Widget withProposta(String text, bool proposed) => Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(child: Text(text)),
                                          if (proposed) ...[
                                            const SizedBox(width: 6),
                                            propostaBadge(),
                                          ],
                                        ],
                                      );

                                  final color = _statusColor(r.stato);
                                  final overduePending = _isOverduePending(r);

                                  final rowHighlight = _rowHighlightColor(r);
                                  final insertedAtLabel = _fmtDateTime(r.createdAt);
                                  return DataRow(
                                    color: rowHighlight == null
                                        ? null
                                        : WidgetStatePropertyAll<Color?>(rowHighlight),
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
                                              'Inserita il: ${_fmtDateTime(r.createdAt)}',
                                          waitDuration:
                                              const Duration(milliseconds: 220),
                                          child: withProposta(
                                              startDateDisplay, isStartProposed),
                                        ),
                                      ),
                                      DataCell(withProposta(
                                          endDateDisplay, isEndProposed)),
                                      DataCell(withProposta(
                                          personaDisp.isEmpty
                                              ? r.personaleId
                                              : personaDisp,
                                          isPersonaProposed)),
                                      DataCell(withProposta(
                                          strutturaDisp.isEmpty
                                              ? r.structureId
                                              : strutturaDisp,
                                          isStrutturaProposed)),
                                      DataCell(withProposta(
                                          commessaDisp.isEmpty
                                              ? r.commessaId
                                              : commessaDisp,
                                          isCommessaProposed)),
                                      DataCell(withProposta(
                                          cameraDisplay, isCameraProposed)),

                                      // Stato con badge + popup per modifica
                                      DataCell(
                                        PopupMenuButton<String>(
                                          tooltip: 'Modifica stato',
                                          onSelected: (v) => _updateStato(r, v),
                                          itemBuilder: (_) => kStatiAmmessi
                                              .map((s) => PopupMenuItem(value: s, child: Text(s)))
                                              .toList(),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: overduePending
                                                  ? (_alertBlinkOn
                                                      ? Colors.red
                                                      : Colors.red.withValues(alpha: 0.45))
                                                  : color.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              overduePending ? 'IN_ATTESA !' : r.stato,
                                              style: TextStyle(
                                                color: overduePending ? Colors.white : color,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      DataCell(
                                        SizedBox(
                                          width: 120,
                                          child: NotePreviewText(
                                            note: r.note,
                                            maxChars: 10,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(richied.isEmpty ? r.dtUserUuid : richied)),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (r.stato == 'RICHIESTA_MODIFICA')
                                              IconButton(
                                                tooltip: 'Conferma richiesta modifica',
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _confirmModify(r),
                                                icon: Icon(
                                                  Icons.playlist_add_check_circle_outlined,
                                                  size: 18,
                                                  color: Colors.orange.shade800,
                                                ),
                                              ),
                                            IconButton(
                                              tooltip: 'Modifica',
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _createOrEdit(row: r),
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: Colors.blueGrey.shade800,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Elimina',
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _delete(r.id),
                                              icon: Icon(
                                                Icons.delete_forever,
                                                size: 18,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(Text(_fmtDateTime(r.createdAt))),
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
              ),
          ),
      ),
    );
  }

  /// Crea o modifica (UUID coerenti) – con mappe per i dropdown
  Future<void> _createOrEdit({_PernottoRow? row}) async {
    if (_insertOrSaveInFlight) return;
    if (!await ensureCanPersist(context)) return;
    final personaleMap = { for (final o in personaleOptions) o['id']!: o['label']! };
    final strutturaMap = { for (final o in strutturaOptions) o['id']!: o['label']! };
    final commessaMap  = { for (final o in commessaOptions)  o['id']!: o['label']! };

    final result = await showDialog<_PernottoRow>(
      context: context,
      builder: (_) => _PernottoDialog(
        personaleNames: personaleMap,
        structureNames: strutturaMap,
        commessaNames:  commessaMap,
        row: row,
      ),
    );
    if (result == null) return;

    _insertOrSaveInFlight = true;
    setState(() => loading = true);
    try {
      // UUID utente corrente per auditing ("Chi ha creato/modificato")
      String? updatedBy;
      final session = SupabaseService.client.auth.currentSession;
      if (session != null) {
        final u = await SupabaseService.client
            .from('users')
            .select('id_uuid')
            .eq('auth_id', session.user.id)
            .maybeSingle();
        updatedBy = (u?['id_uuid'] as String?)?.trim();
        updatedBy ??= session.user.id; // fallback UUID auth
      }

      final startIso = _normalizeDateIso(
        result.startDate,
        fallback: row == null ? '' : _normalizeDateIso(row.startDate),
      );
      final endIso = _normalizeDateIso(
        result.endDate,
        fallback: row == null ? '' : _normalizeDateIso(row.endDate),
      );

      final payload = {
        colPersonale: result.personaleId, // UUID
        colStruttura: result.structureId, // UUID (nome colonna risolto)
        colCommessa : result.commessaId,  // UUID
        'camera_tipo':  result.cameraTipo,
        'start_date':   startIso,
        'end_date':     endIso,
        'status':       result.stato,
        'master_note':  result.note,
        'updated_by': ?updatedBy,
        // Richiedente iniziale: solo in creazione, mai sovrascritto in modifica.
        if (row == null && updatedBy != null) 'created_by': updatedBy,
      };

      if (row == null) {
        await SupabaseService.client.from(kTable).insert(payload);
        _snack('Pernotto creato');
      } else {
        await SupabaseService.client.from(kTable).update(payload).eq('id', row.id);
        final who = await _notifRecipientsLabel(row, 'update');
        if (!mounted) return;
        _snack('Pernotto aggiornato. Notifica inviata a: $who');
        // Push workflow al DT/richiedente della prenotazione.
        if (row.dtUserUuid.isNotEmpty) {
          try {
            await NotificationSender.notifyUserForBooking(
              dtUserId: row.dtUserUuid,
              bookingId: row.id,
              action: 'update',
              title: 'Prenotazione aggiornata',
              bookingType: 'pernottamento',
            );
          } catch (e) {
            debugPrint('>>> INVIO PUSH ERRORE: $e');
          }
        } else {
          debugPrint('>>> INVIO PUSH: dtUserUuid vuoto, skip');
        }
      }
      await _loadRows();
    } catch (e) {
      _snack('Errore salvataggio: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
      _insertOrSaveInFlight = false;
    }
  }

  Future<void> _delete(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina pernottamento'),
        content: const Text('Confermi l\'eliminazione? L\'azione è irreversibile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => loading = true);
    try {
      _PernottoRow? rowBefore;
      for (final r in rows) {
        if (r.id == id) {
          rowBefore = r;
          break;
        }
      }
      String who = 'destinatari workflow';
      if (rowBefore != null) {
        who = await _notifRecipientsLabel(rowBefore, 'delete');
      }
      if (!mounted) return;

      String? dtUserUuid;
      try {
        final b = await SupabaseService.client.from(kTable).select('dt_user_uuid').eq('id', id).maybeSingle();
        dtUserUuid = (b?['dt_user_uuid'] as String?)?.trim();
      } catch (_) {}

      if (dtUserUuid != null && dtUserUuid.isNotEmpty) {
        try {
          final bid = int.tryParse(id);
          if (bid != null && bid > 0) {
            await NotificationSender.notifyUserForBooking(
              dtUserId: dtUserUuid,
              bookingId: bid,
              action: 'delete',
              title: 'Prenotazione eliminata',
              bookingType: 'pernottamento',
            );
          }
        } catch (_) {}
      }

      // Notifica PRIMA della cancellazione: l'Edge Function legge la prenotazione
      // dal DB per costruire testo (Per/Tipo/Data). Se cancelliamo prima otteniamo N/D.
      await SupabaseService.client.from(kTable).delete().eq('id', id);
      if (!mounted) return;
      _snack('Pernotto eliminato. Notifica inviata a: $who');

      await _loadRows();
    } catch (e) {
      _snack('Errore eliminazione: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

// ---- MODEL
class _PernottoRow {
  final String id;
  final String personaleId; // UUID (bookings.[colPersonale])
  final String structureId; // UUID (bookings.[colStruttura])
  final String commessaId;  // UUID (bookings.[colCommessa])
  final String cameraTipo;
  final String startDate; // ISO yyyy-MM-dd
  final String endDate;   // ISO yyyy-MM-dd
  final String stato;     // IN_ATTESA | CONFERMATA | ANNULLATA | RIFIUTATA
  final String note;
  final String dtUserUuid;
  final String createdBy;
  final String updatedBy;
  final String createdAt;
  final Map<String, dynamic>? modificaPayload;
  final String modificaNote;
  final String modificaRequestedAt;

  _PernottoRow({
    required this.id,
    required this.personaleId,
    required this.structureId,
    required this.commessaId,
    required this.cameraTipo,
    required this.startDate,
    required this.endDate,
    required this.stato,
    required this.note,
    required this.dtUserUuid,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.modificaPayload,
    required this.modificaNote,
    required this.modificaRequestedAt,
  });
}

// ---- DIALOG CREA/EDITA (usa id_uuid; sanifica valori iniziali per evitare assert)
class _PernottoDialog extends StatefulWidget {
  final Map<String, String> personaleNames; // id_uuid -> label
  final Map<String, String> structureNames; // id_uuid -> label
  final Map<String, String> commessaNames;  // id_uuid -> label
  final _PernottoRow? row;

  const _PernottoDialog({
    required this.personaleNames,
    required this.structureNames,
    required this.commessaNames,
    this.row,
  });

  @override
  State<_PernottoDialog> createState() => _PernottoDialogState();
}

class _PernottoDialogState extends State<_PernottoDialog> {
  final _formKey = GlobalKey<FormState>();

  String? personaleId; // UUID
  String? structureId; // UUID
  String? commessaId;  // UUID
  final cameraCtrl = TextEditingController();
  DateTime? dal;
  DateTime? al;
  String? stato;
  final noteCtrl = TextEditingController();

  String? _safe(String? v, Map<String, String> m) => (v != null && m.containsKey(v)) ? v : null;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r != null) {
      // SANIFICA: se gli UUID salvati non esistono più nelle opzioni, azzera per evitare assert
      personaleId   = _safe(r.personaleId, widget.personaleNames);
      structureId   = _safe(r.structureId, widget.structureNames);
      commessaId    = _safe(r.commessaId,  widget.commessaNames);
      cameraCtrl.text = r.cameraTipo;
      dal           = parseFlexibleDateToDateTime(r.startDate);
      al            = parseFlexibleDateToDateTime(r.endDate);
      stato         = r.stato;
      noteCtrl.text = r.note;
    }
  }

  @override
  void dispose() {
    cameraCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (dal ?? now) : (al ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          dal = picked;
          if (al != null && picked.isAfter(al!)) al = picked;
        } else {
          al = picked;
          if (dal != null && picked.isBefore(dal!)) dal = picked;
        }
      });
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo pernottamento' : 'Modifica pernottamento'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Personale
                DropdownSearch<String>(
                  items: widget.personaleNames.keys.toList(),
                  selectedItem: personaleId,
                  itemAsString: (id) => widget.personaleNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona il personale' : null,
                  onChanged: (v) => setState(() => personaleId = v),
                  popupProps: const PopupProps.menu(showSearchBox: true),
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

                // Struttura
                DropdownSearch<String>(
                  items: widget.structureNames.keys.toList(),
                  selectedItem: structureId,
                  itemAsString: (id) => widget.structureNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona la struttura' : null,
                  onChanged: (v) => setState(() => structureId = v),
                  popupProps: const PopupProps.menu(showSearchBox: true),
                  clearButtonProps: const ClearButtonProps(isVisible: true),
                  dropdownDecoratorProps: DropDownDecoratorProps(
                    dropdownSearchDecoration: const InputDecoration(
                      labelText: 'Struttura',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Commessa
                DropdownSearch<String>(
                  items: widget.commessaNames.keys.toList(),
                  selectedItem: commessaId,
                  itemAsString: (id) => widget.commessaNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona la commessa' : null,
                  onChanged: (v) => setState(() => commessaId = v),
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

                // Tipo camera
                TextFormField(
                  controller: cameraCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo camera',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),

                // Date
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Dal',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(dal == null ? '—' : _displayDate(dal!)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickDate(isStart: false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Al',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(al == null ? '—' : _displayDate(al!)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Stato
                DropdownSearch<String>(
                  items: kStatiAmmessi,
                  selectedItem: kStatiAmmessi.contains(stato) ? stato : null,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona lo stato' : null,
                  onChanged: (v) => setState(() => stato = v),
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
                TextFormField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (dal == null || al == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Seleziona le date Dal/Al')),
              );
              return;
            }
            Navigator.pop(
              context,
              _PernottoRow(
                id: '',
                personaleId: personaleId!,
                structureId: structureId!,
                commessaId:  commessaId!,
                cameraTipo:  cameraCtrl.text,
                startDate:   _iso(dal!),
                endDate:     _iso(al!),
                stato:       stato!,
                note:        noteCtrl.text,
                dtUserUuid:  '', // impostato lato DT in inserimento
                createdBy: '',
                updatedBy: '',
                createdAt: '',
                modificaPayload: null,
                modificaNote: '',
                modificaRequestedAt: '',
              ),
            );
          },
          child: Text(widget.row == null ? 'Crea' : 'Salva'),
        ),
      ],
   );
 }
}