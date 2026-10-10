import 'dart:convert';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deadline_nav_highlight.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/field_timestamps.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class AdminLogisticaAttrezzaturePage extends StatefulWidget {
  /// DT/assistente: sola lettura. Dipendente: usare [dipendenteMode].
  final bool readOnly;

  /// Vista dipendente: sola lettura + solo attrezzature assegnate a [fullName].
  final bool dipendenteMode;
  final String? fullName;

  const AdminLogisticaAttrezzaturePage({
    super.key,
    this.readOnly = false,
    this.dipendenteMode = false,
    this.fullName,
  });

  @override
  State<AdminLogisticaAttrezzaturePage> createState() => _AdminLogisticaAttrezzaturePageState();
}

class _AdminLogisticaAttrezzaturePageState extends State<AdminLogisticaAttrezzaturePage>
    with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  String? _commessaFilter;
  bool _showCompleteDesktop = false;
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();

  bool _deadlineUuidAnchorsMatch(String rowUuid) {
    final t = _deadlineScrollUuid?.trim().toLowerCase();
    final r = rowUuid.trim().toLowerCase();
    return t != null && t.isNotEmpty && r.isNotEmpty && t == r;
  }

  void _onDeadlineHighlightUuid(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _deadlineScrollUuid = trimmed;
      _search = '';
      _commessaFilter = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleDeadlineScrollToAnchor(_deadlineScrollAnchorKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deadlineScrollUuid = null);
      });
    });
  }

  /// Vero solo per admin/logistica (modifica consentita).
  bool get _canEdit => !widget.readOnly && !widget.dipendenteMode;

  /// Normalizza un nome persona: minuscolo, spazi collassati, token ordinati.
  static String _normPersonTokens(String raw) {
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    final tokens = cleaned.split(' ').where((t) => t.isNotEmpty).toList()..sort();
    return tokens.join(' ');
  }
  final Map<String, String> _commesse = <String, String>{};
  final Map<String, String> _utentiByUuid = <String, String>{};
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _expandedMobileId;
  bool _nfcBusy = false;

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  String _fmtDateCell(dynamic v) {
    final s = _fmtDate(v);
    return s.isEmpty ? '—' : s;
  }

  (double, double)? _extractCoords(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll('GPS:', '').trim();
    final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch(cleaned);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  Future<void> _openPositionOnMap(String positionRaw) async {
    final coords = _extractCoords(positionRaw);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna coordinata GPS valida.')),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    disposeDeadlineFlash();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadCommesse();
      await _loadRows();
    } finally {
      if (mounted) setState(() => _loading = false);
      maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
    }
  }

  Future<void> _loadCommesse() async {
    final res = await _supa.from('commesse').select('id_uuid,nome,active').eq('active', true).order('nome');
    _commesse
      ..clear()
      ..addEntries((res as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return MapEntry((m['id_uuid'] ?? '').toString(), (m['nome'] ?? '').toString());
      }));
  }

  Future<void> _loadRows() async {
    var q = _supa.from('logistica_attrezzature').select();
    if ((_commessaFilter ?? '').trim().isNotEmpty) {
      q = q.eq('commessa_id', _commessaFilter!);
    }
    final res = await q.order('codice_cronos', ascending: true);
    var list = List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    if (widget.dipendenteMode) {
      final mine = _normPersonTokens((widget.fullName ?? '').toString());
      list = mine.isEmpty
          ? const <Map<String, dynamic>>[]
          : list
              .where((r) => _normPersonTokens((r['assegnatario'] ?? '').toString()) == mine)
              .toList(growable: false);
    }
    if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final tokens = [
          r['codice_cronos'],
          r['assegnatario'],
          r['famiglia_attrezzi'],
          r['marca'],
          r['descrizione_articolo'],
          r['serial_number'],
          r['modello'],
          r['oda'],
          r['data_oda'],
          r['posizione'],
          r['ddt'],
          r['data_ultima_taratura'],
          r['data_prossima_taratura'],
          _fmtDate(r['data_ultima_taratura']),
          _fmtDate(r['data_prossima_taratura']),
          r['note'],
          _commesse[(r['commessa_id'] ?? '').toString()],
        ].map((v) => (v ?? '').toString().toLowerCase());
        return tokens.any((t) => t.contains(k));
      }).toList(growable: false);
    }
    final ids = <String>{};
    for (final r in list) {
      final c = (r['created_by_user_uuid'] ?? '').toString().trim();
      final u = (r['updated_by_user_uuid'] ?? '').toString().trim();
      if (c.isNotEmpty) ids.add(c);
      if (u.isNotEmpty) ids.add(u);
      mergeFieldTimestampActorUuids(r, ids);
    }
    final userMap = <String, String>{};
    if (ids.isNotEmpty) {
      userMap.addAll(await loadUserNamesByUuid(ids));
    }
    if (!mounted) return;
    setState(() {
      _rows = list;
      _utentiByUuid
        ..clear()
        ..addAll(userMap);
    });
  }

  DataCell _hoverCell(Widget child, Map<String, dynamic> r, String fieldKey) {
    return decorateDataCellWithAuditHover(
      DataCell(child),
      row: r,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  String _extractRef(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    if (s.contains('-')) s = s.split('-').first.trim();
    s = s.split(RegExp(r'\s+')).first.trim();
    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _isAutoRef(String ref) => RegExp(r'^(BOX|CON|A)\d+$', caseSensitive: false).hasMatch(ref);

  String _norm(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String? _findCommessaIdByText(String rawValue) {
    final target = _norm(rawValue.trim());
    if (target.isEmpty) return null;
    String? containsMatch;
    for (final entry in _commesse.entries) {
      final n = _norm(entry.value);
      if (n.isEmpty) continue;
      if (n == target) return entry.key;
      if (n.contains(target) || target.contains(n)) containsMatch ??= entry.key;
    }
    return containsMatch;
  }

  Future<String?> _resolveCommessaByPosizione(String posizione) async {
    final ref = _extractRef(posizione);
    if (!_isAutoRef(ref)) return null;

    final boxRes = await _supa
        .from('logistica_box')
        .select('numero_interno,codice_box,nome_box,commessa_id,active')
        .eq('active', true);
    for (final e in (boxRes as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final commessaId = (m['commessa_id'] ?? '').toString().trim();
      if (commessaId.isEmpty) continue;
      final refs = [
        _extractRef((m['numero_interno'] ?? '').toString()),
        _extractRef((m['codice_box'] ?? '').toString()),
        _extractRef((m['nome_box'] ?? '').toString()),
      ];
      if (refs.contains(ref)) return commessaId;
    }

    final mdoRes = await _supa
        .from('logistica_mdo_ferroviari')
        .select('matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,active')
        .eq('active', true);
    for (final e in (mdoRes as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final refs = [
        _extractRef((m['matricola_interna'] ?? '').toString()),
        _extractRef((m['descrizione_mezzo'] ?? '').toString()),
      ];
      if (!refs.contains(ref)) continue;
      final byCommessa = _findCommessaIdByText((m['commessa'] ?? '').toString());
      if (byCommessa != null) return byCommessa;
      final byCantiere = _findCommessaIdByText((m['cantiere_attuale'] ?? '').toString());
      if (byCantiere != null) return byCantiere;
    }
    return null;
  }

  Future<void> _bulkSyncCommesseFromPosizione() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiorna commesse'),
        content: const Text('Aggiornare tutte le commesse in base al campo Posizione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aggiorna')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final all = await _supa.from('logistica_attrezzature').select('id_uuid,posizione,commessa_id');
      int scanned = 0, updated = 0, skipped = 0, noMatch = 0, errors = 0;
      for (final e in (all as List)) {
        scanned++;
        final r = Map<String, dynamic>.from(e as Map);
        final id = (r['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) {
          skipped++;
          continue;
        }
        final pos = (r['posizione'] ?? '').toString();
        final resolved = await _resolveCommessaByPosizione(pos);
        if ((resolved ?? '').isEmpty) {
          noMatch++;
          continue;
        }
        final cur = (r['commessa_id'] ?? '').toString().trim();
        if (cur == resolved) {
          skipped++;
          continue;
        }
        try {
          await _supa.from('logistica_attrezzature').update({'commessa_id': resolved}).eq('id_uuid', id);
          updated++;
        } catch (_) {
          errors++;
        }
      }
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: updated > 0 ? Colors.green.shade700 : Colors.orange.shade800,
          content: Text(
            'Aggiornamento completato. Scansionate: $scanned, aggiornate: $updated, senza match: $noMatch, saltate: $skipped, errori: $errors',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    if (!_canEdit) {
      if (row != null) await _openDetail(row);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AttrezzaturaDialog(
        row: row,
        commesse: _commesse,
      ),
    );
    if (ok == true) await _loadRows();
  }

  Future<List<Map<String, dynamic>>> _loadStoricoForRow(String id) async {
    if (id.trim().isEmpty) return const <Map<String, dynamic>>[];
    try {
      final res = await _supa
          .from('logistica_attrezzature_assegnatari_storico')
          .select()
          .eq('attrezzatura_id', id)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _openDetail(Map<String, dynamic> r) async {
    final storico = await _loadStoricoForRow((r['id_uuid'] ?? '').toString());
    if (!mounted) return;
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
              children: [
                TextSpan(
                  text: value.trim().isEmpty ? '—' : value,
                  style: const TextStyle(fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dettaglio attrezzatura'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                line('Codice Cronos', (r['codice_cronos'] ?? '').toString()),
                line('Assegnatario', (r['assegnatario'] ?? '').toString()),
                line('Data assegnazione', _fmtDate(r['data_assegnazione'])),
                line('Famiglia', (r['famiglia_attrezzi'] ?? '').toString()),
                line('Marca', (r['marca'] ?? '').toString()),
                line('Descrizione', (r['descrizione_articolo'] ?? '').toString()),
                line('Serial number', (r['serial_number'] ?? '').toString()),
                line('Modello', (r['modello'] ?? '').toString()),
                line('Posizione', (r['posizione'] ?? '').toString()),
                line('Data ultima taratura', _fmtDate(r['data_ultima_taratura'])),
                line('Data prossima taratura', _fmtDate(r['data_prossima_taratura'])),
                line('Note', (r['note'] ?? '').toString()),
                line('Commessa', _commesse[(r['commessa_id'] ?? '').toString()] ?? ''),
                const Divider(height: 18),
                const Text('Storico assegnatari precedenti', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (storico.isEmpty)
                  const Text('Nessun assegnatario precedente.', style: TextStyle(color: Colors.grey))
                else
                  ...storico.map((s) {
                    final ass = (s['assegnatario'] ?? '').toString();
                    final dal = _fmtDate(s['data_assegnazione']);
                    final al = _fmtDate(s['data_fine']);
                    final note = (s['note'] ?? '').toString();
                    final periodo = [
                      if (dal.isNotEmpty) 'dal $dal',
                      if (al.isNotEmpty) 'al $al',
                    ].join(' ');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ass.isEmpty ? '—' : ass, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (periodo.isNotEmpty) Text(periodo, style: const TextStyle(fontSize: 12)),
                          if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Map<String, dynamic> _nfcPayloadForRow(Map<String, dynamic> r) {
    return <String, dynamic>{
      'kind': 'logistica_attrezzature_v1',
      'id_uuid': (r['id_uuid'] ?? '').toString(),
      'codice_cronos': (r['codice_cronos'] ?? '').toString(),
      'serial_number': (r['serial_number'] ?? '').toString(),
      'descrizione_articolo': (r['descrizione_articolo'] ?? '').toString(),
      'modello': (r['modello'] ?? '').toString(),
      'famiglia_attrezzi': (r['famiglia_attrezzi'] ?? '').toString(),
      'marca': (r['marca'] ?? '').toString(),
      'posizione': (r['posizione'] ?? '').toString(),
      'commessa_id': (r['commessa_id'] ?? '').toString(),
      'commessa_nome': _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
    };
  }

  String? _decodeNdefTextRecord(NdefRecord record) {
    final payload = record.payload;
    if (payload.isEmpty) return null;
    final langLen = payload.first & 0x3F;
    if (payload.length <= langLen + 1) return null;
    return utf8.decode(payload.sublist(1 + langLen), allowMalformed: true);
  }

  Future<void> _writeNfcTagForRow(Map<String, dynamic> r) async {
    if (_nfcBusy) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scrittura NFC disponibile solo su Android.')),
        );
      }
      return;
    }
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC non disponibile su questo dispositivo.')),
        );
      }
      return;
    }
    setState(() => _nfcBusy = true);
    var handled = false;
    try {
      final payload = jsonEncode(_nfcPayloadForRow(r));
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        noPlatformSoundsAndroid: true,
        onDiscovered: (NfcTag tag) async {
          if (handled) return;
          handled = true;
          try {
            var msg = NdefMessage(records: [_createTextRecord(payload)]);
            final ndef = NdefAndroid.from(tag);
            if (ndef != null) {
              if (!ndef.isWritable) throw Exception('Tag in sola lettura.');
              if (msg.byteLength > ndef.maxSize) {
                throw Exception('Tag troppo piccolo (${msg.byteLength}/${ndef.maxSize}).');
              }
              await ndef.writeNdefMessage(msg);
            } else {
              final formatable = NdefFormatableAndroid.from(tag);
              if (formatable == null) throw Exception('Tag non compatibile con scrittura NDEF.');
              await formatable.format(msg);
            }
            await NfcManager.instance.stopSession(alertMessageIos: 'Tag NFC scritto con successo.');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scrittura NFC completata.')),
              );
            }
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessageIos: e.toString());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Errore NFC: $e')),
              );
            }
          }
        },
      );
    } finally {
      if (mounted) setState(() => _nfcBusy = false);
    }
  }

  Future<void> _readNfcTagAndOpenTool() async {
    if (_nfcBusy) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lettura NFC disponibile solo su Android.')),
        );
      }
      return;
    }
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC non disponibile su questo dispositivo.')),
        );
      }
      return;
    }
    setState(() => _nfcBusy = true);
    var handled = false;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        noPlatformSoundsAndroid: true,
        onDiscovered: (NfcTag tag) async {
          if (handled) return;
          handled = true;
          try {
            final ndef = NdefAndroid.from(tag);
            final msg = ndef?.cachedNdefMessage;
            if (msg == null || msg.records.isEmpty) {
              await NfcManager.instance.stopSession(errorMessageIos: 'Tag NFC vuoto o non valido.');
              return;
            }
            final decoded = _decodeNdefTextRecord(msg.records.first);
            if (decoded == null || decoded.trim().isEmpty) {
              await NfcManager.instance.stopSession(errorMessageIos: 'Dati NFC non leggibili.');
              return;
            }
            final obj = jsonDecode(decoded);
            if (obj is! Map<String, dynamic>) {
              await NfcManager.instance.stopSession(errorMessageIos: 'Formato dati NFC non supportato.');
              return;
            }
            if ((obj['kind'] ?? '').toString() != 'logistica_attrezzature_v1') {
              await NfcManager.instance.stopSession(errorMessageIos: 'Tag NFC non è di Attrezzature.');
              return;
            }
            final id = (obj['id_uuid'] ?? '').toString().trim();
            if (id.isEmpty) {
              await NfcManager.instance.stopSession(errorMessageIos: 'Tag NFC senza ID attrezzatura.');
              return;
            }
            Map<String, dynamic>? row;
            for (final r in _rows) {
              if ((r['id_uuid'] ?? '').toString().trim() == id) {
                row = r;
                break;
              }
            }
            if (row == null) {
              final fetched = await _supa.from('logistica_attrezzature').select().eq('id_uuid', id).maybeSingle();
              if (fetched != null) row = Map<String, dynamic>.from(fetched as Map);
            }
            await NfcManager.instance.stopSession(alertMessageIos: 'Tag NFC letto.');
            if (!mounted) return;
            if (row == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Attrezzatura non trovata (ID: $id).')),
              );
              return;
            }
            await _openForm(row: row);
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessageIos: e.toString());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Errore NFC: $e')),
              );
            }
          }
        },
      );
    } finally {
      if (mounted) setState(() => _nfcBusy = false);
    }
  }

  NdefRecord _createTextRecord(String text, {String languageCode = 'it'}) {
    final langBytes = utf8.encode(languageCode);
    final textBytes = utf8.encode(text);
    final payload = Uint8List(1 + langBytes.length + textBytes.length)
      ..[0] = langBytes.length
      ..setRange(1, 1 + langBytes.length, langBytes)
      ..setRange(1 + langBytes.length, 1 + langBytes.length + textBytes.length, textBytes);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList(utf8.encode('T')),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  Future<void> _deleteRow(String idUuid) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina attrezzatura'),
        content: const Text('Confermi eliminazione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('logistica_attrezzature').delete().eq('id_uuid', idUuid);
    await _loadRows();
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
    final excel = Excel.createExcel();
    final sheet = excel['Attrezzature'];
    sheet.appendRow([
      'CODICE CRONOS',
      'ASSEGNATARIO',
      'FAMIGLIA ATTREZZI',
      'MARCA',
      'DESCRIZIONE ARTICOLO',
      'SERIAL NUMBER',
      'MODELLO',
      'ODA',
      'DATA ODA',
      'POSIZIONE',
      'DDT',
      'DATA ULTIMA TARATURA',
      'DATA PROSSIMA TARATURA',
      'NOTE',
      'COMMESSA',
    ]);
    for (final r in _rows) {
      sheet.appendRow([
        (r['codice_cronos'] ?? '').toString(),
        (r['assegnatario'] ?? '').toString(),
        (r['famiglia_attrezzi'] ?? '').toString(),
        (r['marca'] ?? '').toString(),
        (r['descrizione_articolo'] ?? '').toString(),
        (r['serial_number'] ?? '').toString(),
        (r['modello'] ?? '').toString(),
        (r['oda'] ?? '').toString(),
        _fmtDate(r['data_oda']),
        (r['posizione'] ?? '').toString(),
        (r['ddt'] ?? '').toString(),
        _fmtDate(r['data_ultima_taratura']),
        _fmtDate(r['data_prossima_taratura']),
        (r['note'] ?? '').toString(),
        _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
      ]);
    }
    final bytes = Uint8List.fromList(excel.encode()!);
    await ExcelExportHelper.saveAndReveal(pageName: 'Attrezzature', bytes: bytes);
  }

  Widget _mobileInfo(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    );
  }

  Widget _mobileMetaChip({required IconData icon, required String text}) {
    final shown = text.trim().isEmpty ? '—' : text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey.shade700),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              shown,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList() {
    if (_rows.isEmpty) return const Center(child: Text('Nessuna attrezzatura trovata'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _rows[index];
        final id = (r['id_uuid'] ?? '').toString();
        final tileKey = id.isEmpty ? 'row_$index' : id;
        final isExpanded = _expandedMobileId == tileKey;
        final code = (r['codice_cronos'] ?? '').toString();
        final serial = (r['serial_number'] ?? '').toString();
        final posizione = (r['posizione'] ?? '').toString();
        final famiglia = (r['famiglia_attrezzi'] ?? '').toString();
        final flash = id.isNotEmpty && deadlineFlashLit(id);
        return KeyedSubtree(
          key: _deadlineUuidAnchorsMatch(id)
              ? _deadlineScrollAnchorKey
              : ValueKey<String>('attrezzature_mobile_card_$tileKey'),
          child: Card(
          elevation: 2,
          color: flash ? Colors.amber.withValues(alpha: 0.42) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ExpansionTile(
            key: PageStorageKey<String>('attrezzature_mobile_$tileKey'),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() => _expandedMobileId = expanded ? tileKey : null);
            },
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            title: Text(
              serial.trim().isEmpty ? 'Serial: —' : 'Serial: $serial',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  code.trim().isEmpty ? 'Codice: —' : 'Codice: $code',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _mobileMetaChip(icon: Icons.precision_manufacturing_outlined, text: famiglia),
                    _mobileMetaChip(icon: Icons.place_outlined, text: posizione),
                  ],
                ),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            children: [
              _mobileInfo('Assegnatario', (r['assegnatario'] ?? '').toString()),
              _mobileInfo('Famiglia', (r['famiglia_attrezzi'] ?? '').toString()),
              _mobileInfo('Marca', (r['marca'] ?? '').toString()),
              _mobileInfo('Descrizione', (r['descrizione_articolo'] ?? '').toString()),
              _mobileInfo('Modello', (r['modello'] ?? '').toString()),
              _mobileInfo('Posizione', (r['posizione'] ?? '').toString()),
              _mobileInfo('Data ultima taratura', _fmtDate(r['data_ultima_taratura'])),
              _mobileInfo('Data prossima taratura', _fmtDate(r['data_prossima_taratura'])),
              _mobileInfo('Commessa', _commesse[(r['commessa_id'] ?? '').toString()] ?? ''),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Apri su Maps',
                    onPressed: _extractCoords((r['posizione'] ?? '').toString()) == null
                        ? null
                        : () => _openPositionOnMap((r['posizione'] ?? '').toString()),
                    icon: const Icon(Icons.map_outlined),
                  ),
                  if (_canEdit) ...[
                    IconButton(tooltip: 'Scrivi tag NFC', onPressed: _nfcBusy ? null : () => _writeNfcTagForRow(r), icon: const Icon(Icons.nfc)),
                    IconButton(tooltip: 'Modifica', onPressed: () => _openForm(row: r), icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                      tooltip: 'Elimina',
                      onPressed: id.isEmpty ? null : () => _deleteRow(id),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ] else
                    IconButton(
                      tooltip: 'Dettaglio',
                      onPressed: () => _openDetail(r),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                ],
              )
            ],
          ),
          ),
        );
      },
    );
  }

  List<DataColumn> _desktopColumns() {
    if (_showCompleteDesktop) {
      return const [
        DataColumn(label: Text('CODICE CRONOS')),
        DataColumn(label: Text('ASSEGNATARIO')),
        DataColumn(label: Text('FAMIGLIA')),
        DataColumn(label: Text('MARCA')),
        DataColumn(label: Text('DESCRIZIONE')),
        DataColumn(label: Text('SERIAL')),
        DataColumn(label: Text('MODELLO')),
        DataColumn(label: Text('ODA')),
        DataColumn(label: Text('DATA ODA')),
        DataColumn(label: Text('POSIZIONE')),
        DataColumn(label: Text('DDT')),
        DataColumn(label: Text('DATA ULTIMA TARATURA')),
        DataColumn(label: Text('DATA PROSSIMA TARATURA')),
        DataColumn(label: Text('NOTE')),
        DataColumn(label: Text('COMMESSA')),
        DataColumn(label: Text('AZIONI')),
      ];
    }
    return const [
      DataColumn(label: Text('CODICE')),
      DataColumn(label: Text('SERIAL')),
      DataColumn(label: Text('FAMIGLIA')),
      DataColumn(label: Text('DESCRIZIONE')),
      DataColumn(label: Text('ASSEGNATARIO')),
      DataColumn(label: Text('DATA ULTIMA TARATURA')),
      DataColumn(label: Text('DATA PROSSIMA TARATURA')),
      DataColumn(label: Text('COMMESSA')),
      DataColumn(label: Text('AZIONI')),
    ];
  }

  List<DataCell> _desktopCells(Map<String, dynamic> r) {
    final id = (r['id_uuid'] ?? '').toString();
    final actions = DataCell(_canEdit
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Scrivi tag NFC',
                icon: const Icon(Icons.nfc),
                visualDensity: VisualDensity.compact,
                onPressed: _nfcBusy ? null : () => _writeNfcTagForRow(r),
              ),
              IconButton(
                tooltip: 'Modifica',
                icon: const Icon(Icons.edit_outlined),
                visualDensity: VisualDensity.compact,
                onPressed: () => _openForm(row: r),
              ),
              IconButton(
                tooltip: 'Elimina',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                visualDensity: VisualDensity.compact,
                onPressed: id.isEmpty ? null : () => _deleteRow(id),
              ),
            ],
          )
        : IconButton(
            tooltip: 'Dettaglio',
            icon: const Icon(Icons.visibility_outlined),
            visualDensity: VisualDensity.compact,
            onPressed: () => _openDetail(r),
          ));

    if (_showCompleteDesktop) {
      return [
        _hoverCell(SizedBox(width: 120, child: Text((r['codice_cronos'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'codice_cronos'),
        _hoverCell(SizedBox(width: 160, child: Text((r['assegnatario'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'assegnatario'),
        _hoverCell(SizedBox(width: 120, child: Text((r['famiglia_attrezzi'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'famiglia_attrezzi'),
        _hoverCell(SizedBox(width: 90, child: Text((r['marca'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'marca'),
        _hoverCell(SizedBox(width: 220, child: Text((r['descrizione_articolo'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'descrizione_articolo'),
        _hoverCell(SizedBox(width: 120, child: Text((r['serial_number'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'serial_number'),
        _hoverCell(SizedBox(width: 120, child: Text((r['modello'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'modello'),
        _hoverCell(SizedBox(width: 90, child: Text((r['oda'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'oda'),
        _hoverCell(SizedBox(width: 90, child: Text(_fmtDate(r['data_oda']), overflow: TextOverflow.ellipsis)), r, 'data_oda'),
        _hoverCell(SizedBox(width: 180, child: Text((r['posizione'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'posizione'),
        _hoverCell(SizedBox(width: 100, child: Text((r['ddt'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'ddt'),
        _hoverCell(SizedBox(width: 130, child: Text(_fmtDateCell(r['data_ultima_taratura']), overflow: TextOverflow.ellipsis)), r, 'data_ultima_taratura'),
        _hoverCell(SizedBox(width: 140, child: Text(_fmtDateCell(r['data_prossima_taratura']), overflow: TextOverflow.ellipsis)), r, 'data_prossima_taratura'),
        _hoverCell(SizedBox(width: 160, child: Text((r['note'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'note'),
        _hoverCell(SizedBox(width: 150, child: Text(_commesse[(r['commessa_id'] ?? '').toString()] ?? '', overflow: TextOverflow.ellipsis)), r, 'commessa_id'),
        actions,
      ];
    }

    return [
      _hoverCell(SizedBox(width: 120, child: Text((r['codice_cronos'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'codice_cronos'),
      _hoverCell(SizedBox(width: 130, child: Text((r['serial_number'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'serial_number'),
      _hoverCell(SizedBox(width: 120, child: Text((r['famiglia_attrezzi'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'famiglia_attrezzi'),
      _hoverCell(SizedBox(width: 260, child: Text((r['descrizione_articolo'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'descrizione_articolo'),
      _hoverCell(SizedBox(width: 180, child: Text((r['assegnatario'] ?? '').toString(), overflow: TextOverflow.ellipsis)), r, 'assegnatario'),
      _hoverCell(SizedBox(width: 130, child: Text(_fmtDateCell(r['data_ultima_taratura']), overflow: TextOverflow.ellipsis)), r, 'data_ultima_taratura'),
      _hoverCell(SizedBox(width: 140, child: Text(_fmtDateCell(r['data_prossima_taratura']), overflow: TextOverflow.ellipsis)), r, 'data_prossima_taratura'),
      _hoverCell(SizedBox(width: 150, child: Text(_commesse[(r['commessa_id'] ?? '').toString()] ?? '', overflow: TextOverflow.ellipsis)), r, 'commessa_id'),
      actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout = isLogisticaCompactLayout(context);
    final commessaItems = _commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Logistica - Attrezzature'),
        actions: [
          if (!isMobileLayout)
            IconButton(tooltip: 'Export Excel', onPressed: _exportExcel, icon: const Icon(Icons.download_outlined)),
          if (_canEdit)
            IconButton(
              tooltip: 'Leggi tag NFC',
              onPressed: _nfcBusy ? null : _readNfcTagAndOpenTool,
              icon: _nfcBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.nfc),
            ),
          if (_canEdit && !isMobileLayout)
            IconButton(tooltip: 'Nuova attrezzatura', onPressed: () => _openForm(), icon: const Icon(Icons.add)),
          if (_canEdit && !isMobileLayout)
            IconButton(
              tooltip: 'Aggiorna commesse in base a posizione',
              onPressed: _bulkSyncCommesseFromPosizione,
              icon: const Icon(Icons.sync_alt),
            ),
          IconButton(tooltip: 'Ricarica', onPressed: _loadRows, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (isMobileLayout)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_canEdit)
                            FilledButton.icon(
                              onPressed: () => _openForm(),
                              icon: const Icon(Icons.add),
                              label: const Text('Nuova'),
                            ),
                          if (_canEdit)
                            OutlinedButton.icon(
                              onPressed: _bulkSyncCommesseFromPosizione,
                              icon: const Icon(Icons.sync_alt),
                              label: const Text('Sync commesse'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _exportExcel,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Excel'),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: logisticaFieldWidth(context, desktop: 320),
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Cerca codice, serial, famiglia, marca, posizione...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) async {
                              _search = v;
                              await _loadRows();
                            },
                          ),
                        ),
                        SizedBox(
                          width: logisticaFieldWidth(context, desktop: 280),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _commessaFilter,
                            decoration: const InputDecoration(labelText: 'Commessa', border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem<String>(value: null, child: Text('Tutte')),
                              ...commessaItems.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))),
                            ],
                            onChanged: (v) async {
                              setState(() => _commessaFilter = v);
                              await _loadRows();
                            },
                          ),
                        ),
                        if (!isMobileLayout)
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(value: false, label: Text('Semplificata')),
                              ButtonSegment<bool>(value: true, label: Text('Completa')),
                            ],
                            selected: <bool>{_showCompleteDesktop},
                            onSelectionChanged: (sel) {
                              setState(() => _showCompleteDesktop = sel.first);
                            },
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: isMobileLayout
                        ? _buildMobileList()
                        : logisticaScrollableTable(
                            context: context,
                            child: SingleChildScrollView(
                              child: DataTable(
                                showCheckboxColumn: false,
                                columnSpacing: 8,
                                headingRowHeight: 40,
                                dataRowMinHeight: 34,
                                dataRowMaxHeight: 42,
                                columns: _desktopColumns(),
                                rows: _rows.map((r) {
                                  final id = (r['id_uuid'] ?? '').toString();
                                  final cells =
                                      _desktopCells(r).toList(growable: true);
                                  if (cells.isNotEmpty &&
                                      _deadlineUuidAnchorsMatch(id)) {
                                    cells[0] = DataCell(
                                      KeyedSubtree(
                                        key: _deadlineScrollAnchorKey,
                                        child: cells[0].child,
                                      ),
                                    );
                                  }
                                  return DataRow(
                                    color: WidgetStateProperty
                                        .resolveWith<Color?>((_) =>
                                            deadlineFlashLit(id)
                                                ? Colors.amber
                                                    .withValues(alpha: 0.42)
                                                : null),
                                    onSelectChanged: (_) => _openForm(row: r),
                                    cells: cells,
                                  );
                                }).toList(growable: false),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AttrezzaturaDialog extends StatefulWidget {
  final Map<String, dynamic>? row;
  final Map<String, String> commesse;
  const _AttrezzaturaDialog({required this.row, required this.commesse});

  @override
  State<_AttrezzaturaDialog> createState() => _AttrezzaturaDialogState();
}

class _AttrezzaturaDialogState extends State<_AttrezzaturaDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController codiceCtrl;
  late final TextEditingController assegnatarioCtrl;
  late final TextEditingController famigliaCtrl;
  late final TextEditingController marcaCtrl;
  late final TextEditingController descrizioneCtrl;
  late final TextEditingController serialCtrl;
  late final TextEditingController modelloCtrl;
  late final TextEditingController odaCtrl;
  late final TextEditingController dataOdaCtrl;
  late final TextEditingController posizioneCtrl;
  late final TextEditingController ddtCtrl;
  late final TextEditingController dataUltimaTaraturaCtrl;
  late final TextEditingController dataProssimaTaraturaCtrl;
  late final TextEditingController noteCtrl;
  late final TextEditingController dataAssegnazioneCtrl;
  late final TextEditingController commessaSearchCtrl;
  String? commessaSel;
  bool _gpsLoading = false;

  /// Assegnatario salvato a DB (per auto-archivio al cambio).
  late final String _originalAssegnatario;
  late final String _originalDataAssegnazione;

  /// Storico assegnatari precedenti (in memoria, persistito al salvataggio).
  final List<Map<String, dynamic>> _storico = <Map<String, dynamic>>[];
  final List<String> _storicoDeletedIds = <String>[];
  bool _storicoLoading = false;

  (double, double)? _extractCoords(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll('GPS:', '').trim();
    final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch(cleaned);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? <String, dynamic>{};
    codiceCtrl = TextEditingController(text: (r['codice_cronos'] ?? '').toString());
    assegnatarioCtrl = TextEditingController(text: (r['assegnatario'] ?? '').toString());
    famigliaCtrl = TextEditingController(text: (r['famiglia_attrezzi'] ?? '').toString());
    marcaCtrl = TextEditingController(text: (r['marca'] ?? '').toString());
    descrizioneCtrl = TextEditingController(text: (r['descrizione_articolo'] ?? '').toString());
    serialCtrl = TextEditingController(text: (r['serial_number'] ?? '').toString());
    modelloCtrl = TextEditingController(text: (r['modello'] ?? '').toString());
    odaCtrl = TextEditingController(text: (r['oda'] ?? '').toString());
    dataOdaCtrl = TextEditingController(text: formatDateDdMmYyyy(r['data_oda']));
    posizioneCtrl = TextEditingController(text: (r['posizione'] ?? '').toString());
    ddtCtrl = TextEditingController(text: (r['ddt'] ?? '').toString());
    dataUltimaTaraturaCtrl =
        TextEditingController(text: formatDateDdMmYyyy(r['data_ultima_taratura']));
    dataProssimaTaraturaCtrl =
        TextEditingController(text: formatDateDdMmYyyy(r['data_prossima_taratura']));
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
    dataAssegnazioneCtrl = TextEditingController(text: formatDateDdMmYyyy(r['data_assegnazione']));
    _originalAssegnatario = (r['assegnatario'] ?? '').toString().trim();
    _originalDataAssegnazione = (r['data_assegnazione'] ?? '').toString().trim();
    commessaSel = (r['commessa_id'] ?? '').toString().trim().isEmpty ? null : (r['commessa_id'] ?? '').toString();
    commessaSearchCtrl = TextEditingController(text: widget.commesse[commessaSel ?? ''] ?? '');
    _loadStorico();
  }

  Future<void> _loadStorico() async {
    final id = (widget.row?['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    setState(() => _storicoLoading = true);
    try {
      final res = await _supa
          .from('logistica_attrezzature_assegnatari_storico')
          .select()
          .eq('attrezzatura_id', id)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (!mounted) return;
      setState(() {
        _storico
          ..clear()
          ..addAll(list);
        _storicoLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _storicoLoading = false);
    }
  }

  @override
  void dispose() {
    codiceCtrl.dispose();
    assegnatarioCtrl.dispose();
    famigliaCtrl.dispose();
    marcaCtrl.dispose();
    descrizioneCtrl.dispose();
    serialCtrl.dispose();
    modelloCtrl.dispose();
    odaCtrl.dispose();
    dataOdaCtrl.dispose();
    posizioneCtrl.dispose();
    ddtCtrl.dispose();
    dataUltimaTaraturaCtrl.dispose();
    dataProssimaTaraturaCtrl.dispose();
    noteCtrl.dispose();
    dataAssegnazioneCtrl.dispose();
    commessaSearchCtrl.dispose();
    super.dispose();
  }

  String _extractRef(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    if (s.contains('-')) s = s.split('-').first.trim();
    s = s.split(RegExp(r'\s+')).first.trim();
    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _isAutoRef(String ref) => RegExp(r'^(BOX|CON|A)\d+$', caseSensitive: false).hasMatch(ref);
  String _norm(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String? _findCommessaIdByText(String rawValue) {
    final target = _norm(rawValue.trim());
    if (target.isEmpty) return null;
    String? containsMatch;
    for (final entry in widget.commesse.entries) {
      final n = _norm(entry.value);
      if (n.isEmpty) continue;
      if (n == target) return entry.key;
      if (n.contains(target) || target.contains(n)) containsMatch ??= entry.key;
    }
    return containsMatch;
  }

  Future<String?> _resolveCommessaByPosizione(String posizione) async {
    final ref = _extractRef(posizione);
    if (!_isAutoRef(ref)) return null;

    final boxRes = await _supa
        .from('logistica_box')
        .select('numero_interno,codice_box,nome_box,commessa_id,active')
        .eq('active', true);
    for (final e in (boxRes as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final commessaId = (m['commessa_id'] ?? '').toString().trim();
      if (commessaId.isEmpty) continue;
      final refs = [
        _extractRef((m['numero_interno'] ?? '').toString()),
        _extractRef((m['codice_box'] ?? '').toString()),
        _extractRef((m['nome_box'] ?? '').toString()),
      ];
      if (refs.contains(ref)) return commessaId;
    }

    final mdoRes = await _supa
        .from('logistica_mdo_ferroviari')
        .select('matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,active')
        .eq('active', true);
    for (final e in (mdoRes as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final refs = [
        _extractRef((m['matricola_interna'] ?? '').toString()),
        _extractRef((m['descrizione_mezzo'] ?? '').toString()),
      ];
      if (!refs.contains(ref)) continue;
      final byCommessa = _findCommessaIdByText((m['commessa'] ?? '').toString());
      if (byCommessa != null) return byCommessa;
      final byCantiere = _findCommessaIdByText((m['cantiere_attuale'] ?? '').toString());
      if (byCantiere != null) return byCantiere;
    }
    return null;
  }

  String? _optionalIsoDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return parseFlexibleDateToIsoDate(t);
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final autoCommessaId = await _resolveCommessaByPosizione(posizioneCtrl.text);
    final effectiveCommessa = autoCommessaId ?? commessaSel;
    final payload = <String, dynamic>{
      'codice_cronos': codiceCtrl.text.trim().isEmpty ? null : codiceCtrl.text.trim(),
      'assegnatario': assegnatarioCtrl.text.trim().isEmpty ? null : assegnatarioCtrl.text.trim(),
      'famiglia_attrezzi': famigliaCtrl.text.trim().isEmpty ? null : famigliaCtrl.text.trim(),
      'marca': marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
      'descrizione_articolo': descrizioneCtrl.text.trim().isEmpty ? null : descrizioneCtrl.text.trim(),
      'serial_number': serialCtrl.text.trim().isEmpty ? null : serialCtrl.text.trim(),
      'modello': modelloCtrl.text.trim().isEmpty ? null : modelloCtrl.text.trim(),
      'oda': odaCtrl.text.trim().isEmpty ? null : odaCtrl.text.trim(),
      'data_oda': () {
        final raw = dataOdaCtrl.text.trim();
        if (raw.isEmpty) return null;
        return parseFlexibleDateToIsoDate(raw) ?? raw;
      }(),
      'posizione': posizioneCtrl.text.trim().isEmpty ? null : posizioneCtrl.text.trim(),
      'ddt': ddtCtrl.text.trim().isEmpty ? null : ddtCtrl.text.trim(),
      'data_ultima_taratura': _optionalIsoDate(dataUltimaTaraturaCtrl.text),
      'data_prossima_taratura': _optionalIsoDate(dataProssimaTaraturaCtrl.text),
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'data_assegnazione': () {
        final raw = dataAssegnazioneCtrl.text.trim();
        if (raw.isEmpty) return null;
        return parseFlexibleDateToIsoDate(raw) ?? raw;
      }(),
      'commessa_id': effectiveCommessa,
      'active': true,
    };

    final newAssegnatario = assegnatarioCtrl.text.trim();
    final assegnatarioChanged = _originalAssegnatario.isNotEmpty &&
        _normPersonTokens(_originalAssegnatario) != _normPersonTokens(newAssegnatario);

    var id = (widget.row?['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) {
      final inserted = await _supa.from('logistica_attrezzature').insert(payload).select('id_uuid').single();
      id = (inserted['id_uuid'] ?? '').toString().trim();
    } else {
      // Cambio assegnatario: archivia il precedente nello storico.
      if (assegnatarioChanged) {
        await _supa.from('logistica_attrezzature_assegnatari_storico').insert({
          'attrezzatura_id': id,
          'assegnatario': _originalAssegnatario,
          'data_assegnazione': _originalDataAssegnazione.isEmpty ? null : _originalDataAssegnazione,
          'data_fine': DateTime.now().toIso8601String().split('T').first,
          'note': 'Archiviato automaticamente al cambio assegnatario',
        });
      }
      await _supa.from('logistica_attrezzature').update(payload).eq('id_uuid', id);
    }

    await _persistStorico(id);

    if (mounted) Navigator.pop(context, true);
  }

  static String _normPersonTokens(String raw) {
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    final tokens = cleaned.split(' ').where((t) => t.isNotEmpty).toList()..sort();
    return tokens.join(' ');
  }

  Future<void> _persistStorico(String attrezzaturaId) async {
    if (attrezzaturaId.isEmpty) return;
    for (final delId in _storicoDeletedIds) {
      if (delId.trim().isEmpty) continue;
      await _supa.from('logistica_attrezzature_assegnatari_storico').delete().eq('id_uuid', delId);
    }
    for (final s in _storico) {
      final payload = <String, dynamic>{
        'attrezzatura_id': attrezzaturaId,
        'assegnatario': (s['assegnatario'] ?? '').toString().trim().isEmpty
            ? null
            : (s['assegnatario'] ?? '').toString().trim(),
        'data_assegnazione': () {
          final raw = (s['data_assegnazione'] ?? '').toString().trim();
          if (raw.isEmpty) return null;
          return parseFlexibleDateToIsoDate(raw) ?? raw;
        }(),
        'data_fine': () {
          final raw = (s['data_fine'] ?? '').toString().trim();
          if (raw.isEmpty) return null;
          return parseFlexibleDateToIsoDate(raw) ?? raw;
        }(),
        'note': (s['note'] ?? '').toString().trim().isEmpty ? null : (s['note'] ?? '').toString().trim(),
      };
      final sid = (s['id_uuid'] ?? '').toString().trim();
      if (sid.isEmpty) {
        await _supa.from('logistica_attrezzature_assegnatari_storico').insert(payload);
      } else {
        await _supa.from('logistica_attrezzature_assegnatari_storico').update(payload).eq('id_uuid', sid);
      }
    }
  }

  Future<void> _fillPosizioneFromGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS disattivato: attiva la posizione sul dispositivo.')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso posizione negato.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final lat = pos.latitude.toStringAsFixed(6);
      final lon = pos.longitude.toStringAsFixed(6);
      setState(() => posizioneCtrl.text = 'GPS: $lat, $lon');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore acquisizione GPS: $e')),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openGpsOnMap() async {
    final coords = _extractCoords(posizioneCtrl.text);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna coordinata GPS valida in Posizione.')),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final commessaItems = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuova attrezzatura' : 'Modifica attrezzatura'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: codiceCtrl, decoration: const InputDecoration(labelText: 'Codice Cronos', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: assegnatarioCtrl, decoration: const InputDecoration(labelText: 'Assegnatario', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                controller: dataAssegnazioneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data assegnazione (gg/mm/aaaa)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: famigliaCtrl, decoration: const InputDecoration(labelText: 'Famiglia attrezzi', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: marcaCtrl, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: descrizioneCtrl, decoration: const InputDecoration(labelText: 'Descrizione articolo', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial number', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: modelloCtrl, decoration: const InputDecoration(labelText: 'Modello', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: odaCtrl, decoration: const InputDecoration(labelText: 'ODA', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: dataOdaCtrl, decoration: const InputDecoration(labelText: 'Data ODA', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: posizioneCtrl,
                      decoration: const InputDecoration(labelText: 'Posizione', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _gpsLoading ? null : _fillPosizioneFromGps,
                      icon: _gpsLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: const Text('GPS'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _extractCoords(posizioneCtrl.text) == null ? null : _openGpsOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Maps'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(controller: ddtCtrl, decoration: const InputDecoration(labelText: 'DDT', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                controller: dataUltimaTaraturaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data ultima taratura (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dataProssimaTaraturaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data prossima taratura (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: noteCtrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Autocomplete<MapEntry<String, String>>(
                initialValue: TextEditingValue(text: commessaSearchCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return commessaItems;
                  return commessaItems.where((e) => e.value.toLowerCase().contains(q));
                },
                displayStringForOption: (opt) => opt.value,
                onSelected: (opt) {
                  setState(() {
                    commessaSel = opt.key;
                    commessaSearchCtrl.text = opt.value;
                  });
                },
                fieldViewBuilder: (context, textCtrl, focusNode, _) {
                  if (textCtrl.text != commessaSearchCtrl.text) textCtrl.text = commessaSearchCtrl.text;
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Commessa (scrivi e seleziona)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Azzera commessa',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          textCtrl.clear();
                          commessaSearchCtrl.clear();
                          setState(() => commessaSel = null);
                        },
                      ),
                    ),
                    onChanged: (v) {
                      commessaSearchCtrl.text = v;
                      final exact = commessaItems.where((e) => e.value == v).toList(growable: false);
                      setState(() => commessaSel = exact.isNotEmpty ? exact.first.key : null);
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildStoricoSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
        AsyncFilledButton(onPressed: _save, child: const Text('Salva')),
      ],
    );
  }

  Widget _buildStoricoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Storico assegnatari precedenti',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editStoricoEntry(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Aggiungi'),
            ),
          ],
        ),
        if (_storicoLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (_storico.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Nessun assegnatario precedente.', style: TextStyle(color: Colors.grey)),
          )
        else
          ..._storico.asMap().entries.map((e) {
            final idx = e.key;
            final s = e.value;
            final ass = (s['assegnatario'] ?? '').toString();
            final dal = formatDateDdMmYyyy(s['data_assegnazione']);
            final al = formatDateDdMmYyyy(s['data_fine']);
            final note = (s['note'] ?? '').toString();
            final periodo = [
              if (dal.isNotEmpty) 'dal $dal',
              if (al.isNotEmpty) 'al $al',
            ].join(' ');
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(ass.isEmpty ? '—' : ass, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (periodo.isNotEmpty) periodo,
                  if (note.isNotEmpty) note,
                ].join('\n')),
                isThreeLine: note.isNotEmpty && periodo.isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Modifica',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editStoricoEntry(index: idx),
                    ),
                    IconButton(
                      tooltip: 'Elimina',
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      onPressed: () {
                        final sid = (s['id_uuid'] ?? '').toString().trim();
                        if (sid.isNotEmpty) _storicoDeletedIds.add(sid);
                        setState(() => _storico.removeAt(idx));
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _editStoricoEntry({int? index}) async {
    final existing = index == null ? null : _storico[index];
    final assCtrl = TextEditingController(text: (existing?['assegnatario'] ?? '').toString());
    final dalCtrl = TextEditingController(text: formatDateDdMmYyyy(existing?['data_assegnazione']));
    final alCtrl = TextEditingController(text: formatDateDdMmYyyy(existing?['data_fine']));
    final noteCtrlLocal = TextEditingController(text: (existing?['note'] ?? '').toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Nuovo assegnatario precedente' : 'Modifica assegnatario precedente'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: assCtrl, decoration: const InputDecoration(labelText: 'Assegnatario', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(controller: dalCtrl, decoration: const InputDecoration(labelText: 'Data inizio (gg/mm/aaaa)', border: OutlineInputBorder(), isDense: true)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(controller: alCtrl, decoration: const InputDecoration(labelText: 'Data fine (gg/mm/aaaa)', border: OutlineInputBorder(), isDense: true)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: noteCtrlLocal, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (saved == true) {
      final entry = <String, dynamic>{
        if (existing?['id_uuid'] != null) 'id_uuid': existing!['id_uuid'],
        'assegnatario': assCtrl.text.trim(),
        'data_assegnazione': dalCtrl.text.trim(),
        'data_fine': alCtrl.text.trim(),
        'note': noteCtrlLocal.text.trim(),
      };
      setState(() {
        if (index == null) {
          _storico.insert(0, entry);
        } else {
          _storico[index] = entry;
        }
      });
    }
    assCtrl.dispose();
    dalCtrl.dispose();
    alCtrl.dispose();
    noteCtrlLocal.dispose();
  }
}
