import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deadline_nav_highlight.dart';
import '../services/logistica_box_linked_sync.dart';
import '../utils/date_formatters.dart';
import '../utils/dt_user_list.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/logistica_layout.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../services/notification_sender.dart';
import '../services/notification_routing_rules_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class AdminLogisticaMdoFerroviariPage extends StatefulWidget {
  final bool dipendenteMode;
  final bool forceMobileLayout;
  const AdminLogisticaMdoFerroviariPage({
    super.key,
    this.dipendenteMode = false,
    this.forceMobileLayout = false,
  });

  @override
  State<AdminLogisticaMdoFerroviariPage> createState() => _AdminLogisticaMdoFerroviariPageState();
}

class _AdminLogisticaMdoFerroviariPageState extends State<AdminLogisticaMdoFerroviariPage>
    with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  final ScrollController _desktopHorizontalCtrl = ScrollController();
  final ScrollController _desktopVerticalCtrl = ScrollController();
  bool _loading = true;
  bool _compactView = true;
  String _currentRole = '';
  String _search = '';
  int _loadRowsRequestId = 0;
  List<Map<String, dynamic>> _rows = [];
  final List<String> _commessaOptions = <String>[];
  final Map<String, String> _usersByUuid = {};
  final Set<String> _pendingCheckIds = <String>{};
  final Set<String> _expandedMobileRowIds = <String>{};
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();
  bool _blinkOn = true;
  Timer? _blinkTimer;
  Timer? _searchDebounce;
  static const List<Map<String, String>> _dotazioni = [
    {'key': 'dispositivo_shuntaggio_check', 'label': 'Dispositivo shuntaggio'},
    {'key': 'lanterna_bilux_check', 'label': 'Lanterna visita/segnalamento bilux'},
    {'key': 'fanali_coda_check', 'label': 'Fanali di coda'},
    {'key': 'tabella_coda_check', 'label': 'Tabella di coda'},
    {'key': 'torcia_fiamma_rossa_check', 'label': 'Torcia segnalamento fiamma rossa'},
    {'key': 'bandiera_rossa_asta_check', 'label': 'Bandiera rossa con asta'},
    {'key': 'scarpe_fermacarro_check', 'label': 'Scarpe fermacarro'},
    {'key': 'chiave_tripla_snodata_check', 'label': 'Chiave tripla snodata'},
    {'key': 'barra_traino_check', 'label': 'Barra di traino'},
    {'key': 'vaschetta_raccolta_liquidi_check', 'label': 'Vaschetta raccolta liquidi'},
    {'key': 'doc_carte_circolazione_check', 'label': 'DOC: Carte di circolazione'},
    {'key': 'doc_manuale_uso_manutenzione_check', 'label': 'DOC: Manuale uso e manutenzione'},
    {'key': 'doc_libro_bordo_check', 'label': 'DOC: Libro di bordo'},
    {'key': 'doc_diario_manutenzione_check', 'label': 'DOC: Diario manutenzione'},
    {'key': 'doc_verifica_annuale_check', 'label': 'DOC: Verifica Annuale'},
    {'key': 'doc_allegato_p_check', 'label': 'DOC: Allegato P'},
  ];

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _loadCommesseOptions();
    _loadCurrentRole();
    _loadRows();
  }

  Future<void> _loadCurrentRole() async {
    try {
      final authId = _supa.auth.currentUser?.id;
      if ((authId ?? '').trim().isEmpty) return;
      final me = await _supa.from('users').select('role').eq('auth_id', authId!).maybeSingle();
      final role = (me?['role'] ?? '').toString().trim().toLowerCase();
      if (!mounted) return;
      setState(() => _currentRole = role);
    } catch (_) {
      // Non bloccare la pagina se il ruolo non e' risolvibile.
    }
  }

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
      _expandedMobileRowIds.add(trimmed);
      pinRowByUuidToFront(_rows, trimmed);
    });
    if (_desktopVerticalCtrl.hasClients) {
      _desktopVerticalCtrl.jumpTo(0);
    }
    scheduleDeadlineScrollToAnchor(
      _deadlineScrollAnchorKey,
      onDone: () {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _deadlineScrollUuid = null);
        });
      },
    );
  }

  @override
  void dispose() {
    disposeDeadlineFlash();
    _blinkTimer?.cancel();
    _searchDebounce?.cancel();
    _desktopHorizontalCtrl.dispose();
    _desktopVerticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommesseOptions() async {
    try {
      final res = await _supa.from('commesse').select('nome').order('nome');
      final options = <String>{};
      for (final row in (res as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final nome = (m['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) options.add(nome);
      }
      if (!mounted) return;
      setState(() {
        _commessaOptions
          ..clear()
          ..addAll(options.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
      });
    } catch (_) {
      // Non bloccare la pagina se il caricamento commesse fallisce.
    }
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    final requestId = ++_loadRowsRequestId;
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      final res = await _supa
          .from('logistica_mdo_ferroviari')
          .select()
          .order('matricola_interna', ascending: true);
      var list = List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
      if (_search.trim().isNotEmpty) {
        final k = _search.toLowerCase().trim();
        list = list.where((r) {
          final tokens = [
            r['matricola_interna'],
            r['codice_identificativo_targa_rfi'],
            r['descrizione_mezzo'],
            r['descrizione_rumo'],
            r['modello'],
            r['equipment'],
            r['matricola_costruttore'],
            r['cantiere_attuale'],
            r['commessa'],
            r['dt_nome'],
            r['scadenza_va'],
            r['scadenza_cpo'],
            r['scadenza_vqq'],
            r['scadenza_terrazzino'],
            r['scadenza_gru'],
            r['scadenza_cestello'],
          ].map((v) => (v ?? '').toString().toLowerCase());
          return tokens.any((t) => t.contains(k));
        }).toList(growable: false);
      }

      final ids = <String>{};
      for (final r in list) {
        final c = (r['created_by_user_uuid'] ?? '').toString().trim();
        final u = (r['updated_by_user_uuid'] ?? '').toString().trim();
        final gc = (r['check_confermato_by_user_uuid'] ?? '').toString().trim();
        if (c.isNotEmpty) ids.add(c);
        if (u.isNotEmpty) ids.add(u);
        if (gc.isNotEmpty) ids.add(gc);
        for (final d in _dotazioni) {
          final by = (r['${d['key']!.replaceAll('_check', '')}_checked_by_user_uuid'] ?? '').toString().trim();
          if (by.isNotEmpty) ids.add(by);
          final reqBy = (r['${d['key']!.replaceAll('_check', '')}_richiesta_sostituzione_by_user_uuid'] ?? '')
              .toString()
              .trim();
          if (reqBy.isNotEmpty) ids.add(reqBy);
        }
        mergeFieldTimestampActorUuids(r, ids);
      }
      final map = <String, String>{};
      if (ids.isNotEmpty) {
        final users = await _supa.from('users').select('id_uuid,full_name,username').inFilter('id_uuid', ids.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          if (id.isNotEmpty) map[id] = full.isNotEmpty ? full : user;
        }
      }

      if (!mounted || requestId != _loadRowsRequestId) return;
      setState(() {
        _rows = list;
        _usersByUuid
          ..clear()
          ..addAll(map);
      });
      maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
    } finally {
      if (showLoader && mounted && requestId == _loadRowsRequestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadRows(showLoader: false);
    });
  }

  Future<void> _exportExcel() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun dato da esportare')),
        );
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['MDO_Ferroviari'];
      final header = <String>[
        'Matricola interna',
        'Targa RFI',
        'Descrizione mezzo',
        'Descrizione RUMO',
        'Modello',
        'Equipment',
        'Matricola costruttore',
        'Cantiere attuale',
        'Commessa',
        'DT',
        'Scadenza VA',
        'Scadenza CPO',
        'Scadenza VQQ',
        'Scadenza Terrazzino',
        'Scadenza Gru',
        'Scadenza Cestello',
        'Posizione GPS',
        'Check generale',
        'Check dotazioni (eseguite/totali)',
        'Dotazioni presenti',
        'Dotazioni mancanti',
      ];
      for (final d in _dotazioni) {
        header.add('Dotazione - ${d['label']}');
      }
      sheet.appendRow(header);
      for (final r in _rows) {
        final checkedCount = _dotazioniCheckedCount(r);
        final dotazioniSummary = '$checkedCount/${_dotazioni.length}';
        final presenti = <String>[];
        final mancanti = <String>[];
        for (final d in _dotazioni) {
          final key = d['key'] ?? '';
          final label = (d['label'] ?? '').toString().trim();
          if (key.isEmpty || label.isEmpty) continue;
          final value = (r[key] ?? false) == true;
          if (value) {
            presenti.add(label);
          } else {
            mancanti.add(label);
          }
        }
        final row = <dynamic>[
          (r['matricola_interna'] ?? '').toString(),
          (r['codice_identificativo_targa_rfi'] ?? '').toString(),
          (r['descrizione_mezzo'] ?? '').toString(),
          (r['descrizione_rumo'] ?? '').toString(),
          (r['modello'] ?? '').toString(),
          (r['equipment'] ?? '').toString(),
          (r['matricola_costruttore'] ?? '').toString(),
          (r['cantiere_attuale'] ?? '').toString(),
          (r['commessa'] ?? '').toString(),
          (r['dt_nome'] ?? '').toString(),
          _fmtDateOnly(r['scadenza_va']),
          _fmtDateOnly(r['scadenza_cpo']),
          _fmtDateOnly(r['scadenza_vqq']),
          _fmtDateOnly(r['scadenza_terrazzino']),
          _fmtDateOnly(r['scadenza_gru']),
          _fmtDateOnly(r['scadenza_cestello']),
          (r['posizione_gps'] ?? '').toString(),
          (r['check_eseguito'] ?? false) == true ? 'SI' : 'NO',
          dotazioniSummary,
          presenti.join(', '),
          mancanti.join(', '),
        ];
        for (final d in _dotazioni) {
          final key = d['key'] ?? '';
          final value = key.isEmpty ? false : (r[key] ?? false) == true;
          row.add(value ? 'SI' : 'NO');
        }
        sheet.appendRow(row);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'MDO_Ferroviari',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Excel completato: $p')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore export Excel: $e')),
      );
    }
  }

  String _fmtDateTime(dynamic v) {
    final s = formatDateTimeItFromSupabase(v);
    if (s.isNotEmpty) return s;
    if (v == null) return '';
    return v.toString();
  }

  String _fmtDateOnly(dynamic v) {
    if (v == null) return '';
    if (v is DateTime) return formatDateDdMmYyyy(v.toLocal());
    final dt = DateTime.tryParse(v.toString());
    if (dt != null) return formatDateDdMmYyyy(dt.toLocal());
    return v.toString();
  }

  TextStyle? _expiryStyle(dynamic v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    final today = DateTime.now();
    final date = DateTime(dt.year, dt.month, dt.day);
    final ref = DateTime(today.year, today.month, today.day);
    final days = date.difference(ref).inDays;
    if (days < 0) {
      return TextStyle(
        color: _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.3),
        fontWeight: FontWeight.w700,
      );
    }
    if (days <= 30) {
      return const TextStyle(
        color: Colors.orange,
        fontWeight: FontWeight.w700,
      );
    }
    return null;
  }

  Widget _expiryText(dynamic v) {
    final label = _fmtDateOnly(v);
    return Text(label.isEmpty ? '—' : label, style: _expiryStyle(v));
  }

  DataCell _auditCell(DataCell cell, Map<String, dynamic> row, String fieldKey) {
    return decorateDataCellWithFieldAudit(
      cell,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _usersByUuid,
      rowAuditWhenFieldMissing: false,
      copyOnDoubleTapText: _fieldCopyText(row, fieldKey),
      onTextCopied: (_) => _toastCopied(),
    );
  }

  String? _fieldCopyText(Map<String, dynamic> row, String fieldKey) {
    if (fieldKey == 'check_eseguito') return null;
    if (fieldKey.startsWith('scadenza_')) {
      final label = _fmtDateOnly(row[fieldKey]);
      if (label.isEmpty || label == '—') return null;
      return label;
    }
    if (fieldKey == 'dotazioni_checks') {
      final checkedCount = _dotazioniCheckedCount(row);
      final reqCount = _dotazioniRequestedCount(row);
      return '$checkedCount/${_dotazioni.length}'
          '${reqCount > 0 ? '  |  R:$reqCount' : ''}';
    }
    final raw = (row[fieldKey] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  void _toastCopied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiato negli appunti'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _currentUserIdUuid() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return null;
    try {
      final me = await _supa.from('users').select('id_uuid').eq('auth_id', authId!).maybeSingle();
      final idUuid = (me?['id_uuid'] ?? '').toString().trim();
      return idUuid.isEmpty ? authId : idUuid;
    } catch (_) {
      return authId;
    }
  }

  int _notificationBookingId(Map<String, dynamic> row) {
    final direct = row['id'];
    if (direct is int && direct > 0) return direct;
    final parsed = int.tryParse((direct ?? '').toString().trim());
    if ((parsed ?? 0) > 0) return parsed!;
    final uuid = (row['id_uuid'] ?? '').toString().toLowerCase().replaceAll('-', '');
    if (uuid.length >= 8) {
      final hex = uuid.substring(0, 8);
      final v = int.tryParse(hex, radix: 16);
      if ((v ?? 0) > 0) return v!;
    }
    return DateTime.now().millisecondsSinceEpoch.remainder(2000000000) + 1;
  }

  int _dotazioniCheckedCount(Map<String, dynamic> row) {
    var c = 0;
    for (final d in _dotazioni) {
      if ((row[d['key']] ?? false) == true) c++;
    }
    return c;
  }

  int _dotazioniRequestedCount(Map<String, dynamic> row) {
    var c = 0;
    for (final d in _dotazioni) {
      final key = d['key'] ?? '';
      if (key.isEmpty) continue;
      if ((row[_dotazioneReqKey(key)] ?? false) == true) c++;
    }
    return c;
  }

  String _dotazioneReqKey(String key) => key.replaceAll('_check', '_richiesta_sostituzione');
  String _dotazioneReqByCol(String key) {
    if (key == 'doc_manuale_uso_manutenzione_check') {
      // PostgreSQL limita gli identificatori a 63 caratteri: il nome e' troncato lato DB.
      return 'doc_manuale_uso_manutenzione_richiesta_sostituzione_by_user_uui';
    }
    return key.replaceAll('_check', '_richiesta_sostituzione_by_user_uuid');
  }
  String _dotazioneReqAtCol(String key) => key.replaceAll('_check', '_richiesta_sostituzione_at');

  Future<void> _notifyAdminGeneraleForDotazioniRequest(
    Map<String, dynamic> row,
    List<String> labels,
  ) async {
    if (labels.isEmpty) return;
    final admins = await _supa
        .from('users')
        .select('id, role')
        .eq('role', 'logistica');
    final ids = (admins as List)
        .map((e) => (Map<String, dynamic>.from(e as Map)['id']))
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    final code = (row['matricola_interna'] ?? row['codice_identificativo_targa_rfi'] ?? 'N/D').toString();
    final bid = _notificationBookingId(row);
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: bid,
      action: 'mdo_dotazioni_replacement_request',
      title: 'Richiesta integrazione/sostituzione dotazioni MDO',
      message: 'MDO $code: ${labels.join(', ')}',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<List<int>> _logisticaCheckRecipientIds(String ruleKey) async {
    final rules = await NotificationRoutingRulesService.listRules();
    final rule = rules.firstWhere(
      (r) => (r['rule_key'] ?? '').toString() == ruleKey,
      orElse: () => const <String, dynamic>{},
    );
    final enabled = rule['enabled'] == true;
    if (!enabled) return const <int>[];
    final targets = ((rule['targets'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString().trim())
        .where((e) => e.startsWith('role:'))
        .map((e) => e.replaceFirst('role:', ''))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (targets.isEmpty) return const <int>[];

    final users = await _supa
        .from('users')
        .select('id,role')
        .inFilter('role', targets);
    return (users as List)
        .map((e) => (Map<String, dynamic>.from(e as Map)['id']))
        .whereType<int>()
        .toSet()
        .toList(growable: false);
  }

  Future<void> _notifyRolesForMdoGeneralCheck(Map<String, dynamic> row) async {
    final ids = await _logisticaCheckRecipientIds('logistica_mdo_general_check_completed_notify');
    if (ids.isEmpty) return;
    final code = (row['matricola_interna'] ?? row['codice_identificativo_targa_rfi'] ?? 'N/D').toString();
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: _notificationBookingId(row),
      action: 'logistica_mdo_general_check_completed',
      title: 'Check logistica MDO confermato',
      message: 'Check generale confermato per MDO $code',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<void> _notifyRolesForMdoDotazioniChecks(
    Map<String, dynamic> row,
    List<String> checkedLabels,
  ) async {
    if (checkedLabels.isEmpty) return;
    final ids = await _logisticaCheckRecipientIds('logistica_mdo_dotazioni_check_completed_notify');
    if (ids.isEmpty) return;
    final code = (row['matricola_interna'] ?? row['codice_identificativo_targa_rfi'] ?? 'N/D').toString();
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: _notificationBookingId(row),
      action: 'logistica_mdo_dotazioni_check_completed',
      title: 'Check dotazioni MDO confermato',
      message: 'MDO $code - dotazioni: ${checkedLabels.join(', ')}',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<void> _saveDotazioniSelection(
    Map<String, dynamic> row,
    Map<String, bool> selectedByKey,
    Map<String, bool> requestByKey,
  ) async {
    if (!await ensureCanPersist(context)) return;
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final byUuid = await _currentUserIdUuid();
    final payload = <String, dynamic>{};
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final openedRequestLabels = <String>[];
    final checkedNowLabels = <String>[];
    for (final d in _dotazioni) {
      final key = d['key'] ?? '';
      if (key.isEmpty || !selectedByKey.containsKey(key)) continue;
      final prev = (row[key] ?? false) == true;
      final next = selectedByKey[key] == true;
      if (prev != next) {
        final byCol = key.replaceAll('_check', '_checked_by_user_uuid');
        final atCol = key.replaceAll('_check', '_checked_at');
        payload[key] = next;
        payload[byCol] = next ? byUuid : null;
        payload[atCol] = next ? nowIso : null;
        if (!prev && next) {
          final label = (d['label'] ?? '').trim();
          if (label.isNotEmpty) checkedNowLabels.add(label);
        }
      }

      final reqKey = _dotazioneReqKey(key);
      final reqByCol = _dotazioneReqByCol(key);
      final reqAtCol = _dotazioneReqAtCol(key);
      final reqPrev = (row[reqKey] ?? false) == true;
      final reqNext = requestByKey[key] == true;
      if (reqPrev != reqNext) {
        payload[reqKey] = reqNext;
        payload[reqByCol] = reqNext ? byUuid : null;
        payload[reqAtCol] = reqNext ? nowIso : null;
        if (!reqPrev && reqNext) {
          final label = (d['label'] ?? '').trim();
          if (label.isNotEmpty) openedRequestLabels.add(label);
        }
      }
    }
    if (payload.isEmpty) return;
    await _supa.from('logistica_mdo_ferroviari').update(payload).eq('id_uuid', id);
    if (openedRequestLabels.isNotEmpty) {
      try {
        await _notifyAdminGeneraleForDotazioniRequest(row, openedRequestLabels);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifica inviata a logistica.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Richiesta salvata, ma notifica logistica non inviata.'),
            ),
          );
        }
      }
    }
    if (checkedNowLabels.isNotEmpty) {
      try {
        await _notifyRolesForMdoDotazioniChecks(row, checkedNowLabels);
      } catch (_) {
        // Non bloccare il salvataggio in caso di errore notifica.
      }
    }
    await _loadRows();
  }

  Future<void> _captureGpsForRow(String id) async {
    if (id.isEmpty) return;
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
    await _supa.from('logistica_mdo_ferroviari').update({
      'posizione_gps': 'GPS: $lat, $lon',
      'latitudine': pos.latitude,
      'longitudine': pos.longitude,
    }).eq('id_uuid', id);
    await propagateMdoUpdateById(_supa, id);
    await _loadRows();
  }

  Future<void> _updateCommessaForRow(Map<String, dynamic> row) async {
    if (!await ensureCanPersist(context)) return;
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: (row['commessa'] ?? '').toString());
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Aggiorna commessa'),
          content: SizedBox(
            width: 420,
            child: Autocomplete<String>(
              initialValue: TextEditingValue(text: ctrl.text),
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return _commessaOptions;
                return _commessaOptions.where((e) => e.toLowerCase().contains(q));
              },
              onSelected: (v) => ctrl.text = v,
              fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
                if (textCtrl.text != ctrl.text) textCtrl.text = ctrl.text;
                return TextField(
                  controller: textCtrl,
                  focusNode: focusNode,
                  onChanged: (v) => ctrl.text = v,
                  decoration: const InputDecoration(
                    labelText: 'Commessa',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Salva'),
            ),
          ],
        );
      },
    );
    if (saved == null) return;
    await _supa.from('logistica_mdo_ferroviari').update({
      'commessa': saved.isEmpty ? null : saved,
    }).eq('id_uuid', id);
    await propagateMdoUpdateById(_supa, id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Commessa aggiornata.')),
    );
    await _loadRows();
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

  Future<void> _openCoordsOnMap(Map<String, dynamic> row) async {
    final latRaw = row['latitudine'];
    final lonRaw = row['longitudine'];
    final lat = latRaw is num ? latRaw.toDouble() : null;
    final lon = lonRaw is num ? lonRaw.toDouble() : null;
    final coords = (lat != null && lon != null)
        ? (lat, lon)
        : _extractCoords((row['posizione_gps'] ?? '').toString());
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna coordinata GPS valida.')),
      );
      return;
    }
    final (mapLat, mapLon) = coords;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$mapLat,$mapLon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _checkColor(Map<String, dynamic> row) {
    final checked = (row['check_eseguito'] ?? false) == true;
    if (!checked) return Colors.grey;
    final raw = (row['check_confermato_at'] ?? '').toString().trim();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return Colors.grey;
    final days = DateTime.now().toUtc().difference(dt.toUtc()).inDays;
    return days <= 60 ? Colors.green : Colors.grey;
  }

  Future<void> _confirmGeneralCheck(String id) async {
    if (id.isEmpty || _pendingCheckIds.contains(id)) return;
    setState(() => _pendingCheckIds.add(id));
    try {
      final byUuid = await _currentUserIdUuid();
      await _supa.from('logistica_mdo_ferroviari').update({
        'check_eseguito': true,
        'check_confermato_by_user_uuid': byUuid,
        'check_confermato_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id_uuid', id);
      try {
        Map<String, dynamic>? row;
        for (final r in _rows) {
          if ((r['id_uuid'] ?? '').toString().trim() == id) {
            row = r;
            break;
          }
        }
        if (row != null) {
          await _notifyRolesForMdoGeneralCheck(row);
        }
      } catch (_) {
        // Non bloccare il check in caso di errore notifica.
      }
      await _loadRows();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check generale registrato.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingCheckIds.remove(id));
    }
  }

  Future<void> _removeGeneralCheck(String id) async {
    if (id.isEmpty || _pendingCheckIds.contains(id)) return;
    setState(() => _pendingCheckIds.add(id));
    try {
      await _supa.from('logistica_mdo_ferroviari').update({
        'check_eseguito': false,
        'check_confermato_by_user_uuid': null,
        'check_confermato_at': null,
      }).eq('id_uuid', id);
      await _loadRows();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check generale rimosso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingCheckIds.remove(id));
    }
  }

  void _toggleGeneralCheck(String id, Map<String, dynamic> row) {
    if (id.isEmpty || _pendingCheckIds.contains(id)) return;
    final checked = (row['check_eseguito'] ?? false) == true;
    if (checked) {
      _removeGeneralCheck(id);
    } else {
      _confirmGeneralCheck(id);
    }
  }

  void _showGeneralCheckAudit(Map<String, dynamic> row) {
    final byUuid = (row['check_confermato_by_user_uuid'] ?? '').toString().trim();
    final byName = _usersByUuid[byUuid] ?? byUuid;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tracciabilita - Check generale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Check: ${(row['check_eseguito'] ?? false) == true ? 'SI' : 'NO'}'),
            Text('Confermato da: ${byName.isEmpty ? '—' : byName}'),
            Text(
              'Confermato il: ${_fmtDateTime(row['check_confermato_at']).isEmpty ? '—' : _fmtDateTime(row['check_confermato_at'])}',
            ),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  void _showDotazioneAudit(Map<String, dynamic> row, String key, String label) {
    final byCol = key.replaceAll('_check', '_checked_by_user_uuid');
    final atCol = key.replaceAll('_check', '_checked_at');
    final reqKey = _dotazioneReqKey(key);
    final reqByCol = _dotazioneReqByCol(key);
    final reqAtCol = _dotazioneReqAtCol(key);
    final byUuid = (row[byCol] ?? '').toString().trim();
    final reqByUuid = (row[reqByCol] ?? '').toString().trim();
    final byName = _usersByUuid[byUuid] ?? byUuid;
    final reqByName = _usersByUuid[reqByUuid] ?? reqByUuid;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tracciabilita - $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Check: ${(row[key] ?? false) == true ? 'SI' : 'NO'}'),
            Text('Confermato da: ${byName.isEmpty ? '—' : byName}'),
            Text('Confermato il: ${_fmtDateTime(row[atCol]).isEmpty ? '—' : _fmtDateTime(row[atCol])}'),
            const SizedBox(height: 8),
            Text('Richiesta sostituzione: ${(row[reqKey] ?? false) == true ? 'SI' : 'NO'}'),
            Text('Richiesta da: ${reqByName.isEmpty ? '—' : reqByName}'),
            Text('Richiesta il: ${_fmtDateTime(row[reqAtCol]).isEmpty ? '—' : _fmtDateTime(row[reqAtCol])}'),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Widget _dotazionePresenteChip({
    required bool checked,
    required bool saving,
    required VoidCallback onSelect,
  }) {
    return ChoiceChip(
      label: const Text('Presente'),
      avatar: const Icon(Icons.check_circle_outline, size: 16),
      selected: checked,
      selectedColor: Colors.green.withValues(alpha: 0.18),
      side: BorderSide(color: checked ? Colors.green : Colors.grey.shade400),
      labelStyle: TextStyle(
        color: checked ? Colors.green.shade800 : Colors.grey.shade700,
        fontWeight: FontWeight.w700,
      ),
      onSelected: saving ? null : (_) => onSelect(),
    );
  }

  Widget _dotazioneAssenteChip({
    required bool checked,
    required bool saving,
    required VoidCallback onSelect,
  }) {
    return ChoiceChip(
      label: const Text('Assente'),
      avatar: const Icon(Icons.cancel_outlined, size: 16),
      selected: !checked,
      selectedColor: Colors.red.withValues(alpha: 0.16),
      side: BorderSide(color: !checked ? Colors.red : Colors.grey.shade400),
      labelStyle: TextStyle(
        color: !checked ? Colors.red.shade800 : Colors.grey.shade700,
        fontWeight: FontWeight.w700,
      ),
      onSelected: saving ? null : (_) => onSelect(),
    );
  }

  Widget _buildDotazioneDialogRow({
    required BuildContext context,
    required ThemeData theme,
    required Map<String, dynamic> row,
    required String key,
    required String label,
    required bool checked,
    required bool requestActive,
    required bool saving,
    required bool compact,
    required VoidCallback onPresente,
    required VoidCallback onAssente,
    required VoidCallback onToggleRequest,
  }) {
    final chips = Row(
      children: [
        Expanded(
          child: _dotazionePresenteChip(
            checked: checked,
            saving: saving,
            onSelect: onPresente,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dotazioneAssenteChip(
            checked: checked,
            saving: saving,
            onSelect: onAssente,
          ),
        ),
      ],
    );

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: requestActive
              ? 'Rimuovi richiesta sostituzione'
              : 'Richiedi integrazione/sostituzione',
          onPressed: saving ? null : onToggleRequest,
          icon: Icon(
            requestActive ? Icons.notifications_active : Icons.notifications_none,
            color: requestActive
                ? (_blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.25))
                : Colors.grey,
          ),
        ),
        IconButton(
          tooltip: 'Audit',
          onPressed: () => _showDotazioneAudit(row, key, label),
          icon: const Icon(Icons.info_outline),
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            chips,
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: chips),
          trailing,
        ],
      ),
    );
  }

  Future<void> _openDotazioniDialog(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final selectedByKey = <String, bool>{
            for (final d in _dotazioni) d['key']!: (row[d['key']] ?? false) == true,
          };
          final requestByKey = <String, bool>{
            for (final d in _dotazioni)
              d['key']!: (row[_dotazioneReqKey(d['key']!)] ?? false) == true,
          };
          var saving = false;
          return StatefulBuilder(
            builder: (innerCtx, setInner) {
              final screenW = MediaQuery.sizeOf(innerCtx).width;
              final compact = screenW < 520;
              final theme = Theme.of(innerCtx);
              final dialogW = compact ? screenW * 0.92 : 560.0;

              return AlertDialog(
                insetPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 24,
                  vertical: 24,
                ),
                title: const Text('Check dotazioni bordo'),
                content: SizedBox(
                  width: dialogW,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _dotazioni.map((d) {
                        final key = d['key']!;
                        final label = d['label']!;
                        final checked = selectedByKey[key] == true;
                        return _buildDotazioneDialogRow(
                          context: innerCtx,
                          theme: theme,
                          row: row,
                          key: key,
                          label: label,
                          checked: checked,
                          requestActive: requestByKey[key] == true,
                          saving: saving,
                          compact: compact,
                          onPresente: () {
                            selectedByKey[key] = true;
                            setInner(() {});
                          },
                          onAssente: () {
                            selectedByKey[key] = false;
                            setInner(() {});
                          },
                          onToggleRequest: () {
                            requestByKey[key] = !(requestByKey[key] == true);
                            setInner(() {});
                          },
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(innerCtx),
                    child: const Text('Annulla'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setInner(() => saving = true);
                            await _saveDotazioniSelection(
                              row,
                              selectedByKey,
                              requestByKey,
                            );
                            if (ctx.mounted) Navigator.pop(innerCtx);
                          },
                    child: const Text('Salva'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MdoDialog(row: row),
    );
    if (ok == true) {
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(row == null ? 'Record salvato.' : 'Record aggiornato.')),
      );
    }
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina MDO'),
        content: const Text('Confermi eliminazione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('logistica_mdo_ferroviari').delete().eq('id_uuid', id);
    await _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout =
        isLogisticaCompactLayout(context, force: widget.forceMobileLayout);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Lista MDO'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          if (!widget.dipendenteMode)
            IconButton(
              tooltip: 'Nuovo',
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
            ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _loadRows,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : isMobileLayout
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        child: SizedBox(
                          width: logisticaFieldWidth(context, desktop: 360),
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Cerca matricola, mezzo, commessa...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final r = _rows[index];
                            final id = (r['id_uuid'] ?? '').toString();
                            final rowKey = id.isEmpty ? 'row_$index' : id;
                            final detailsExpanded = _expandedMobileRowIds.contains(rowKey);
                            final canDelete = !widget.dipendenteMode && _currentRole == 'logistica';
                            final flash = id.isNotEmpty && deadlineFlashLit(id);
                            return KeyedSubtree(
                              key: _deadlineUuidAnchorsMatch(id)
                                  ? _deadlineScrollAnchorKey
                                  : ValueKey<String>('mdo_mobile_$rowKey'),
                              child: Card(
                              margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: flash ? Colors.amber : Colors.transparent,
                                  width: flash ? 3 : 0,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text((r['matricola_interna'] ?? '').toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text('Targa RFI: ${(r['codice_identificativo_targa_rfi'] ?? '').toString()}'),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 0),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        minimumSize: const Size(0, 32),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (detailsExpanded) {
                                            _expandedMobileRowIds.remove(rowKey);
                                          } else {
                                            _expandedMobileRowIds.add(rowKey);
                                          }
                                        });
                                      },
                                      icon: Icon(
                                        detailsExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                      ),
                                      label: Text(
                                        detailsExpanded
                                            ? 'Nascondi dettagli'
                                            : 'Mostra dettagli',
                                      ),
                                    ),
                                    if (detailsExpanded) ...[
                                      Text((r['descrizione_mezzo'] ?? '').toString(),
                                          maxLines: 2, overflow: TextOverflow.ellipsis),
                                      Text('RUMO: ${(r['descrizione_rumo'] ?? '').toString()}'),
                                      Text('Equipment: ${(r['equipment'] ?? '').toString()}'),
                                      Text('Matricola costr.: ${(r['matricola_costruttore'] ?? '').toString()}'),
                                      Text('Cantiere: ${(r['cantiere_attuale'] ?? '').toString()}'),
                                      Text('Commessa: ${(r['commessa'] ?? '').toString()}'),
                                      Text('DT: ${(r['dt_nome'] ?? '').toString()}'),
                                      Row(
                                        children: [
                                          const Text('Scadenza VA: '),
                                          _expiryText(r['scadenza_va']),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Text('Scadenza CPO: '),
                                          _expiryText(r['scadenza_cpo']),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Text('Scadenza VQQ: '),
                                          _expiryText(r['scadenza_vqq']),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Text('Scadenza terrazzino: '),
                                          _expiryText(r['scadenza_terrazzino']),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Text('Scadenza gru: '),
                                          _expiryText(r['scadenza_gru']),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Text('Scadenza cestello: '),
                                          _expiryText(r['scadenza_cestello']),
                                        ],
                                      ),
                                      Text('Posizione GPS: ${(r['posizione_gps'] ?? '').toString()}'),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Text('Check generale: '),
                                        InkWell(
                                          onTap: id.isEmpty || _pendingCheckIds.contains(id)
                                              ? null
                                              : () => _toggleGeneralCheck(id, r),
                                          onDoubleTap: id.isEmpty
                                              ? null
                                              : () => _showGeneralCheckAudit(r),
                                          child: Icon(
                                            (r['check_eseguito'] ?? false) == true
                                                ? Icons.check_box
                                                : Icons.check_box_outline_blank,
                                            color: _checkColor(r),
                                            size: 20,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Audit check generale',
                                          onPressed: () => _showGeneralCheckAudit(r),
                                          icon: const Icon(Icons.info_outline),
                                        ),
                                      ],
                                    ),
                                    Text('Check dotazioni: ${_dotazioniCheckedCount(r)}/${_dotazioni.length}'),
                                    Builder(
                                      builder: (_) {
                                        final reqCount = _dotazioniRequestedCount(r);
                                        if (reqCount <= 0) return const SizedBox.shrink();
                                        return Text(
                                          'Richieste sostituzione: $reqCount',
                                          style: TextStyle(
                                            color: _blinkOn
                                                ? Colors.red
                                                : Colors.red.withValues(alpha: 0.4),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: () => _openDotazioniDialog(r),
                                          icon: const Icon(Icons.checklist_outlined, size: 18),
                                          label: const Text('Dotazioni'),
                                        ),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: () => _updateCommessaForRow(r),
                                          icon: const Icon(Icons.business_outlined, size: 18),
                                          label: const Text('Commessa'),
                                        ),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: id.isEmpty ? null : () => _captureGpsForRow(id),
                                          icon: const Icon(Icons.my_location, size: 18),
                                          label: const Text('Rileva GPS'),
                                        ),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: () => _openCoordsOnMap(r),
                                          icon: const Icon(Icons.map_outlined, size: 18),
                                          label: const Text('Apri mappa'),
                                        ),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: id.isEmpty || _pendingCheckIds.contains(id)
                                              ? null
                                              : () => _toggleGeneralCheck(id, r),
                                          icon: _pendingCheckIds.contains(id)
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : Icon(
                                                  (r['check_eseguito'] ?? false) == true
                                                      ? Icons.remove_done_outlined
                                                      : Icons.check_circle_outline,
                                                  size: 18,
                                                ),
                                          label: Text(
                                            (r['check_eseguito'] ?? false) == true
                                                ? 'Rimuovi check'
                                                : 'Registra check',
                                          ),
                                        ),
                                        if (!widget.dipendenteMode)
                                          FilledButton.tonalIcon(
                                            style: FilledButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                            onPressed: () => _openForm(row: r),
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            label: const Text('Modifica'),
                                          ),
                                        if (canDelete)
                                          FilledButton.tonalIcon(
                                            style: FilledButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                            onPressed: id.isEmpty ? null : () => _deleteRow(id),
                                            icon: const Icon(Icons.delete_outline, size: 18),
                                            label: const Text('Elimina'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 380,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Cerca matricola, mezzo, commessa...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 210,
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Compatta'),
                                icon: Icon(Icons.view_week_outlined, size: 16),
                              ),
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Completa'),
                                icon: Icon(Icons.table_rows_outlined, size: 16),
                              ),
                            ],
                            selected: <bool>{_compactView},
                            showSelectedIcon: false,
                            onSelectionChanged: (sel) {
                              if (sel.isEmpty) return;
                              setState(() => _compactView = sel.first);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DataTable2(
                          minWidth: _compactView ? 1700 : 2900,
                          fixedTopRows: 1,
                          fixedLeftColumns: 2,
                          scrollController: _desktopVerticalCtrl,
                          horizontalScrollController: _desktopHorizontalCtrl,
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: true,
                          columnSpacing: _compactView ? 4 : 8,
                          horizontalMargin: _compactView ? 6 : 12,
                          columns: [
                            DataColumn(label: Text('Matricola interna')),
                            DataColumn(label: Text('Targa RFI')),
                            DataColumn(label: Text('Descrizione mezzo')),
                            DataColumn(label: Text('Modello')),
                            if (!_compactView) DataColumn(label: Text('Descrizione RUMO')),
                            if (!_compactView) DataColumn(label: Text('Equipment')),
                            if (!_compactView) DataColumn(label: Text('Matricola costr.')),
                            DataColumn(label: Text('Cantiere attuale')),
                            DataColumn(label: Text('Commessa')),
                            if (!_compactView) DataColumn(label: Text('DT')),
                            if (!_compactView) DataColumn(label: Text('Scad. VA')),
                            if (!_compactView) DataColumn(label: Text('Scad. CPO')),
                            if (!_compactView) DataColumn(label: Text('Scad. VQQ')),
                            if (!_compactView) DataColumn(label: Text('Scad. Terrazzino')),
                            if (!_compactView) DataColumn(label: Text('Scad. Gru')),
                            if (!_compactView) DataColumn(label: Text('Scad. Cestello')),
                            if (!_compactView) DataColumn(label: Text('Posizione GPS')),
                            DataColumn(label: Text('Check generale')),
                            DataColumn(label: Text('Check dotazioni')),
                            DataColumn(label: Text('Azioni')),
                          ],
                          rows: _rows.map((r) {
                            final id = (r['id_uuid'] ?? '').toString();
                            final tooltipKeys = <String>[
                              'matricola_interna',
                              'codice_identificativo_targa_rfi',
                              'descrizione_mezzo',
                              'modello',
                              if (!_compactView) 'descrizione_rumo',
                              if (!_compactView) 'equipment',
                              if (!_compactView) 'matricola_costruttore',
                              'cantiere_attuale',
                              'commessa',
                              if (!_compactView) 'dt_nome',
                              if (!_compactView) 'scadenza_va',
                              if (!_compactView) 'scadenza_cpo',
                              if (!_compactView) 'scadenza_vqq',
                              if (!_compactView) 'scadenza_terrazzino',
                              if (!_compactView) 'scadenza_gru',
                              if (!_compactView) 'scadenza_cestello',
                              if (!_compactView) 'posizione_gps',
                              'check_eseguito',
                              'dotazioni_checks',
                              'updated_at',
                            ];
                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (_) => id.isNotEmpty && deadlineFlashLit(id)
                                    ? Colors.amber.withValues(alpha: 0.42)
                                    : null,
                              ),
                              cells: [
                              DataCell(
                                SizedBox(
                                  key: _deadlineUuidAnchorsMatch(id)
                                      ? _deadlineScrollAnchorKey
                                      : null,
                                  child: Text((r['matricola_interna'] ?? '').toString()),
                                ),
                              ),
                              DataCell(Text((r['codice_identificativo_targa_rfi'] ?? '').toString())),
                              DataCell(
                                SizedBox(
                                  width: _compactView ? 150 : 200,
                                  child: Text(
                                    (r['descrizione_mezzo'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text((r['modello'] ?? '').toString())),
                              if (!_compactView)
                                DataCell(
                                  SizedBox(
                                    width: 170,
                                    child: Text(
                                      (r['descrizione_rumo'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              if (!_compactView) DataCell(Text((r['equipment'] ?? '').toString())),
                              if (!_compactView) DataCell(Text((r['matricola_costruttore'] ?? '').toString())),
                              DataCell(
                                SizedBox(
                                  width: _compactView ? 110 : 140,
                                  child: Text(
                                    (r['cantiere_attuale'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text((r['commessa'] ?? '').toString())),
                              if (!_compactView) DataCell(Text((r['dt_nome'] ?? '').toString())),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_va'])),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_cpo'])),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_vqq'])),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_terrazzino'])),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_gru'])),
                              if (!_compactView) DataCell(_expiryText(r['scadenza_cestello'])),
                              if (!_compactView)
                                DataCell(
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      (r['posizione_gps'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              DataCell(
                                InkWell(
                                  onTap: id.isEmpty || _pendingCheckIds.contains(id)
                                      ? null
                                      : () => _toggleGeneralCheck(id, r),
                                  onDoubleTap: id.isEmpty
                                      ? null
                                      : () => _showGeneralCheckAudit(r),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        (r['check_eseguito'] ?? false) == true
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        color: _checkColor(r),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => _showGeneralCheckAudit(r),
                                        child: const Icon(Icons.info_outline, size: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Builder(
                                  builder: (_) {
                                    final checkedCount = _dotazioniCheckedCount(r);
                                    final reqCount = _dotazioniRequestedCount(r);
                                    final label = '$checkedCount/${_dotazioni.length}'
                                        '${reqCount > 0 ? '  |  R:$reqCount' : ''}';
                                    return Text(
                                      label,
                                      style: reqCount > 0
                                          ? TextStyle(
                                              color: _blinkOn
                                                  ? Colors.red
                                                  : Colors.red.withValues(alpha: 0.4),
                                              fontWeight: FontWeight.w700,
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                              DataCell(
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                    IconButton(
                                      tooltip: 'Gestisci check dotazioni',
                                      onPressed: () => _openDotazioniDialog(r),
                                      icon: const Icon(Icons.checklist_outlined, size: 18),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                    ),
                                    IconButton(
                                      tooltip: 'Aggiorna commessa',
                                      onPressed: () => _updateCommessaForRow(r),
                                      icon: const Icon(Icons.business_outlined, size: 18),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                    ),
                                    IconButton(
                                      tooltip: 'Rileva posizione GPS',
                                      onPressed: id.isEmpty ? null : () => _captureGpsForRow(id),
                                      icon: const Icon(Icons.my_location, size: 18),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                    ),
                                    IconButton(
                                      tooltip: 'Apri posizione su mappa',
                                      onPressed: () => _openCoordsOnMap(r),
                                      icon: const Icon(Icons.map_outlined, size: 18),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                    ),
                                    IconButton(
                                      tooltip: (r['check_eseguito'] ?? false) == true
                                          ? 'Rimuovi check generale'
                                          : 'Registra check generale',
                                      onPressed: id.isEmpty || _pendingCheckIds.contains(id)
                                          ? null
                                          : () => _toggleGeneralCheck(id, r),
                                      icon: _pendingCheckIds.contains(id)
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Icon(
                                              (r['check_eseguito'] ?? false) == true
                                                  ? Icons.remove_done_outlined
                                                  : Icons.check_circle_outline,
                                              size: 18,
                                            ),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                    ),
                                    if (!widget.dipendenteMode)
                                      IconButton(
                                        tooltip: 'Modifica',
                                        onPressed: () => _openForm(row: r),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                      ),
                                    if (!widget.dipendenteMode)
                                      IconButton(
                                        tooltip: 'Elimina',
                                        onPressed: id.isEmpty ? null : () => _deleteRow(id),
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                      ),
                                  ],
                                  ),
                                ),
                              ),
                            ].asMap().entries.map((entry) {
                              final idx = entry.key;
                              final cell = entry.value;
                              if (idx >= tooltipKeys.length) return cell;
                              final key = tooltipKeys[idx];
                              return _auditCell(cell, r, key);
                            }).toList());
                          }).toList(growable: false),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MdoDialog extends StatefulWidget {
  final Map<String, dynamic>? row;
  const _MdoDialog({this.row});

  @override
  State<_MdoDialog> createState() => _MdoDialogState();
}

class _MdoDialogState extends State<_MdoDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController matricolaCtrl;
  late final TextEditingController targaCtrl;
  late final TextEditingController mezzoCtrl;
  late final TextEditingController rumoCtrl;
  late final TextEditingController modelloCtrl;
  late final TextEditingController equipmentCtrl;
  late final TextEditingController matricolaCostrCtrl;
  late final TextEditingController cantiereCtrl;
  late final TextEditingController commessaCtrl;
  late final TextEditingController dtCtrl;
  late final TextEditingController posizioneGpsCtrl;
  late final TextEditingController latitudineCtrl;
  late final TextEditingController longitudineCtrl;
  late final TextEditingController scadenzaVaCtrl;
  late final TextEditingController scadenzaCpoCtrl;
  late final TextEditingController scadenzaVqqCtrl;
  late final TextEditingController scadenzaTerrazzinoCtrl;
  late final TextEditingController scadenzaGruCtrl;
  late final TextEditingController scadenzaCestelloCtrl;
  final List<String> _commesse = <String>[];
  final List<String> _dtOptions = <String>[];

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? {};
    matricolaCtrl = TextEditingController(text: (r['matricola_interna'] ?? '').toString());
    targaCtrl = TextEditingController(text: (r['codice_identificativo_targa_rfi'] ?? '').toString());
    mezzoCtrl = TextEditingController(text: (r['descrizione_mezzo'] ?? '').toString());
    rumoCtrl = TextEditingController(text: (r['descrizione_rumo'] ?? '').toString());
    modelloCtrl = TextEditingController(text: (r['modello'] ?? '').toString());
    equipmentCtrl = TextEditingController(text: (r['equipment'] ?? '').toString());
    matricolaCostrCtrl = TextEditingController(text: (r['matricola_costruttore'] ?? '').toString());
    cantiereCtrl = TextEditingController(text: (r['cantiere_attuale'] ?? '').toString());
    commessaCtrl = TextEditingController(text: (r['commessa'] ?? '').toString());
    dtCtrl = TextEditingController(text: (r['dt_nome'] ?? '').toString());
    posizioneGpsCtrl = TextEditingController(text: (r['posizione_gps'] ?? '').toString());
    latitudineCtrl = TextEditingController(text: (r['latitudine'] ?? '').toString());
    longitudineCtrl = TextEditingController(text: (r['longitudine'] ?? '').toString());
    scadenzaVaCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_va']));
    scadenzaCpoCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_cpo']));
    scadenzaVqqCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_vqq']));
    scadenzaTerrazzinoCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_terrazzino']));
    scadenzaGruCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_gru']));
    scadenzaCestelloCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_cestello']));
    _loadCommesse();
    _loadDtOptions();
  }

  Future<void> _loadCommesse() async {
    try {
      final rows = await _supa
          .from('commesse')
          .select('nome,active')
          .eq('active', true)
          .order('nome', ascending: true);
      final items = (rows as List)
          .map((e) => (e['nome'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _commesse
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // fallback: campo manuale sempre disponibile
    }
  }

  Future<void> _loadDtOptions() async {
    try {
      final items = await loadDtDisplayNameList();
      if (!mounted) return;
      setState(() {
        _dtOptions
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // fallback: campo manuale
    }
  }

  @override
  void dispose() {
    matricolaCtrl.dispose();
    targaCtrl.dispose();
    mezzoCtrl.dispose();
    rumoCtrl.dispose();
    modelloCtrl.dispose();
    equipmentCtrl.dispose();
    matricolaCostrCtrl.dispose();
    cantiereCtrl.dispose();
    commessaCtrl.dispose();
    dtCtrl.dispose();
    posizioneGpsCtrl.dispose();
    latitudineCtrl.dispose();
    longitudineCtrl.dispose();
    scadenzaVaCtrl.dispose();
    scadenzaCpoCtrl.dispose();
    scadenzaVqqCtrl.dispose();
    scadenzaTerrazzinoCtrl.dispose();
    scadenzaGruCtrl.dispose();
    scadenzaCestelloCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final latParsed = double.tryParse(latitudineCtrl.text.trim().replaceAll(',', '.'));
    final lonParsed = double.tryParse(longitudineCtrl.text.trim().replaceAll(',', '.'));
    final payload = <String, dynamic>{
      'matricola_interna': matricolaCtrl.text.trim().isEmpty ? null : matricolaCtrl.text.trim(),
      'codice_identificativo_targa_rfi': targaCtrl.text.trim().isEmpty ? null : targaCtrl.text.trim(),
      'descrizione_mezzo': mezzoCtrl.text.trim().isEmpty ? null : mezzoCtrl.text.trim(),
      'descrizione_rumo': rumoCtrl.text.trim().isEmpty ? null : rumoCtrl.text.trim(),
      'modello': modelloCtrl.text.trim().isEmpty ? null : modelloCtrl.text.trim(),
      'equipment': equipmentCtrl.text.trim().isEmpty ? null : equipmentCtrl.text.trim(),
      'matricola_costruttore': matricolaCostrCtrl.text.trim().isEmpty ? null : matricolaCostrCtrl.text.trim(),
      'cantiere_attuale': cantiereCtrl.text.trim().isEmpty ? null : cantiereCtrl.text.trim(),
      'commessa': commessaCtrl.text.trim().isEmpty ? null : commessaCtrl.text.trim(),
      'dt_nome': dtCtrl.text.trim().isEmpty ? null : dtCtrl.text.trim(),
      'posizione_gps': posizioneGpsCtrl.text.trim().isEmpty ? null : posizioneGpsCtrl.text.trim(),
      'latitudine': latitudineCtrl.text.trim().isEmpty ? null : latParsed,
      'longitudine': longitudineCtrl.text.trim().isEmpty ? null : lonParsed,
      'scadenza_va': parseFlexibleDateToIsoDate(scadenzaVaCtrl.text.trim()),
      'scadenza_cpo': parseFlexibleDateToIsoDate(scadenzaCpoCtrl.text.trim()),
      'scadenza_vqq': parseFlexibleDateToIsoDate(scadenzaVqqCtrl.text.trim()),
      'scadenza_terrazzino': parseFlexibleDateToIsoDate(scadenzaTerrazzinoCtrl.text.trim()),
      'scadenza_gru': parseFlexibleDateToIsoDate(scadenzaGruCtrl.text.trim()),
      'scadenza_cestello': parseFlexibleDateToIsoDate(scadenzaCestelloCtrl.text.trim()),
      'active': true,
    };
    final id = (widget.row?['id_uuid'] ?? '').toString();
    if (id.isEmpty) {
      final inserted = await _supa
          .from('logistica_mdo_ferroviari')
          .insert(payload)
          .select('id_uuid')
          .single();
      await propagateMdoUpdateById(
        _supa,
        (inserted['id_uuid'] ?? '').toString(),
      );
    } else {
      await _supa.from('logistica_mdo_ferroviari').update(payload).eq('id_uuid', id);
      await propagateMdoUpdateById(_supa, id);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo MDO ferroviario' : 'Modifica MDO ferroviario'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 6),
              TextField(
                controller: matricolaCtrl,
                decoration: const InputDecoration(labelText: 'Matricola interna', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: targaCtrl,
                decoration: const InputDecoration(labelText: 'Codice identificativo (Targa RFI)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mezzoCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descrizione mezzo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rumoCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descrizione RUMO', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: modelloCtrl,
                decoration: const InputDecoration(labelText: 'Modello', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: equipmentCtrl,
                decoration: const InputDecoration(labelText: 'Equipment', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: matricolaCostrCtrl,
                decoration: const InputDecoration(labelText: 'Matricola costruttore', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cantiereCtrl,
                decoration: const InputDecoration(labelText: 'Cantiere attuale', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: commessaCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return _commesse;
                  return _commesse.where((e) => e.toLowerCase().contains(q));
                },
                onSelected: (value) => commessaCtrl.text = value,
                fieldViewBuilder:
                    (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != commessaCtrl.text) {
                    textCtrl.text = commessaCtrl.text;
                  }
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Commessa (scrivi e seleziona)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => commessaCtrl.text = v,
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
              const SizedBox(height: 8),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: dtCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return _dtOptions;
                  return _dtOptions.where((e) => e.toLowerCase().contains(q));
                },
                onSelected: (value) => dtCtrl.text = value,
                fieldViewBuilder:
                    (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != dtCtrl.text) {
                    textCtrl.text = dtCtrl.text;
                  }
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'DT (scrivi e seleziona)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => dtCtrl.text = v,
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: posizioneGpsCtrl,
                decoration: const InputDecoration(labelText: 'Posizione GPS', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latitudineCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Latitudine', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: longitudineCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Longitudine', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaVaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza VA (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaCpoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza CPO (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaVqqCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza VQQ (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaTerrazzinoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza Terrazzino (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaGruCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza Gru (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzaCestelloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza Cestello (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                ),
              ),
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
}
