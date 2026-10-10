import 'dart:io';
import 'dart:async';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../utils/booking_inserted_by.dart';
import '../utils/date_formatters.dart';
import '../utils/mailto_launcher.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

const List<String> kStatiAmmessiMobile = <String>[
  'IN_ATTESA',
  'CONFERMATA',
  'ANNULLATA',
  'RIFIUTATA',
  'RICHIESTA_MODIFICA',
  'CONFERMA_MODIFICA',
];

class AdminPernottiMobilePage extends StatefulWidget {
  const AdminPernottiMobilePage({super.key});

  @override
  State<AdminPernottiMobilePage> createState() => _AdminPernottiMobilePageState();
}

class _AdminPernottiMobilePageState extends State<AdminPernottiMobilePage> {
  static const String kTable = 'bookings';

  bool loading = false;
  bool _insertOrSaveInFlight = false;

  String colPersonale = 'personale_id';
  String colStruttura = 'structure_id';
  String colCommessa = 'commessa_id';

  String? statoFilter;
  String? strutturaFilter;
  String? commessaFilter;
  String? personaleFilter;
  String? dtFilter;

  final Map<String, String> personaleNames = {};
  final Map<String, String> structureNames = {};
  final Map<String, String> structureEmails = {};
  final Map<String, String> commessaNames = {};
  final Map<String, String> dtNamesByUuid = {};
  final Map<String, String> _authorByUuid = {};
  final Map<String, String> _authorById = {};

  final List<Map<String, String>> strutturaOptions = [];
  final List<Map<String, String>> commessaOptions = [];
  final List<Map<String, String>> personaleOptions = [];
  final List<Map<String, String>> dtOptions = [];

  List<_PernottoRowMobile> rows = [];
  Timer? _alertBlinkTimer;
  bool _alertBlinkOn = true;

  @override
  void initState() {
    super.initState();
    _alertBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _alertBlinkOn = !_alertBlinkOn);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _alertBlinkTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      await _resolveBookingsColumns();
      await _loadDizionari();
      await _loadRows();
    } catch (e) {
      _snack('Errore inizializzazione: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, String>> _toOptions(Map<String, String> m) {
    final uniq = <String, String>{};
    for (final e in m.entries) {
      if (e.key.isNotEmpty) uniq[e.key] = e.value;
    }
    final list = uniq.entries.map((e) => {'id': e.key, 'label': e.value}).toList();
    list.sort((a, b) => a['label']!.toLowerCase().compareTo(b['label']!.toLowerCase()));
    return list;
  }

  String? _safeValue(String? v, Map<String, String> m) {
    if (v == null) return null;
    return m.containsKey(v) ? v : null;
  }

  Future<String> _probeCol(String preferred, List<String> candidates) async {
    for (final c in <String>[preferred, ...candidates.where((x) => x != preferred)]) {
      try {
        await SupabaseService.client.from(kTable).select('id,$c').limit(1);
        return c;
      } catch (_) {}
    }
    return preferred;
  }

  Future<void> _resolveBookingsColumns() async {
    colStruttura = await _probeCol('structure_id', ['struttura_id', 'structure_uuid']);
    colPersonale = await _probeCol('personale_id', ['personale_uuid', 'id_personale']);
    colCommessa = await _probeCol('commessa_id', ['commessa_uuid', 'id_commessa']);
  }

  Future<void> _loadDizionari() async {
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

    final u = await SupabaseService.client
        .from('users')
        .select('id, id_uuid, username, full_name')
        .order('username');
    dtNamesByUuid.clear();
    _authorByUuid.clear();
    _authorById.clear();
    for (final e in (u as List)) {
      final id = (e['id'] ?? '').toString();
      final idUuid = (e['id_uuid'] ?? '').toString();
      final fn = (e['full_name'] ?? '').toString();
      final un = (e['username'] ?? '').toString();
      final label = fn.isNotEmpty ? fn : un;
      if (id.trim().isNotEmpty) {
        _authorById[id.trim()] = label;
        if (id.length >= 32) dtNamesByUuid[id] = label;
      }
      if (idUuid.length >= 32) {
        _authorByUuid[idUuid] = label;
        dtNamesByUuid[idUuid] = label;
      }
    }
    dtOptions
      ..clear()
      ..addAll(_toOptions(dtNamesByUuid));
  }

  dynamic _pernottiRowsQuery() {
    dynamic q = SupabaseService.client.from(kTable).select();

    if (statoFilter != null && statoFilter!.isNotEmpty) q = q.eq('status', statoFilter);
    if (strutturaFilter != null && strutturaFilter!.isNotEmpty) q = q.eq(colStruttura, strutturaFilter);
    if (commessaFilter != null && commessaFilter!.isNotEmpty) q = q.eq(colCommessa, commessaFilter);
    if (personaleFilter != null && personaleFilter!.isNotEmpty) q = q.eq(colPersonale, personaleFilter);
    if (dtFilter != null && dtFilter!.isNotEmpty) q = q.eq('dt_user_uuid', dtFilter);
    return q;
  }

  Future<void> _loadRows() async {
    rows = [];

    const pageSize = 1000;
    int from = 0;
    final res = <dynamic>[];
    while (true) {
      final page = await _pernottiRowsQuery()
          .order('start_date', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .range(from, from + pageSize - 1);
      final list = List<dynamic>.from(page as List);
      if (list.isEmpty) break;
      res.addAll(list);
      from += list.length;
    }

    for (final r in res) {
      rows.add(_PernottoRowMobile(
        id: (r['id'] ?? '').toString(),
        personaleId: (r[colPersonale] ?? '').toString(),
        structureId: (r[colStruttura] ?? '').toString(),
        commessaId: (r[colCommessa] ?? '').toString(),
        cameraTipo: (r['camera_tipo'] ?? '').toString(),
        startDate: _fmtDate(r['start_date']),
        endDate: _fmtDate(r['end_date']),
        stato: (r['status'] ?? '').toString().toUpperCase(),
        note: (r['master_note'] ?? '').toString(),
        dtUserUuid: (r['dt_user_uuid'] ?? '').toString(),
        createdBy: (r['created_by'] ?? '').toString(),
        updatedBy: (r['updated_by'] ?? '').toString(),
        modificaPayload: (r['modifica_payload'] is Map)
            ? Map<String, dynamic>.from(r['modifica_payload'] as Map)
            : null,
        modificaNote: (r['modifica_note'] ?? '').toString(),
        modificaRequestedAt: (r['modifica_requested_at'] ?? '').toString(),
      ));
    }

    if (mounted) setState(() {});
  }

  Future<void> _exportToExcel() async {
    try {
      if (rows.isEmpty) {
        _snack('Nessun dato da esportare', error: true);
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      sheet.appendRow(const [
        'Dal',
        'Al',
        'Personale',
        'Struttura',
        'Commessa',
        'Camera',
        'Stato',
        'Note',
        'Richiedente'
      ]);
      for (final r in rows) {
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
        sheet.appendRow([
          r.startDate,
          r.endDate,
          persona.isEmpty ? r.personaleId : persona,
          struttura.isEmpty ? r.structureId : struttura,
          commessa.isEmpty ? r.commessaId : commessa,
          r.cameraTipo,
          r.stato,
          r.note,
          richied.isEmpty ? r.dtUserUuid : richied,
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        _snack('Errore generazione file Excel', error: true);
        return;
      }
      final date = italyTodayIsoDate();
      final suggested = 'pernottamenti_$date.xlsx';
      String path;
      if (!kIsWeb && Platform.isWindows) {
        final user = Platform.environment['USERPROFILE'] ?? '.';
        path = '$user\\Downloads\\$suggested';
      } else {
        final home = Platform.environment['HOME'] ?? '.';
        path = '$home/Downloads/$suggested';
      }
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      _snack('File esportato: $path');
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

    final res = await SupabaseService.client
        .from(kTable)
        .select()
        .eq(colStruttura, structId)
        .eq('status', 'IN_ATTESA');
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

  Future<void> _updateStato(_PernottoRowMobile r, String nuovoStato) async {
    if (!await ensureCanPersist(context)) return;
    try {
      await SupabaseService.client.from(kTable).update({'status': nuovoStato}).eq('id', r.id);
      final who = await _notifRecipientsLabel(r, 'update');
      if (!mounted) return;
      _snack('Stato aggiornato: $nuovoStato. Notifica inviata a: $who');
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

  Future<void> _confirmModify(_PernottoRowMobile r) async {
    if (!await ensureCanPersist(context)) return;
    final payload = r.modificaPayload;
    if (payload == null || payload.isEmpty) {
      _snack('Nessuna modifica proposta trovata.', error: true);
      return;
    }

    String pOr(String key) => (payload[key] ?? '').toString();
    final personaleNew = pOr(colPersonale).isNotEmpty ? pOr(colPersonale) : pOr('personale_id');
    final strutturaNew = pOr(colStruttura).isNotEmpty
        ? pOr(colStruttura)
        : (pOr('struttura_id').isNotEmpty ? pOr('struttura_id') : pOr('structure_id'));
    final commessaNew = pOr(colCommessa).isNotEmpty ? pOr(colCommessa) : pOr('commessa_id');
    final cameraNew = pOr('camera_tipo');
    final dalNew = pOr('start_date');
    final alNew = pOr('end_date');
    final noteNew = pOr('master_note');
    final effectiveDalIso =
        _normalizeDateIso(dalNew, fallback: _normalizeDateIso(r.startDate));
    final effectiveAlIso =
        _normalizeDateIso(alNew, fallback: _normalizeDateIso(r.endDate));
    final effectiveDalLabel =
        effectiveDalIso.isEmpty ? '—' : _fmtDate(effectiveDalIso);
    final effectiveAlLabel =
        effectiveAlIso.isEmpty ? '—' : _fmtDate(effectiveAlIso);

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
              Text('Persona: ${personaleNames[r.personaleId] ?? r.personaleId} → ${personaleNames[personaleNew] ?? personaleNew}'),
              Text('Struttura: ${structureNames[r.structureId] ?? r.structureId} → ${structureNames[strutturaNew] ?? strutturaNew}'),
              Text('Commessa: ${commessaNames[r.commessaId] ?? r.commessaId} → ${commessaNames[commessaNew] ?? commessaNew}'),
              Text('Dal: ${r.startDate} → $effectiveDalLabel'),
              Text('Al: ${r.endDate} → $effectiveAlLabel'),
              Text('Camera: ${r.cameraTipo} → ${cameraNew.isEmpty ? '—' : cameraNew}'),
              if (noteNew.isNotEmpty)
                NotePreviewText(
                  note: '${r.note} -> $noteNew',
                  prefix: 'Note: ',
                  maxChars: 10,
                ),
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
        'modifica_payload': null,
        'modifica_note': null,
        'modifica_requested_at': null,
      };
      await SupabaseService.client.from(kTable).update(update).eq('id', r.id);
      final who = await _notifRecipientsLabel(r, 'update');
      if (!mounted) return;
      _snack('Modifica confermata. Notifica inviata a: $who');

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

  Future<void> _createOrEdit({_PernottoRowMobile? row}) async {
    if (_insertOrSaveInFlight) return;
    if (!await ensureCanPersist(context)) return;
    final personaleMap = {for (final o in personaleOptions) o['id']!: o['label']!};
    final strutturaMap = {for (final o in strutturaOptions) o['id']!: o['label']!};
    final commessaMap = {for (final o in commessaOptions) o['id']!: o['label']!};

    final result = await showDialog<_PernottoRowMobile>(
      context: context,
      builder: (_) => _PernottoDialogMobile(
        personaleNames: personaleMap,
        structureNames: strutturaMap,
        commessaNames: commessaMap,
        row: row,
      ),
    );
    if (result == null) return;

    setState(() {
      loading = true;
      _insertOrSaveInFlight = true;
    });
    try {
      String? updatedBy;
      final session = SupabaseService.client.auth.currentSession;
      if (session != null) {
        final u = await SupabaseService.client
            .from('users')
            .select('id_uuid')
            .eq('auth_id', session.user.id)
            .maybeSingle();
        updatedBy = (u?['id_uuid'] as String?)?.trim();
        updatedBy ??= session.user.id;
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
        colPersonale: result.personaleId,
        colStruttura: result.structureId,
        colCommessa: result.commessaId,
        'camera_tipo': result.cameraTipo,
        'start_date': startIso,
        'end_date': endIso,
        'status': result.stato,
        'master_note': result.note,
        'updated_by': ?updatedBy,
      };

      if (row == null) {
        await SupabaseService.client.from(kTable).insert(payload);
        _snack('Pernotto creato');
      } else {
        await SupabaseService.client.from(kTable).update(payload).eq('id', row.id);
        final who = await _notifRecipientsLabel(row, 'update');
        if (!mounted) return;
        _snack('Pernotto aggiornato. Notifica inviata a: $who');
        if (row.dtUserUuid.isNotEmpty) {
          try {
            await NotificationSender.notifyUserForBooking(
              dtUserId: row.dtUserUuid,
              bookingId: row.id,
              action: 'update',
              title: 'Prenotazione aggiornata',
              bookingType: 'pernottamento',
            );
          } catch (_) {}
        }
      }
      await _loadRows();
    } catch (e) {
      _snack('Errore salvataggio: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          _insertOrSaveInFlight = false;
        });
      }
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
      _PernottoRowMobile? rowBefore;
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
        final b = await SupabaseService.client
            .from(kTable)
            .select('dt_user_uuid')
            .eq('id', id)
            .maybeSingle();
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

  String _buildPlainTextRoomsTable(List<dynamic> rowsData) {
    const headers = ['Persona', 'Dal', 'Al', 'Camera'];
    final cells = <List<String>>[];
    for (final r in rowsData) {
      final map = r as Map;
      final personaleId = (map[colPersonale] ?? '').toString();
      final personaLabel = (personaleNames[personaleId] ?? personaleId).trim();
      cells.add([
        personaLabel.isEmpty ? personaleId : personaLabel,
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
      if (widths[c] > 36) widths[c] = 36;
    }
    String padCell(String s, int w) {
      if (s.length <= w) return s.padRight(w);
      if (w <= 1) return s.substring(0, w);
      return '${s.substring(0, w - 1)}…';
    }

    String line(List<String> row) => List.generate(4, (i) => padCell(row[i], widths[i])).join(' | ');
    final sep = List.generate(4, (i) => '-' * widths[i]).join('-+-');
    final buf = StringBuffer()
      ..writeln(line(headers))
      ..writeln(sep);
    for (final row in cells) {
      buf.writeln(line(row));
    }
    return buf.toString().trimRight();
  }

  String _fmtDate(dynamic iso) {
    final raw = (iso ?? '').toString().trim();
    if (raw.isEmpty) return '';

    // Supporta sia yyyy-MM-dd che datetime ISO (prende i primi 10 chars).
    final yyyyMmDd = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final yyyyMmDdPrefix = RegExp(r'^\d{4}-\d{2}-\d{2}');

    if (yyyyMmDd.hasMatch(raw)) {
      final dd = raw.substring(8, 10);
      final mm = raw.substring(5, 7);
      final yyyy = raw.substring(0, 4);
      return '$dd/$mm/$yyyy';
    }

    if (yyyyMmDdPrefix.hasMatch(raw) && raw.length >= 10) {
      final v = raw.substring(0, 10);
      final dd = v.substring(8, 10);
      final mm = v.substring(5, 7);
      final yyyy = v.substring(0, 4);
      return '$dd/$mm/$yyyy';
    }

    // Se già nel formato dd/MM/yyyy, lascialo.
    final ddMmYyyy = RegExp(r'^\d{2}/\d{2}/\d{4}$');
    if (ddMmYyyy.hasMatch(raw)) return raw;

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return '${parsed.day.toString().padLeft(2, '0')}/'
          '${parsed.month.toString().padLeft(2, '0')}/'
          '${parsed.year}';
    }

    // Fallback: mostra raw senza trasformazioni.
    return raw;
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

  Future<String> _notifRecipientsLabel(_PernottoRowMobile r, String action) async {
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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN_ATTESA':
        return Colors.orange;
      case 'CONFERMATA':
        return Colors.green;
      case 'ANNULLATA':
        return Colors.redAccent;
      case 'RIFIUTATA':
        return Colors.red;
      case 'RICHIESTA_MODIFICA':
        return Colors.deepOrange;
      case 'CONFERMA_MODIFICA':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color? _rowHighlightColor(_PernottoRowMobile r) {
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

  bool _isOverduePending(_PernottoRowMobile r) {
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

  @override
  Widget build(BuildContext context) {
    final safeStrutturaFilter = _safeValue(strutturaFilter, structureNames);
    final safeCommessaFilter = _safeValue(commessaFilter, commessaNames);
    final safePersonaleFilter = _safeValue(personaleFilter, personaleNames);
    final safeDtFilter = _safeValue(dtFilter, dtNamesByUuid);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            AppLogo(size: useUltraCompactAppBar(context) ? 28 : 40),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Admin Pernottamenti',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
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
            tooltip: 'Esporta Excel',
            icon: const Icon(Icons.file_download),
            onPressed: _exportToExcel,
          ),
          IconButton(
            tooltip: 'Crea bozza Outlook',
            icon: const Icon(Icons.send),
            onPressed: _createOutlookDraftForStructure,
          ),
        ],
      )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _insertOrSaveInFlight ? null : () => _createOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo'),
      ),
      body: PageWithTopLogo(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                DropdownSearch<String>(
                                  items: kStatiAmmessiMobile,
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
                                  dropdownDecoratorProps: const DropDownDecoratorProps(
                                    dropdownSearchDecoration: InputDecoration(
                                      labelText: 'Stato',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownSearch<String>(
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
                                  dropdownDecoratorProps: const DropDownDecoratorProps(
                                    dropdownSearchDecoration: InputDecoration(
                                      labelText: 'Struttura',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownSearch<String>(
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
                                  dropdownDecoratorProps: const DropDownDecoratorProps(
                                    dropdownSearchDecoration: InputDecoration(
                                      labelText: 'Commessa',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownSearch<String>(
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
                                  dropdownDecoratorProps: const DropDownDecoratorProps(
                                    dropdownSearchDecoration: InputDecoration(
                                      labelText: 'Personale',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownSearch<String>(
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
                                  dropdownDecoratorProps: const DropDownDecoratorProps(
                                    dropdownSearchDecoration: InputDecoration(
                                      labelText: 'Richiedente',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Risultati: ${rows.length}', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        ...rows.map((r) {
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
                          final personaDisplayId =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      personaleProposedId.isNotEmpty)
                                  ? personaleProposedId
                                  : r.personaleId;
                          final strutturaDisplayId =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      strutturaProposedId.isNotEmpty)
                                  ? strutturaProposedId
                                  : r.structureId;
                          final commessaDisplayId =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      commessaProposedId.isNotEmpty)
                                  ? commessaProposedId
                                  : r.commessaId;
                          final cameraDisplay =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      cameraProposed.isNotEmpty)
                                  ? cameraProposed
                                  : r.cameraTipo;
                          final persona = (personaleNames[personaDisplayId] ??
                                  personaDisplayId)
                              .trim();
                          final struttura = (structureNames[strutturaDisplayId] ??
                                  strutturaDisplayId)
                              .trim();
                          final commessa = (commessaNames[commessaDisplayId] ??
                                  commessaDisplayId)
                              .trim();
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
                          final startDateDisplay =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      reqStartRaw.trim().isNotEmpty)
                                  ? _fmtDate(reqStartRaw)
                                  : r.startDate;
                          final endDateDisplay =
                              (r.stato == 'RICHIESTA_MODIFICA' &&
                                      reqEndRaw.trim().isNotEmpty)
                                  ? _fmtDate(reqEndRaw)
                                  : r.endDate;
                          final color = _statusColor(r.stato);
                          final overduePending = _isOverduePending(r);
                          final rowHighlight = _rowHighlightColor(r);
                          return Card(
                            color: rowHighlight,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${persona.isEmpty ? r.personaleId : persona}${isPersonaProposed ? ' (proposta)' : ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (v) => _updateStato(r, v),
                                        itemBuilder: (_) => kStatiAmmessiMobile
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
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text('Dal: $startDateDisplay'),
                                      if (isStartProposed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                        ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text('Al: $endDateDisplay'),
                                      if (isEndProposed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                        ),
                                    ],
                                  ),
                                  Text(
                                    'Struttura: ${struttura.isEmpty ? r.structureId : struttura}${isStrutturaProposed ? ' (proposta)' : ''}',
                                  ),
                                  Text(
                                    'Commessa: ${commessa.isEmpty ? r.commessaId : commessa}${isCommessaProposed ? ' (proposta)' : ''}',
                                  ),
                                  if (cameraDisplay.isNotEmpty)
                                    Text(
                                      'Camera: $cameraDisplay${isCameraProposed ? ' (proposta)' : ''}',
                                    ),
                                  if (r.note.isNotEmpty)
                                    NotePreviewText(
                                      note: r.note,
                                      prefix: 'Note: ',
                                      maxChars: 10,
                                    ),
                                  Text('Richiedente: ${richied.isEmpty ? r.dtUserUuid : richied}'),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (r.stato == 'RICHIESTA_MODIFICA')
                                        IconButton(
                                          tooltip: 'Conferma modifica',
                                          icon: const Icon(Icons.check_circle, color: Colors.blue),
                                          onPressed: () => _confirmModify(r),
                                        ),
                                      IconButton(
                                        tooltip: 'Modifica',
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _createOrEdit(row: r),
                                      ),
                                      IconButton(
                                        tooltip: 'Elimina',
                                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                                        onPressed: () => _delete(r.id),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PernottoRowMobile {
  final String id;
  final String personaleId;
  final String structureId;
  final String commessaId;
  final String cameraTipo;
  final String startDate;
  final String endDate;
  final String stato;
  final String note;
  final String dtUserUuid;
  final String createdBy;
  final String updatedBy;
  final Map<String, dynamic>? modificaPayload;
  final String modificaNote;
  final String modificaRequestedAt;

  _PernottoRowMobile({
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
    required this.modificaPayload,
    required this.modificaNote,
    required this.modificaRequestedAt,
  });
}

class _PernottoDialogMobile extends StatefulWidget {
  final Map<String, String> personaleNames;
  final Map<String, String> structureNames;
  final Map<String, String> commessaNames;
  final _PernottoRowMobile? row;

  const _PernottoDialogMobile({
    required this.personaleNames,
    required this.structureNames,
    required this.commessaNames,
    this.row,
  });

  @override
  State<_PernottoDialogMobile> createState() => _PernottoDialogMobileState();
}

class _PernottoDialogMobileState extends State<_PernottoDialogMobile> {
  final _formKey = GlobalKey<FormState>();
  String? personaleId;
  String? structureId;
  String? commessaId;
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
      personaleId = _safe(r.personaleId, widget.personaleNames);
      structureId = _safe(r.structureId, widget.structureNames);
      commessaId = _safe(r.commessaId, widget.commessaNames);
      cameraCtrl.text = r.cameraTipo;
      dal = parseFlexibleDateToDateTime(r.startDate);
      al = parseFlexibleDateToDateTime(r.endDate);
      stato = r.stato;
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
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  // Evita dipendenza a formatter esterni non disponibili in questo file.
  String _displayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString()}';

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
                DropdownSearch<String>(
                  items: widget.personaleNames.keys.toList(),
                  selectedItem: personaleId,
                  itemAsString: (id) => widget.personaleNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona il personale' : null,
                  onChanged: (v) => setState(() => personaleId = v),
                  popupProps: const PopupProps.menu(showSearchBox: true),
                  clearButtonProps: const ClearButtonProps(isVisible: true),
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: 'Personale',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownSearch<String>(
                  items: widget.structureNames.keys.toList(),
                  selectedItem: structureId,
                  itemAsString: (id) => widget.structureNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona la struttura' : null,
                  onChanged: (v) => setState(() => structureId = v),
                  popupProps: const PopupProps.menu(showSearchBox: true),
                  clearButtonProps: const ClearButtonProps(isVisible: true),
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: 'Struttura',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownSearch<String>(
                  items: widget.commessaNames.keys.toList(),
                  selectedItem: commessaId,
                  itemAsString: (id) => widget.commessaNames[id] ?? id,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona la commessa' : null,
                  onChanged: (v) => setState(() => commessaId = v),
                  popupProps: const PopupProps.menu(showSearchBox: true),
                  clearButtonProps: const ClearButtonProps(isVisible: true),
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: 'Commessa',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: cameraCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo camera',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
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
                DropdownSearch<String>(
                  items: kStatiAmmessiMobile,
                  selectedItem: kStatiAmmessiMobile.contains(stato) ? stato : null,
                  validator: (v) => (v == null || v.isEmpty) ? 'Seleziona lo stato' : null,
                  onChanged: (v) => setState(() => stato = v),
                  popupProps: const PopupProps.menu(),
                  clearButtonProps: const ClearButtonProps(isVisible: false),
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: 'Stato',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
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
              _PernottoRowMobile(
                id: '',
                personaleId: personaleId!,
                structureId: structureId!,
                commessaId: commessaId!,
                cameraTipo: cameraCtrl.text,
                startDate: _iso(dal!),
                endDate: _iso(al!),
                stato: stato!,
                note: noteCtrl.text,
                dtUserUuid: '',
                createdBy: '',
                updatedBy: '',
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

