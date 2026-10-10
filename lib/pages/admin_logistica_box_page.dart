import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/deadline_nav_highlight.dart';
import '../services/logistica_box_linked_sync.dart';
import '../services/notification_sender.dart';
import '../services/notification_routing_rules_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/logistica_layout.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Etichette tooltip tracciabilità per colonna (chiave `field_timestamps`).
const _boxFieldAuditLabels = <String, String>{
  'numero_interno': 'Numero interno',
  'tipologia': 'Tipologia',
  'lunghezza_cm': 'Lunghezza',
  'larghezza_cm': 'Larghezza',
  'altezza_cm': 'Altezza',
  'peso_kg': 'Peso',
  'ingressi': 'Ingressi',
  'vani': 'Vani',
  'ac': 'AC',
  'matricola': 'Matricola',
  'data_acquisto': 'Data acquisto',
  'data_consegna': 'Data consegna',
  'fornitore': 'Fornitore',
  'ordine_acquisto': 'Ordine acquisto',
  'periodo_trasferimento': 'Periodo trasferimento',
  'commessa_provenienza': 'Commessa provenienza',
  'codice_box': 'Codice BOX',
  'nome_box': 'Nome BOX',
  'commessa_id': 'Commessa',
  'ubicazione': 'Ubicazione',
  'posizione_gps': 'Coordinate GPS',
  'latitudine': 'Latitudine GPS',
  'longitudine': 'Longitudine GPS',
  'check_eseguito': 'Check',
  'stato': 'Stato',
  'targa_stato': 'Targa',
  'note': 'Note',
};

class AdminLogisticaBoxPage extends StatefulWidget {
  const AdminLogisticaBoxPage({super.key});

  @override
  State<AdminLogisticaBoxPage> createState() => _AdminLogisticaBoxPageState();
}

class _AdminLogisticaBoxPageState extends State<AdminLogisticaBoxPage>
    with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  final ScrollController _headerHorizontalCtrl = ScrollController();
  final ScrollController _bodyHorizontalCtrl = ScrollController();
  final ScrollController _leftVerticalCtrl = ScrollController();
  final ScrollController _rightVerticalCtrl = ScrollController();
  final ScrollController _mobileVerticalCtrl = ScrollController();
  final TextEditingController _commessaFilterSearchCtrl = TextEditingController();
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;
  bool _loading = true;
  bool _compactView = true;
  String _search = '';
  String? _commessaFilter;
  final Map<String, String> _commesse = {};
  final Map<String, String> _utentiByUuid = {};
  final Set<String> _pendingCheckIds = {};
  List<Map<String, dynamic>> _rows = [];
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();

  String _boxRowUuid(Map<String, dynamic> row) =>
      (row['id_uuid'] ?? '').toString().trim();

  bool _deadlineUuidAnchorsMatch(String rowUuid) {
    final t = _deadlineScrollUuid?.trim().toLowerCase();
    final r = rowUuid.trim().toLowerCase();
    return t != null && t.isNotEmpty && r.isNotEmpty && t == r;
  }

  static const double _desktopRowStride = 47; // altezza 46 + divider 1
  static const double _mobileRowStrideEstimate = 215;

  int? _deadlineRowIndex(String id) {
    final needle = id.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (var i = 0; i < _rows.length; i++) {
      if (_boxRowUuid(_rows[i]).toLowerCase() == needle) return i;
    }
    return null;
  }

  /// Scroll alla riga BOX (ListView.builder non monta righe fuori viewport).
  bool _scrollToDeadlineBoxRow() {
    final idx = _deadlineRowIndex(_deadlineScrollUuid ?? '');
    if (idx == null || idx < 0) return false;

    final compact = isLogisticaCompactLayout(context);
    final stride = compact ? _mobileRowStrideEstimate : _desktopRowStride;
    final primary = compact ? _mobileVerticalCtrl : _rightVerticalCtrl;
    final secondary = compact ? null : _leftVerticalCtrl;

    if (!primary.hasClients) return false;

    final pos = primary.position;
    final rowTop = idx * stride;
    final target = (rowTop - pos.viewportDimension * 0.32 + stride / 2)
        .clamp(0.0, pos.maxScrollExtent);

    _syncingVertical = true;
    primary.jumpTo(target);
    if (secondary != null && secondary.hasClients) {
      secondary.jumpTo(
        target.clamp(0.0, secondary.position.maxScrollExtent),
      );
    }
    _syncingVertical = false;

    unawaited(
      primary
          .animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        if (!mounted) return;
        final ctx = _deadlineScrollAnchorKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.2,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }),
    );
    return true;
  }

  void _scheduleDeadlineScrollAndClearAnchor({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrolled = _scrollToDeadlineBoxRow();
      if (!scrolled && attempt < 5) {
        _scheduleDeadlineScrollAndClearAnchor(attempt: attempt + 1);
        return;
      }
      if (!scrolled) {
        scheduleDeadlineScrollToAnchor(_deadlineScrollAnchorKey);
      }
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _deadlineScrollUuid = null);
      });
    });
  }

  void _onDeadlineHighlightUuid(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final hadFilter =
        _search.trim().isNotEmpty || (_commessaFilter ?? '').trim().isNotEmpty;
    setState(() {
      _deadlineScrollUuid = trimmed;
      _search = '';
      _commessaFilter = null;
      _commessaFilterSearchCtrl.clear();
      pinRowByUuidToFront(_rows, trimmed);
    });
    void afterRowsReady() {
      if (!mounted) return;
      pinRowByUuidToFront(_rows, trimmed);
      if (_leftVerticalCtrl.hasClients) _leftVerticalCtrl.jumpTo(0);
      if (_rightVerticalCtrl.hasClients) _rightVerticalCtrl.jumpTo(0);
      _scheduleDeadlineScrollAndClearAnchor();
    }

    if (hadFilter) {
      unawaited(_loadRows().then((_) => afterRowsReady()));
    } else {
      afterRowsReady();
    }
  }

  @override
  void initState() {
    super.initState();
    _headerHorizontalCtrl.addListener(_syncFromHeader);
    _bodyHorizontalCtrl.addListener(_syncFromBody);
    _leftVerticalCtrl.addListener(_syncFromLeftVertical);
    _rightVerticalCtrl.addListener(_syncFromRightVertical);
    _bootstrap();
  }

  @override
  void dispose() {
    disposeDeadlineFlash();
    _headerHorizontalCtrl
      ..removeListener(_syncFromHeader)
      ..dispose();
    _bodyHorizontalCtrl
      ..removeListener(_syncFromBody)
      ..dispose();
    _leftVerticalCtrl
      ..removeListener(_syncFromLeftVertical)
      ..dispose();
    _rightVerticalCtrl
      ..removeListener(_syncFromRightVertical)
      ..dispose();
    _mobileVerticalCtrl.dispose();
    _commessaFilterSearchCtrl.dispose();
    super.dispose();
  }

  void _syncFromHeader() {
    if (_syncingHorizontal || !_bodyHorizontalCtrl.hasClients) return;
    _syncingHorizontal = true;
    _bodyHorizontalCtrl.jumpTo(_headerHorizontalCtrl.offset);
    _syncingHorizontal = false;
  }

  void _syncFromBody() {
    if (_syncingHorizontal || !_headerHorizontalCtrl.hasClients) return;
    _syncingHorizontal = true;
    _headerHorizontalCtrl.jumpTo(_bodyHorizontalCtrl.offset);
    _syncingHorizontal = false;
  }

  void _syncFromLeftVertical() {
    if (_syncingVertical || !_rightVerticalCtrl.hasClients) return;
    _syncingVertical = true;
    _rightVerticalCtrl.jumpTo(_leftVerticalCtrl.offset);
    _syncingVertical = false;
  }

  void _syncFromRightVertical() {
    if (_syncingVertical || !_leftVerticalCtrl.hasClients) return;
    _syncingVertical = true;
    _leftVerticalCtrl.jumpTo(_rightVerticalCtrl.offset);
    _syncingVertical = false;
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadCommesse();
      await _loadRows(consumeNavHighlight: false);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
      }
    }
  }

  Future<void> _loadCommesse() async {
    final res = await _supa
        .from('commesse')
        .select('id_uuid,nome,active')
        .eq('active', true)
        .order('nome');
    _commesse
      ..clear()
      ..addEntries((res as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return MapEntry((m['id_uuid'] ?? '').toString(), (m['nome'] ?? '').toString());
      }));
  }

  Future<void> _loadRows({bool consumeNavHighlight = true}) async {
    var q = _supa.from('logistica_box').select();
    if ((_commessaFilter ?? '').trim().isNotEmpty) {
      q = q.eq('commessa_id', _commessaFilter!);
    }
    final res = await q.order('numero_interno', ascending: true);
    var list = List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final tokens = [
          r['numero_interno'],
          r['tipologia'],
          r['lunghezza_cm'],
          r['larghezza_cm'],
          r['altezza_cm'],
          r['peso_kg'],
          r['ingressi'],
          r['vani'],
          r['ac'],
          r['matricola'],
          r['fornitore'],
          r['ordine_acquisto'],
          r['periodo_trasferimento'],
          r['commessa_provenienza'],
          r['data_acquisto'],
          r['data_consegna'],
          r['posizione_gps'],
          r['latitudine'],
          r['longitudine'],
          r['codice_box'],
          r['nome_box'],
          r['ubicazione'],
          r['stato'],
          r['targa_stato'],
          r['note'],
          _commesse[(r['commessa_id'] ?? '').toString()],
        ].map((v) => (v ?? '').toString().toLowerCase());
        return tokens.any((t) => t.contains(k));
      }).toList(growable: false);
    }

    // Ordine naturale crescente: BOX1, BOX2, ... BOX10
    list.sort((a, b) {
      final aVal = ((a['numero_interno'] ?? a['codice_box'] ?? '')).toString();
      final bVal = ((b['numero_interno'] ?? b['codice_box'] ?? '')).toString();
      return _naturalCompare(aVal, bVal);
    });

    final ids = <String>{};
    for (final r in list) {
      final c = (r['created_by_user_uuid'] ?? '').toString().trim();
      final u = (r['updated_by_user_uuid'] ?? '').toString().trim();
      final chk = (r['check_confermato_by_uuid'] ?? '').toString().trim();
      if (c.isNotEmpty) ids.add(c);
      if (u.isNotEmpty) ids.add(u);
      if (chk.isNotEmpty) ids.add(chk);
      mergeFieldTimestampActorUuids(r, ids);
    }
    final map = <String, String>{};
    if (ids.isNotEmpty) {
      final users = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .inFilter('id_uuid', ids.toList());
      for (final e in (users as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString();
        final full = (m['full_name'] ?? '').toString().trim();
        final user = (m['username'] ?? '').toString().trim();
        if (id.isNotEmpty) map[id] = full.isNotEmpty ? full : user;
      }
    }

    for (final r in list) {
      final normalized = normalizeFieldTimestampsForRow(r);
      if (normalized.isNotEmpty) {
        r['field_timestamps'] = normalized;
      }
    }

    setState(() {
      _rows = list;
      _utentiByUuid
        ..clear()
        ..addAll(map);
    });
    if (consumeNavHighlight) {
      maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
    }
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
      final sheet = excel['Logistica_BOX'];
      sheet.appendRow([
        'Numero interno',
        'Tipologia',
        'Commessa',
        'Ubicazione',
        'Posizione GPS',
        'Stato',
        'Targa stato',
        'Check eseguito',
        'Note',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          (r['numero_interno'] ?? '').toString(),
          (r['tipologia'] ?? '').toString(),
          _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
          (r['ubicazione'] ?? '').toString(),
          (r['posizione_gps'] ?? '').toString(),
          (r['stato'] ?? '').toString(),
          (r['targa_stato'] ?? '').toString(),
          (r['check_eseguito'] ?? false) == true ? 'SI' : 'NO',
          (r['note'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Logistica_BOX',
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

  int _naturalCompare(String a, String b) {
    final aParts = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
    final bParts = RegExp(r'\d+|\D+').allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final ap = aParts[i];
      final bp = bParts[i];
      final an = int.tryParse(ap);
      final bn = int.tryParse(bp);
      if (an != null && bn != null) {
        final cmp = an.compareTo(bn);
        if (cmp != 0) return cmp;
      } else {
        final cmp = ap.compareTo(bp);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BoxDialog(commesse: _commesse, row: row),
    );
    if (ok == true) {
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(row == null ? 'BOX salvato correttamente.' : 'BOX aggiornato correttamente.'),
        ),
      );
    }
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina BOX'),
        content: const Text('Confermi eliminazione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('logistica_box').delete().eq('id_uuid', id);
    await _loadRows();
  }

  String _fmtDateTime(dynamic v) {
    final s = formatDateTimeItFromSupabase(v);
    if (s.isNotEmpty) return s;
    if (v == null) return '';
    return v.toString();
  }

  String _fmtDateOnly(dynamic v) => formatDateDdMmYyyy(v);

  double get _azioniColWidth => _compactView ? 217.0 : 220.0;

  double get _rightTableWidthCompact {
    // Tipologia + Commessa + Ubicazione + Coordinate GPS + Check + Stato + Targa + Note + Azioni
    return 260 + 170 + 190 + 150 + 80 + 90 + 90 + 180 + _azioniColWidth;
  }

  double get _rightTableWidthFull {
    return 260 +
        95 +
        95 +
        90 +
        80 +
        70 +
        60 +
        55 +
        120 +
        110 +
        110 +
        130 +
        120 +
        140 +
        150 +
        90 +
        180 +
        170 +
        190 +
        150 +
        80 +
        90 +
        90 +
        180 +
        220;
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _bodyCell(dynamic value, double width, {int maxLines = 1}) {
    final text = (value ?? '').toString();
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _withAuditHover(
    Widget child,
    Map<String, dynamic> row,
    String fieldKey,
  ) {
    return wrapWithAuditHover(
      child,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
      fieldLabel: _boxFieldAuditLabels[fieldKey],
    );
  }

  Widget _auditText(
    String text, {
    required Map<String, dynamic> row,
    required String fieldKey,
    TextStyle? style,
    int? maxLines,
  }) {
    return _withAuditHover(
      Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      ),
      row,
      fieldKey,
    );
  }

  Widget _actionIcon({
    required String tooltip,
    required IconData icon,
    Color? color,
    required VoidCallback? onPressed,
    Widget? customIcon,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      iconSize: 18,
      color: color,
      onPressed: onPressed,
      icon: customIcon ?? Icon(icon),
    );
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

  int _notificationBookingIdFromUuid(String idUuid) {
    final uuid = idUuid.toLowerCase().replaceAll('-', '');
    if (uuid.length >= 8) {
      final v = int.tryParse(uuid.substring(0, 8), radix: 16);
      if ((v ?? 0) > 0) return v!;
    }
    return DateTime.now().millisecondsSinceEpoch.remainder(2000000000) + 1;
  }

  Future<void> _notifyRolesForBoxCheck({
    required String boxIdUuid,
    required String boxCode,
  }) async {
    final rules = await NotificationRoutingRulesService.listRules();
    final rule = rules.firstWhere(
      (r) => (r['rule_key'] ?? '').toString() == 'logistica_box_check_completed_notify',
      orElse: () => const <String, dynamic>{},
    );
    final enabled = rule['enabled'] == true;
    if (!enabled) return;
    final targets = ((rule['targets'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString().trim())
        .where((e) => e.startsWith('role:'))
        .map((e) => e.replaceFirst('role:', ''))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (targets.isEmpty) return;

    final users = await _supa
        .from('users')
        .select('id,role')
        .inFilter('role', targets);
    final ids = (users as List)
        .map((e) => Map<String, dynamic>.from(e as Map)['id'])
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: _notificationBookingIdFromUuid(boxIdUuid),
      action: 'logistica_box_check_completed',
      title: 'Check logistica BOX confermato',
      message: 'Check confermato per BOX $boxCode',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<void> _confirmCheck(String id) async {
    if (_pendingCheckIds.contains(id)) return;
    setState(() => _pendingCheckIds.add(id));
    try {
      final currentUserId = _supa.auth.currentUser?.id;
      String? checkByUuid = currentUserId;
      if ((currentUserId ?? '').trim().isNotEmpty) {
        try {
          final meByAuth = await _supa
              .from('users')
              .select('id_uuid')
              .eq('auth_id', currentUserId!)
              .maybeSingle();
          final idUuid = (meByAuth?['id_uuid'] ?? '').toString().trim();
          if (idUuid.isNotEmpty) {
            checkByUuid = idUuid;
          }
        } catch (_) {
          // fallback su auth uid corrente
        }
      }
      await _supa.from('logistica_box').update({
        'check_eseguito': true,
        'check_confermato_at': DateTime.now().toUtc().toIso8601String(),
        'check_confermato_by_uuid': checkByUuid,
      }).eq('id_uuid', id);
      try {
        Map<String, dynamic>? row;
        for (final r in _rows) {
          if ((r['id_uuid'] ?? '').toString() == id) {
            row = r;
            break;
          }
        }
        final code = (row?['numero_interno'] ?? row?['codice_box'] ?? row?['nome_box'] ?? id).toString();
        await _notifyRolesForBoxCheck(
          boxIdUuid: id,
          boxCode: code,
        );
      } catch (_) {
        // Non bloccare il flusso check in caso di errore notifica.
      }
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check confermato.')),
      );
    } finally {
      if (mounted) setState(() => _pendingCheckIds.remove(id));
    }
  }

  Future<void> _removeCheck(String id) async {
    if (_pendingCheckIds.contains(id)) return;
    setState(() => _pendingCheckIds.add(id));
    try {
      await _supa.from('logistica_box').update({
        'check_eseguito': false,
        'check_confermato_at': null,
        'check_confermato_by_uuid': null,
      }).eq('id_uuid', id);
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check rimosso.')),
      );
    } finally {
      if (mounted) setState(() => _pendingCheckIds.remove(id));
    }
  }

  Future<void> _captureGpsForRow(String id) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS disattivato sul dispositivo.')),
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final lat = pos.latitude.toStringAsFixed(6);
      final lon = pos.longitude.toStringAsFixed(6);
      await _supa.from('logistica_box').update({
        'posizione_gps': '$lat, $lon',
        'latitudine': pos.latitude,
        'longitudine': pos.longitude,
      }).eq('id_uuid', id);
      await propagateLogisticaBoxUpdateById(_supa, id);
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinate GPS aggiornate.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante rilevazione coordinate GPS.')),
      );
    }
  }

  Future<void> _openCoordsOnMap(Map<String, dynamic> row) async {
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinate GPS non disponibili.')),
      );
      return;
    }
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${coords.$1},${coords.$2}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire la mappa.')),
      );
    }
  }

  Future<void> _showAudit(Map<String, dynamic> r) async {
    final createdByUuid = (r['created_by_user_uuid'] ?? '').toString().trim();
    final updatedByUuid = (r['updated_by_user_uuid'] ?? '').toString().trim();
    var createdBy = _utentiByUuid[createdByUuid];
    var updatedBy = _utentiByUuid[updatedByUuid];
    if ((createdBy ?? '').trim().isEmpty && createdByUuid.isNotEmpty) {
      try {
        final byAuth = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .eq('auth_id', createdByUuid)
            .maybeSingle();
        if (byAuth != null) {
          final mappedId = (byAuth['id_uuid'] ?? '').toString().trim();
          final full = (byAuth['full_name'] ?? '').toString().trim();
          final user = (byAuth['username'] ?? '').toString().trim();
          final resolved = full.isNotEmpty ? full : user;
          if (resolved.isNotEmpty) {
            createdBy = resolved;
            if (mappedId.isNotEmpty) _utentiByUuid[mappedId] = resolved;
            _utentiByUuid[createdByUuid] = resolved;
          }
        }
      } catch (_) {}
    }
    if ((updatedBy ?? '').trim().isEmpty && updatedByUuid.isNotEmpty) {
      try {
        final byAuth = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .eq('auth_id', updatedByUuid)
            .maybeSingle();
        if (byAuth != null) {
          final mappedId = (byAuth['id_uuid'] ?? '').toString().trim();
          final full = (byAuth['full_name'] ?? '').toString().trim();
          final user = (byAuth['username'] ?? '').toString().trim();
          final resolved = full.isNotEmpty ? full : user;
          if (resolved.isNotEmpty) {
            updatedBy = resolved;
            if (mappedId.isNotEmpty) _utentiByUuid[mappedId] = resolved;
            _utentiByUuid[updatedByUuid] = resolved;
          }
        }
      } catch (_) {}
    }
    createdBy ??= createdByUuid;
    updatedBy ??= updatedByUuid;
    final createdByText = createdBy.trim();
    final updatedByText = updatedBy.trim();
    final createdAt = (r['created_at'] ?? '').toString();
    final updatedAt = (r['updated_at'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Traccia modifiche'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inserito il: ${_fmtDateTime(createdAt)}'),
            Text('Inserito da: ${createdByText.isEmpty ? '—' : createdByText}'),
            const SizedBox(height: 8),
            Text('Ultima modifica il: ${_fmtDateTime(updatedAt)}'),
            Text('Ultima modifica da: ${updatedByText.isEmpty ? '—' : updatedByText}'),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Future<void> _showCheckAudit(Map<String, dynamic> r) async {
    final checked = (r['check_eseguito'] ?? false) == true;
    final byUuid = (r['check_confermato_by_uuid'] ?? '').toString().trim();
    var byName = _utentiByUuid[byUuid];
    if ((byName ?? '').trim().isEmpty && byUuid.isNotEmpty) {
      try {
        final byAuth = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .eq('auth_id', byUuid)
            .maybeSingle();
        if (byAuth != null) {
          final mappedId = (byAuth['id_uuid'] ?? '').toString().trim();
          final full = (byAuth['full_name'] ?? '').toString().trim();
          final user = (byAuth['username'] ?? '').toString().trim();
          final resolved = full.isNotEmpty ? full : user;
          if (resolved.isNotEmpty) {
            byName = resolved;
            if (mappedId.isNotEmpty) {
              _utentiByUuid[mappedId] = resolved;
            }
            _utentiByUuid[byUuid] = resolved;
          }
        }
      } catch (_) {
        // fallback sotto
      }
    }
    byName ??= byUuid;
    final byNameText = byName.trim();
    final at = _fmtDateTime(r['check_confermato_at']);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tracciabilita check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Check eseguito: ${checked ? 'SI' : 'NO'}'),
            Text('Confermato da: ${byNameText.isEmpty ? '—' : byNameText}'),
            Text('Confermato il: ${at.isEmpty ? '—' : at}'),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(List<MapEntry<String, String>> commessaItems) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Cerca BOX, codice, ubicazione...',
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
                width: 320,
                child: Autocomplete<MapEntry<String, String>>(
                  initialValue: TextEditingValue(text: _commessaFilterSearchCtrl.text),
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.trim().toLowerCase();
                    if (q.isEmpty) return commessaItems;
                    return commessaItems.where((e) => e.value.toLowerCase().contains(q));
                  },
                  displayStringForOption: (opt) => opt.value,
                  onSelected: (opt) async {
                    _commessaFilterSearchCtrl.text = opt.value;
                    setState(() => _commessaFilter = opt.key);
                    await _loadRows();
                  },
                  fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
                    if (textCtrl.text != _commessaFilterSearchCtrl.text) {
                      textCtrl.text = _commessaFilterSearchCtrl.text;
                    }
                    return TextField(
                      controller: textCtrl,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Commessa (scrivi e seleziona)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: 'Azzera filtro commessa',
                          icon: const Icon(Icons.clear),
                          onPressed: () async {
                            textCtrl.clear();
                            _commessaFilterSearchCtrl.clear();
                            setState(() => _commessaFilter = null);
                            await _loadRows();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _mobileVerticalCtrl,
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final r = _rows[index];
              final id = _boxRowUuid(r);
              final checked = (r['check_eseguito'] ?? false) == true;
              final flash = id.isNotEmpty && deadlineFlashLit(id);
              return KeyedSubtree(
                key: _deadlineUuidAnchorsMatch(id)
                    ? _deadlineScrollAnchorKey
                    : ValueKey<String>('box_mobile_$id'),
                child: Card(
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                color: flash ? Colors.amber.withValues(alpha: 0.38) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _auditText(
                        (r['numero_interno'] ?? '').toString(),
                        row: r,
                        fieldKey: 'numero_interno',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _auditText(
                        (r['tipologia'] ?? '').toString(),
                        row: r,
                        fieldKey: 'tipologia',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 6),
                      _auditText(
                        'Commessa: ${_commesse[(r['commessa_id'] ?? '').toString()] ?? ''}',
                        row: r,
                        fieldKey: 'commessa_id',
                      ),
                      _auditText(
                        'Ubicazione: ${(r['ubicazione'] ?? '').toString()}',
                        row: r,
                        fieldKey: 'ubicazione',
                      ),
                      _auditText(
                        'Coordinate GPS: ${(r['posizione_gps'] ?? '').toString()}',
                        row: r,
                        fieldKey: 'posizione_gps',
                      ),
                      _auditText(
                        'Stato: ${(r['stato'] ?? '').toString()} · Targa: ${(r['targa_stato'] ?? '').toString()}',
                        row: r,
                        fieldKey: 'stato',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          IconButton(tooltip: 'Traccia modifiche', onPressed: () => _showAudit(r), icon: const Icon(Icons.history)),
                          IconButton(tooltip: 'Modifica', onPressed: () => _openForm(row: r), icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                            tooltip: 'Elimina',
                            onPressed: id.isEmpty ? null : () => _deleteRow(id),
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                          IconButton(tooltip: 'Apri posizione su mappa', onPressed: () => _openCoordsOnMap(r), icon: const Icon(Icons.map_outlined)),
                          IconButton(
                            tooltip: 'Rileva coordinate GPS',
                            onPressed: id.isEmpty ? null : () => _captureGpsForRow(id),
                            icon: const Icon(Icons.my_location),
                          ),
                          IconButton(
                            tooltip: checked ? 'Rimuovi check' : 'Conferma check',
                            onPressed: id.isEmpty ? null : () => (checked ? _removeCheck(id) : _confirmCheck(id)),
                            icon: Icon(checked ? Icons.remove_done_outlined : Icons.check_circle_outline),
                          ),
                          IconButton(
                            tooltip: 'Audit check',
                            onPressed: () => _showCheckAudit(r),
                            icon: Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, color: _checkColor(r)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout = isLogisticaCompactLayout(context);
    final commessaItems = _commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final selectedCommessaName = _commesse[_commessaFilter ?? ''] ?? '';
    if (_commessaFilterSearchCtrl.text != selectedCommessaName) {
      _commessaFilterSearchCtrl.text = selectedCommessaName;
    }
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Logistica - BOX'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportExcel,
          ),
          IconButton(
            tooltip: 'Nuovo BOX',
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(),
          ),
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRows,
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : isMobileLayout
                ? _buildMobileLayout(commessaItems)
                : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: logisticaFieldWidth(context, desktop: 300),
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Cerca BOX, codice, ubicazione...',
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
                          width: logisticaFieldWidth(context, desktop: 260),
                          child: Autocomplete<MapEntry<String, String>>(
                            initialValue: TextEditingValue(text: _commessaFilterSearchCtrl.text),
                            optionsBuilder: (textEditingValue) {
                              final q = textEditingValue.text.trim().toLowerCase();
                              if (q.isEmpty) return commessaItems;
                              return commessaItems.where((e) => e.value.toLowerCase().contains(q));
                            },
                            displayStringForOption: (opt) => opt.value,
                            onSelected: (opt) async {
                              _commessaFilterSearchCtrl.text = opt.value;
                              setState(() => _commessaFilter = opt.key);
                              await _loadRows();
                            },
                            fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
                              if (textCtrl.text != _commessaFilterSearchCtrl.text) {
                                textCtrl.text = _commessaFilterSearchCtrl.text;
                              }
                              return TextField(
                                controller: textCtrl,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  labelText: 'Commessa (scrivi e seleziona)',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: IconButton(
                                    tooltip: 'Azzera filtro commessa',
                                    icon: const Icon(Icons.clear),
                                    onPressed: () async {
                                      textCtrl.clear();
                                      _commessaFilterSearchCtrl.clear();
                                      setState(() => _commessaFilter = null);
                                      await _loadRows();
                                    },
                                  ),
                                ),
                                onChanged: (v) {
                                  _commessaFilterSearchCtrl.text = v;
                                },
                                onSubmitted: (_) async {
                                  final exact = commessaItems.where((e) =>
                                      e.value.toLowerCase() == textCtrl.text.trim().toLowerCase());
                                  setState(() => _commessaFilter = exact.isNotEmpty ? exact.first.key : null);
                                  await _loadRows();
                                },
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<bool>(
                            initialValue: _compactView,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Vista',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem<bool>(value: true, child: Text('Compatta')),
                              DropdownMenuItem<bool>(value: false, child: Text('Completa')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _compactView = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            border: Border(
                              top: BorderSide(color: Theme.of(context).dividerColor),
                              bottom: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              _headerCell('Numero interno', 110),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _headerHorizontalCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _headerCell('Tipologia', 260),
                                      if (!_compactView) _headerCell('Lunghezza cm', 95),
                                      if (!_compactView) _headerCell('Larghezza cm', 95),
                                      if (!_compactView) _headerCell('Altezza cm', 90),
                                      if (!_compactView) _headerCell('Peso kg', 80),
                                      if (!_compactView) _headerCell('Ingressi', 70),
                                      if (!_compactView) _headerCell('Vani', 60),
                                      if (!_compactView) _headerCell('A/C', 55),
                                      if (!_compactView) _headerCell('Matricola', 120),
                                      if (!_compactView) _headerCell('Data acquisto', 110),
                                      if (!_compactView) _headerCell('Data consegna', 110),
                                      if (!_compactView) _headerCell('Fornitore', 140),
                                      if (!_compactView) _headerCell("Ordine d'acquisto", 130),
                                      if (!_compactView) _headerCell('Periodo trasferimento', 150),
                                      if (!_compactView) _headerCell('Commessa provenienza', 160),
                                      if (!_compactView) _headerCell('Codice BOX', 100),
                                      if (!_compactView) _headerCell('Nome BOX', 220),
                                      _headerCell('Commessa', 170),
                                      _headerCell('Ubicazione', 190),
                                      _headerCell('Coordinate GPS', 150),
                                      _headerCell('Check', 80),
                                      _headerCell('Stato', 90),
                                      _headerCell('Targa', 90),
                                      _headerCell('Note', 180),
                                      _headerCell('Azioni', _azioniColWidth),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 110,
                                child: ListView.separated(
                                  controller: _leftVerticalCtrl,
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final r = _rows[index];
                                    final id = _boxRowUuid(r);
                                    final flash = id.isNotEmpty && deadlineFlashLit(id);
                                    return Container(
                                      key: ValueKey<String>('box_left_$id'),
                                      height: 46,
                                      color: flash
                                          ? Colors.amber.withValues(alpha: 0.42)
                                          : null,
                                      child: Row(
                                        children: [
                                          _withAuditHover(
                                            _bodyCell(r['numero_interno'], 110),
                                            r,
                                            'numero_interno',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: Scrollbar(
                                  controller: _bodyHorizontalCtrl,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _bodyHorizontalCtrl,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: _compactView ? _rightTableWidthCompact : _rightTableWidthFull,
                                      child: ListView.separated(
                                        controller: _rightVerticalCtrl,
                                        itemCount: _rows.length,
                                        separatorBuilder: (_, _) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final r = _rows[index];
                                          final id = _boxRowUuid(r);
                                          final flash = id.isNotEmpty && deadlineFlashLit(id);
                                          return KeyedSubtree(
                                            key: _deadlineUuidAnchorsMatch(id)
                                                ? _deadlineScrollAnchorKey
                                                : ValueKey<String>('box_right_$id'),
                                            child: Container(
                                            height: 46,
                                            color: flash
                                                ? Colors.amber.withValues(alpha: 0.42)
                                                : null,
                                            child: Row(
                                              children: [
                                                _withAuditHover(_bodyCell(r['tipologia'], 260, maxLines: 1), r, 'tipologia'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['lunghezza_cm'], 95), r, 'lunghezza_cm'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['larghezza_cm'], 95), r, 'larghezza_cm'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['altezza_cm'], 90), r, 'altezza_cm'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['peso_kg'], 80), r, 'peso_kg'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['ingressi'], 70), r, 'ingressi'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['vani'], 60), r, 'vani'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['ac'], 55), r, 'ac'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['matricola'], 120), r, 'matricola'),
                                                if (!_compactView) _withAuditHover(_bodyCell(_fmtDateOnly(r['data_acquisto']), 110), r, 'data_acquisto'),
                                                if (!_compactView) _withAuditHover(_bodyCell(_fmtDateOnly(r['data_consegna']), 110), r, 'data_consegna'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['fornitore'], 130), r, 'fornitore'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['ordine_acquisto'], 120), r, 'ordine_acquisto'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['periodo_trasferimento'], 140), r, 'periodo_trasferimento'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['commessa_provenienza'], 150), r, 'commessa_provenienza'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['codice_box'], 90), r, 'codice_box'),
                                                if (!_compactView) _withAuditHover(_bodyCell(r['nome_box'], 180, maxLines: 2), r, 'nome_box'),
                                                _withAuditHover(_bodyCell(_commesse[(r['commessa_id'] ?? '').toString()] ?? '', 170), r, 'commessa_id'),
                                                _withAuditHover(_bodyCell(r['ubicazione'], 190, maxLines: 2), r, 'ubicazione'),
                                                _withAuditHover(_bodyCell(r['posizione_gps'], 150, maxLines: 2), r, 'posizione_gps'),
                                                _withAuditHover(SizedBox(
                                                  width: 80,
                                                  child: InkWell(
                                                  onTap: () => _showCheckAudit(r),
                                                  onDoubleTap: id.isEmpty
                                                      ? null
                                                      : () {
                                                          final checked = (r['check_eseguito'] ?? false) == true;
                                                          if (checked) {
                                                            _removeCheck(id);
                                                          } else {
                                                            _confirmCheck(id);
                                                          }
                                                        },
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                      Icon(
                                                        (r['check_eseguito'] ?? false) == true
                                                            ? Icons.check_box
                                                            : Icons.check_box_outline_blank,
                                                        color: _checkColor(r),
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      const Icon(Icons.info_outline, size: 14),
                                                      ],
                                                    ),
                                                  ),
                                                ), r, 'check_eseguito'),
                                                _withAuditHover(_bodyCell(r['stato'], 90), r, 'stato'),
                                                _withAuditHover(_bodyCell(r['targa_stato'], 90), r, 'targa_stato'),
                                                _withAuditHover(
                                                  SizedBox(
                                                    width: 180,
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                                      child: NotePreviewText(
                                                        note: (r['note'] ?? '').toString(),
                                                        maxChars: 10,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  r,
                                                  'note',
                                                ),
                                              _withAuditHover(SizedBox(
                                                width: _azioniColWidth,
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      _actionIcon(
                                                        tooltip: 'Traccia modifiche',
                                                        icon: Icons.history,
                                                        onPressed: () => _showAudit(r),
                                                      ),
                                                      _actionIcon(
                                                        tooltip: 'Modifica',
                                                        icon: Icons.edit_outlined,
                                                        onPressed: () => _openForm(row: r),
                                                      ),
                                                      _actionIcon(
                                                        tooltip: 'Elimina',
                                                        icon: Icons.delete_outline,
                                                        color: Colors.red,
                                                        onPressed: id.isEmpty ? null : () => _deleteRow(id),
                                                      ),
                                                      _actionIcon(
                                                        tooltip: 'Apri posizione su mappa',
                                                        icon: Icons.map_outlined,
                                                        onPressed: () => _openCoordsOnMap(r),
                                                      ),
                                                    _actionIcon(
                                                      tooltip: 'Rileva coordinate GPS',
                                                      icon: Icons.my_location,
                                                      onPressed: id.isEmpty ? null : () => _captureGpsForRow(id),
                                                    ),
                                                      _actionIcon(
                                                      tooltip: (r['check_eseguito'] ?? false) == true
                                                          ? 'Rimuovi check'
                                                          : 'Conferma check',
                                                      icon: (r['check_eseguito'] ?? false) == true
                                                          ? Icons.remove_done_outlined
                                                          : Icons.check_circle_outline,
                                                        customIcon: _pendingCheckIds.contains(id)
                                                            ? const SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child: CircularProgressIndicator(strokeWidth: 2),
                                                              )
                                                            : null,
                                                        onPressed: id.isEmpty || _pendingCheckIds.contains(id)
                                                            ? null
                                                          : () {
                                                              final checked = (r['check_eseguito'] ?? false) == true;
                                                              if (checked) {
                                                                _removeCheck(id);
                                                              } else {
                                                                _confirmCheck(id);
                                                              }
                                                            },
                                                      ),
                                                    ],
                                                  ),
                                                ), r, 'updated_at'),
                                              ],
                                            ),
                                          ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BoxDialog extends StatefulWidget {
  final Map<String, String> commesse;
  final Map<String, dynamic>? row;
  const _BoxDialog({required this.commesse, this.row});

  @override
  State<_BoxDialog> createState() => _BoxDialogState();
}

class _BoxDialogState extends State<_BoxDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController numeroInternoCtrl;
  late final TextEditingController tipologiaCtrl;
  late final TextEditingController lunghezzaCtrl;
  late final TextEditingController larghezzaCtrl;
  late final TextEditingController altezzaCtrl;
  late final TextEditingController pesoKgCtrl;
  late final TextEditingController ingressiCtrl;
  late final TextEditingController vaniCtrl;
  late final TextEditingController acCtrl;
  late final TextEditingController matricolaCtrl;
  late final TextEditingController dataAcquistoCtrl;
  late final TextEditingController dataConsegnaCtrl;
  late final TextEditingController fornitoreCtrl;
  late final TextEditingController ordineAcquistoCtrl;
  late final TextEditingController periodoTrasferimentoCtrl;
  late final TextEditingController commessaProvenienzaCtrl;
  late final TextEditingController posizioneGpsCtrl;
  late final TextEditingController codiceCtrl;
  late final TextEditingController nomeCtrl;
  late final TextEditingController ubicazioneCtrl;
  late final TextEditingController statoCtrl;
  late final TextEditingController noteCtrl;
  late final TextEditingController commessaSearchCtrl;
  String? targaStatoSel;
  String? commessaSel;
  double? _latitudine;
  double? _longitudine;
  bool _gpsLoading = false;
  late final bool _isEdit;
  late final String _baselineUbicazione;
  late final String _baselineCommessaId;
  late String _lastCommessaLabel;
  bool _periodoManuallyEdited = false;
  bool _provenienzaManuallyEdited = false;

  String _commessaLabelFor(String? id) {
    if (id == null || id.trim().isEmpty) return '';
    return widget.commesse[id] ?? '';
  }

  String _todayTransferDate() => formatDateDdMmYyyyFromDate(DateTime.now());

  void _onUbicazioneChanged() {
    if (!_isEdit) return;
    if (ubicazioneCtrl.text.trim() == _baselineUbicazione) return;
    if (_periodoManuallyEdited) return;
    periodoTrasferimentoCtrl.text = _todayTransferDate();
  }

  void _applyCommessaChange(String? newId) {
    final newKey = (newId ?? '').trim();
    final prevKey = (commessaSel ?? '').trim();
    if (newKey == prevKey) return;

    if (_isEdit && newKey != _baselineCommessaId) {
      if (!_periodoManuallyEdited) {
        periodoTrasferimentoCtrl.text = _todayTransferDate();
      }
      if (!_provenienzaManuallyEdited) {
        final prevLabel = _lastCommessaLabel.trim();
        if (prevLabel.isNotEmpty) {
          commessaProvenienzaCtrl.text = prevLabel;
        }
      }
    }

    commessaSel = newId;
    _lastCommessaLabel = _commessaLabelFor(newId);
  }

  void _applyTransferFieldsOnSave() {
    if (!_isEdit) return;
    final ubicazioneChanged =
        ubicazioneCtrl.text.trim() != _baselineUbicazione;
    final commessaChanged = (commessaSel ?? '').trim() != _baselineCommessaId;
    if (!ubicazioneChanged && !commessaChanged) return;

    if (!_periodoManuallyEdited) {
      periodoTrasferimentoCtrl.text = _todayTransferDate();
    }
    if (commessaChanged &&
        !_provenienzaManuallyEdited &&
        commessaProvenienzaCtrl.text.trim().isEmpty) {
      final prev = _commessaLabelFor(
        _baselineCommessaId.isEmpty ? null : _baselineCommessaId,
      );
      if (prev.isNotEmpty) {
        commessaProvenienzaCtrl.text = prev;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? {};
    numeroInternoCtrl = TextEditingController(text: (r['numero_interno'] ?? '').toString());
    tipologiaCtrl = TextEditingController(text: (r['tipologia'] ?? '').toString());
    lunghezzaCtrl = TextEditingController(text: (r['lunghezza_cm'] ?? '').toString());
    larghezzaCtrl = TextEditingController(text: (r['larghezza_cm'] ?? '').toString());
    altezzaCtrl = TextEditingController(text: (r['altezza_cm'] ?? '').toString());
    pesoKgCtrl = TextEditingController(text: (r['peso_kg'] ?? '').toString());
    ingressiCtrl = TextEditingController(text: (r['ingressi'] ?? '').toString());
    vaniCtrl = TextEditingController(text: (r['vani'] ?? '').toString());
    acCtrl = TextEditingController(text: (r['ac'] ?? '').toString());
    matricolaCtrl = TextEditingController(text: (r['matricola'] ?? '').toString());
    dataAcquistoCtrl = TextEditingController(text: formatDateDdMmYyyy(r['data_acquisto']));
    dataConsegnaCtrl = TextEditingController(text: formatDateDdMmYyyy(r['data_consegna']));
    fornitoreCtrl = TextEditingController(text: (r['fornitore'] ?? '').toString());
    ordineAcquistoCtrl = TextEditingController(text: (r['ordine_acquisto'] ?? '').toString());
    periodoTrasferimentoCtrl = TextEditingController(text: (r['periodo_trasferimento'] ?? '').toString());
    commessaProvenienzaCtrl = TextEditingController(text: (r['commessa_provenienza'] ?? '').toString());
    posizioneGpsCtrl = TextEditingController(text: (r['posizione_gps'] ?? '').toString());
    codiceCtrl = TextEditingController(text: (r['codice_box'] ?? '').toString());
    nomeCtrl = TextEditingController(text: (r['nome_box'] ?? '').toString());
    ubicazioneCtrl = TextEditingController(text: (r['ubicazione'] ?? '').toString());
    statoCtrl = TextEditingController(text: (r['stato'] ?? '').toString());
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
    final targaRaw = (r['targa_stato'] ?? '').toString().trim().toLowerCase();
    if (targaRaw == 'presente') {
      targaStatoSel = 'Presente';
    } else if (targaRaw == 'mancante') {
      targaStatoSel = 'Mancante';
    } else {
      targaStatoSel = null;
    }
    commessaSel = (r['commessa_id'] ?? '').toString().trim().isEmpty
        ? null
        : (r['commessa_id'] ?? '').toString();
    commessaSearchCtrl = TextEditingController(
      text: widget.commesse[commessaSel ?? ''] ?? '',
    );
    _latitudine = (r['latitudine'] is num) ? (r['latitudine'] as num).toDouble() : null;
    _longitudine = (r['longitudine'] is num) ? (r['longitudine'] as num).toDouble() : null;

    _isEdit = widget.row != null;
    _baselineUbicazione = ubicazioneCtrl.text.trim();
    _baselineCommessaId = (commessaSel ?? '').trim();
    _lastCommessaLabel = _commessaLabelFor(commessaSel);
    ubicazioneCtrl.addListener(_onUbicazioneChanged);
  }

  @override
  void dispose() {
    numeroInternoCtrl.dispose();
    tipologiaCtrl.dispose();
    lunghezzaCtrl.dispose();
    larghezzaCtrl.dispose();
    altezzaCtrl.dispose();
    pesoKgCtrl.dispose();
    ingressiCtrl.dispose();
    vaniCtrl.dispose();
    acCtrl.dispose();
    matricolaCtrl.dispose();
    dataAcquistoCtrl.dispose();
    dataConsegnaCtrl.dispose();
    fornitoreCtrl.dispose();
    ordineAcquistoCtrl.dispose();
    periodoTrasferimentoCtrl.dispose();
    commessaProvenienzaCtrl.dispose();
    posizioneGpsCtrl.dispose();
    codiceCtrl.dispose();
    nomeCtrl.dispose();
    ubicazioneCtrl.dispose();
    statoCtrl.dispose();
    noteCtrl.dispose();
    commessaSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final dataAcquistoIso = parseFlexibleDateToIsoDate(dataAcquistoCtrl.text);
    final dataConsegnaIso = parseFlexibleDateToIsoDate(dataConsegnaCtrl.text);
    if (dataAcquistoCtrl.text.trim().isNotEmpty && dataAcquistoIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data acquisto non valida (usa GG/MM/AAAA).')),
      );
      return;
    }
    if (dataConsegnaCtrl.text.trim().isNotEmpty && dataConsegnaIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data consegna non valida (usa GG/MM/AAAA).')),
      );
      return;
    }
    _applyTransferFieldsOnSave();
    final gpsParsed = mdoGpsCoordsFromText(posizioneGpsCtrl.text);
    if (gpsParsed != null) {
      _latitudine = gpsParsed.$1;
      _longitudine = gpsParsed.$2;
      posizioneGpsCtrl.text = formatGpsCoordsText(gpsParsed.$1, gpsParsed.$2);
    } else if (posizioneGpsCtrl.text.trim().isEmpty) {
      _latitudine = null;
      _longitudine = null;
    }
    final payload = <String, dynamic>{
      'numero_interno': numeroInternoCtrl.text.trim().isEmpty ? null : numeroInternoCtrl.text.trim(),
      'tipologia': tipologiaCtrl.text.trim().isEmpty ? null : tipologiaCtrl.text.trim(),
      'lunghezza_cm': lunghezzaCtrl.text.trim().isEmpty ? null : lunghezzaCtrl.text.trim(),
      'larghezza_cm': larghezzaCtrl.text.trim().isEmpty ? null : larghezzaCtrl.text.trim(),
      'altezza_cm': altezzaCtrl.text.trim().isEmpty ? null : altezzaCtrl.text.trim(),
      'peso_kg': pesoKgCtrl.text.trim().isEmpty ? null : pesoKgCtrl.text.trim(),
      'ingressi': ingressiCtrl.text.trim().isEmpty ? null : ingressiCtrl.text.trim(),
      'vani': vaniCtrl.text.trim().isEmpty ? null : vaniCtrl.text.trim(),
      'ac': acCtrl.text.trim().isEmpty ? null : acCtrl.text.trim(),
      'matricola': matricolaCtrl.text.trim().isEmpty ? null : matricolaCtrl.text.trim(),
      'data_acquisto': dataAcquistoIso,
      'data_consegna': dataConsegnaIso,
      'fornitore': fornitoreCtrl.text.trim().isEmpty ? null : fornitoreCtrl.text.trim(),
      'ordine_acquisto': ordineAcquistoCtrl.text.trim().isEmpty ? null : ordineAcquistoCtrl.text.trim(),
      'periodo_trasferimento': periodoTrasferimentoCtrl.text.trim().isEmpty ? null : periodoTrasferimentoCtrl.text.trim(),
      'commessa_provenienza': commessaProvenienzaCtrl.text.trim().isEmpty ? null : commessaProvenienzaCtrl.text.trim(),
      'posizione_gps': posizioneGpsCtrl.text.trim().isEmpty ? null : posizioneGpsCtrl.text.trim(),
      'latitudine': _latitudine,
      'longitudine': _longitudine,
      'codice_box': codiceCtrl.text.trim().isEmpty ? null : codiceCtrl.text.trim(),
      'nome_box': nomeCtrl.text.trim().isEmpty ? null : nomeCtrl.text.trim(),
      'commessa_id': commessaSel,
      'ubicazione': ubicazioneCtrl.text.trim().isEmpty ? null : ubicazioneCtrl.text.trim(),
      'stato': statoCtrl.text.trim().isEmpty ? null : statoCtrl.text.trim(),
      'targa_stato': targaStatoSel,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'active': true,
    };
    final id = (widget.row?['id_uuid'] ?? '').toString();
    if (id.isEmpty) {
      await _supa.from('logistica_box').insert(payload);
    } else {
      await _supa.from('logistica_box').update(payload).eq('id_uuid', id);
    }
    final propagation =
        await propagateLogisticaBoxUpdateToLinkedAssets(_supa, payload);
    if (mounted) {
      if (propagation.totalUpdated > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              'BOX salvato. Sincronizzati ${propagation.estintoriUpdated} estintori '
              'e ${propagation.casetteUpdated} cassette P.S.',
            ),
          ),
        );
      }
      Navigator.pop(context, true);
    }
  }

  void _syncGpsFromTextField(String text) {
    final coords = mdoGpsCoordsFromText(text);
    _latitudine = coords?.$1;
    _longitudine = coords?.$2;
  }

  Future<void> _fillUbicazioneFromGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS disattivato sul dispositivo.')),
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _latitudine = pos.latitude;
        _longitudine = pos.longitude;
        posizioneGpsCtrl.text = formatGpsCoordsText(pos.latitude, pos.longitude);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore acquisizione coordinate GPS.')),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openGpsOnMap() async {
    _syncGpsFromTextField(posizioneGpsCtrl.text);
    final coords = (_latitudine != null && _longitudine != null)
        ? (_latitudine!, _longitudine!)
        : mdoGpsCoordsFromText(posizioneGpsCtrl.text);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci coordinate valide prima di aprire la mappa.')),
      );
      return;
    }
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${coords.$1},${coords.$2}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire la mappa.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final commessaItems = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo BOX' : 'Modifica BOX'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: numeroInternoCtrl,
                decoration: const InputDecoration(labelText: 'Numero interno', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tipologiaCtrl,
                decoration: const InputDecoration(labelText: 'Tipologia', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lunghezzaCtrl,
                      decoration: const InputDecoration(labelText: 'Lunghezza cm', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: larghezzaCtrl,
                      decoration: const InputDecoration(labelText: 'Larghezza cm', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: altezzaCtrl,
                      decoration: const InputDecoration(labelText: 'Altezza cm', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pesoKgCtrl,
                      decoration: const InputDecoration(labelText: 'Peso kg', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ingressiCtrl,
                      decoration: const InputDecoration(labelText: 'Ingressi', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: vaniCtrl,
                      decoration: const InputDecoration(labelText: 'Vani', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: acCtrl,
                      decoration: const InputDecoration(labelText: 'A/C', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: matricolaCtrl,
                      decoration: const InputDecoration(labelText: 'Matricola', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codiceCtrl,
                decoration: const InputDecoration(labelText: 'Codice BOX', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome BOX', border: OutlineInputBorder()),
              ),
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
                    _applyCommessaChange(opt.key);
                    commessaSearchCtrl.text = opt.value;
                  });
                },
                fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != commessaSearchCtrl.text) {
                    textCtrl.text = commessaSearchCtrl.text;
                  }
                  return TextFormField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Commessa (scrivi e seleziona)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Azzera commessa',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _applyCommessaChange(null);
                            commessaSearchCtrl.clear();
                            textCtrl.clear();
                          });
                        },
                      ),
                    ),
                    onChanged: (v) {
                      commessaSearchCtrl.text = v;
                      final exact = commessaItems
                          .where((e) => e.value.toLowerCase() == v.toLowerCase())
                          .toList();
                      setState(() {
                        if (exact.isNotEmpty) {
                          _applyCommessaChange(exact.first.key);
                        } else if (v.trim().isEmpty) {
                          _applyCommessaChange(null);
                        } else {
                          commessaSel = null;
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ubicazioneCtrl,
                decoration: const InputDecoration(labelText: 'Ubicazione', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: posizioneGpsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Coordinate GPS',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _syncGpsFromTextField(v)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _gpsLoading ? null : _fillUbicazioneFromGps,
                    icon: _gpsLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text('Rileva coordinate GPS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openGpsOnMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Apri mappa'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: statoCtrl,
                decoration: const InputDecoration(labelText: 'Stato', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: targaStatoSel,
                decoration: const InputDecoration(
                  labelText: 'Targa (Presente/Mancante)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Non specificato')),
                  DropdownMenuItem<String?>(value: 'Presente', child: Text('Presente')),
                  DropdownMenuItem<String?>(value: 'Mancante', child: Text('Mancante')),
                ],
                onChanged: (v) => setState(() => targaStatoSel = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dataAcquistoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data acquisto (GG/MM/AAAA)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: dataConsegnaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data consegna (GG/MM/AAAA)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fornitoreCtrl,
                decoration: const InputDecoration(labelText: 'Fornitore', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ordineAcquistoCtrl,
                decoration: const InputDecoration(labelText: "Ordine d'acquisto", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: periodoTrasferimentoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Periodo trasferimento',
                  hintText: 'GG/MM/AAAA — auto se cambi ubicazione o commessa',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _periodoManuallyEdited = true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commessaProvenienzaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Commessa provenienza',
                  hintText: 'Auto: commessa precedente al cambio',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _provenienzaManuallyEdited = true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
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
