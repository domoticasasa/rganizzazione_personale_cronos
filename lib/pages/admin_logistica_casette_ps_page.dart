import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:excel/excel.dart' hide Border;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deadline_nav_highlight.dart';
import '../services/logistica_box_linked_sync.dart';
import '../services/notification_sender.dart';
import '../utils/casetta_ps_materiale.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/logistica_layout.dart';
import '../utils/logistica_ubicazione_ref.dart';
import '../utils/mdo_gps_coords.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/casetta_ps_materiale_checklist.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/linked_scrollbar.dart';
import '../utils/admin_vista_guard.dart';

class AdminLogisticaCasettePsPage extends StatefulWidget {
  const AdminLogisticaCasettePsPage({super.key, this.highlightUuid});

  /// Riga da portare in cima e far lampeggiare (es. da Sedi sicurezza).
  final String? highlightUuid;

  @override
  State<AdminLogisticaCasettePsPage> createState() =>
      _AdminLogisticaCasettePsPageState();
}

class _AdminLogisticaCasettePsPageState
    extends State<AdminLogisticaCasettePsPage> with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  final TextEditingController _commessaFilterSearchCtrl =
      TextEditingController();
  bool _loading = true;
  String _search = '';
  bool _blinkOn = true;
  Timer? _blinkTimer;
  String? _commessaFilter;
  final Map<String, String> _commesse = <String, String>{};
  final Map<String, String> _utentiByUuid = <String, String>{};
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();
  final ScrollController _tableVerticalCtrl = ScrollController();
  final ScrollController _tableHorizontalCtrl = ScrollController();
  final ScrollController _mobileListCtrl = ScrollController();

  static const double _desktopHeadingH = 58;
  static const double _desktopRowH = 48;

  String _rowUuid(Map<String, dynamic> row) =>
      (row['id_uuid'] ?? '').toString().trim();

  bool _deadlineUuidAnchorsMatch(String rowUuid) {
    final t = _deadlineScrollUuid?.trim().toLowerCase();
    final r = rowUuid.trim().toLowerCase();
    return t != null && t.isNotEmpty && r.isNotEmpty && t == r;
  }

  void _jumpDeadlineControllersToTop() {
    if (_tableVerticalCtrl.hasClients) _tableVerticalCtrl.jumpTo(0);
    if (_mobileListCtrl.hasClients) _mobileListCtrl.jumpTo(0);
  }

  void _scheduleDeadlineScrollAndClearAnchor({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final compact = isLogisticaCompactLayout(context);
      final primary = compact ? _mobileListCtrl : _tableVerticalCtrl;
      if (!primary.hasClients && attempt < 8) {
        _scheduleDeadlineScrollAndClearAnchor(attempt: attempt + 1);
        return;
      }
      _jumpDeadlineControllersToTop();
      Future<void>.delayed(const Duration(milliseconds: 4000), () {
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
      _jumpDeadlineControllersToTop();
      _scheduleDeadlineScrollAndClearAnchor();
      scheduleDeadlineScrollToAnchor(_deadlineScrollAnchorKey);
    }

    if (hadFilter) {
      unawaited(
        _loadRows(consumeNavHighlight: false).then((_) => afterRowsReady()),
      );
    } else {
      afterRowsReady();
    }
  }

  void _applyPendingNavHighlight() {
    final fromWidget = (widget.highlightUuid ?? '').trim();
    if (fromWidget.isNotEmpty) {
      final armed = (DeadlineNavHighlight.peekUuid() ?? '').trim();
      if (armed.isNotEmpty &&
          armed.toLowerCase() == fromWidget.toLowerCase()) {
        maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          scheduleDeadlineFlash(fromWidget);
          _onDeadlineHighlightUuid(fromWidget);
        });
      }
      return;
    }
    maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
  }

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted || _loading) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    disposeDeadlineFlash();
    _commessaFilterSearchCtrl.dispose();
    _tableVerticalCtrl.dispose();
    _tableHorizontalCtrl.dispose();
    _mobileListCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadCommesse();
      await _loadRows(consumeNavHighlight: false);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _applyPendingNavHighlight();
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
        return MapEntry(
            (m['id_uuid'] ?? '').toString(), (m['nome'] ?? '').toString());
      }));
  }

  Future<void> _loadRows({bool consumeNavHighlight = true}) async {
    var q = _supa.from('logistica_casette_ps').select();
    if ((_commessaFilter ?? '').trim().isNotEmpty) {
      q = q.eq('commessa_id', _commessaFilter!);
    }
    final res = await q.order('codice_interno', ascending: true);
    var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final mat = casettaPsMaterialeSummary(r);
        final tokens = [
          r['id_uuid'],
          r['codice_interno'],
          r['tipo_cassetta'],
          r['n_loto'],
          r['scadenze'],
          r['ubicazione'],
          _commesse[(r['commessa_id'] ?? '').toString()],
          if (mat.totali > 0) '${mat.presenti}/${mat.totali}',
        ].map((v) => (v ?? '').toString().toLowerCase());
        return tokens.any((t) => t.contains(k));
      }).toList();
    }
    final pinId =
        (_deadlineScrollUuid ?? widget.highlightUuid ?? '').trim();
    if (pinId.isNotEmpty) pinRowByUuidToFront(list, pinId);
    if (!mounted) return;
    setState(() => _rows = list);
    if (consumeNavHighlight) {
      maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
    }
    unawaited(_loadUtentiForRows(list));
  }

  Future<void> _loadUtentiForRows(List<Map<String, dynamic>> list) async {
    final ids = <String>{};
    for (final r in list) {
      final c = (r['created_by_user_uuid'] ?? '').toString().trim();
      final u = (r['updated_by_user_uuid'] ?? '').toString().trim();
      final rr =
          (r['richiesta_sostituzione_by_user_uuid'] ?? '').toString().trim();
      if (c.isNotEmpty) ids.add(c);
      if (u.isNotEmpty) ids.add(u);
      if (rr.isNotEmpty) ids.add(rr);
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
        final id = (m['id_uuid'] ?? '').toString().trim();
        final full = (m['full_name'] ?? '').toString().trim();
        final user = (m['username'] ?? '').toString().trim();
        if (id.isNotEmpty) map[id] = full.isNotEmpty ? full : user;
      }
    }
    if (!mounted) return;
    setState(() {
      _utentiByUuid
        ..clear()
        ..addAll(map);
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
      final sheet = excel['Casette_PS'];
      sheet.appendRow([
        'Cod. interno',
        'Tipo cassetta',
        'Commessa',
        'Scadenze',
        'N. LOTO',
        'Materiale (presenti)',
        'Ubicazione',
        'Posizione GPS',
        'Richiesta sostituzione',
      ]);
      for (final r in _rows) {
        final mat = casettaPsMaterialeSummary(r);
        sheet.appendRow([
          (r['codice_interno'] ?? '').toString(),
          (r['tipo_cassetta'] ?? '').toString(),
          _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
          _fmtMonthYear(r['scadenze']),
          (r['n_loto'] ?? '').toString(),
          mat.totali > 0 ? '${mat.presenti}/${mat.totali}' : '',
          (r['ubicazione'] ?? '').toString(),
          (r['posizione_gps'] ?? '').toString(),
          (r['richiesta_sostituzione'] ?? false) == true ? 'SI' : 'NO',
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Casette_PS',
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

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CasettaPsDialog(commesse: _commesse, row: row),
    );
    if (ok == true) {
      await _loadRows();
    }
  }

  Future<void> _openMaterialeCheck(Map<String, dynamic> row) async {
    final msg = await showDialog<String?>(
      context: context,
      builder: (ctx) => _CasettaPsCheckDialog(row: row),
    );
    if (!mounted) return;
    if (msg != null && msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _loadRows();
    }
  }

  Future<void> _bulkSyncCommesseFromUbicazione() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizza da ubicazione'),
        content: const Text(
          'Allinea commessa e coordinate GPS di tutte le cassette '
          'in base a BOX, CON o MDO (Axx) in ubicazione.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sincronizza')),
        ],
      ),
    );
    if (ok != true) return;

    if (_commesse.isEmpty) {
      await _loadCommesse();
    }

    try {
      setState(() => _loading = true);
      final result = await syncAllLinkedAssetsFromUbicazioneSources(
        _supa,
        commesseById: _commesse,
      );
      await _loadRows();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: result.totalUpdated > 0
              ? Colors.green.shade700
              : Colors.orange.shade800,
          content: Text(
            'Sincronizzazione completata: ${result.estintoriUpdated} estintori, '
            '${result.casetteUpdated} cassette P.S., errori: ${result.errors}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina cassetta P.S.'),
        content: const Text('Confermi eliminazione?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('logistica_casette_ps').delete().eq('id_uuid', id);
    await _loadRows();
  }

  Future<String?> _currentUserIdUuid() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return null;
    try {
      final me = await _supa
          .from('users')
          .select('id_uuid')
          .eq('auth_id', authId!)
          .maybeSingle();
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
    final uuid =
        (row['id_uuid'] ?? '').toString().toLowerCase().replaceAll('-', '');
    if (uuid.length >= 8) {
      final hex = uuid.substring(0, 8);
      final v = int.tryParse(hex, radix: 16);
      if ((v ?? 0) > 0) return v!;
    }
    return DateTime.now().millisecondsSinceEpoch.remainder(2000000000) + 1;
  }

  Future<void> _notifyLogisticaRolesForReplacement(
      Map<String, dynamic> row) async {
    final admins =
        await _supa.from('users').select('id, role').eq('role', 'logistica');
    final ids = (admins as List)
        .map((e) => (Map<String, dynamic>.from(e as Map)['id']))
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    final code = (row['codice_interno'] ?? 'N/D').toString();
    final bid = _notificationBookingId(row);
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: bid,
      action: 'casetta_ps_replace_request',
      title: 'Richiesta sostituzione Cassetta P.S.',
      message: 'Richiesta sostituzione per cassetta $code',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<void> _toggleReplacementRequest(Map<String, dynamic> row) async {
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final requested = (row['richiesta_sostituzione'] ?? false) == true;
    try {
      final byUuid = await _currentUserIdUuid();
      await _supa.from('logistica_casette_ps').update({
        'richiesta_sostituzione': !requested,
        'richiesta_sostituzione_at':
            !requested ? DateTime.now().toUtc().toIso8601String() : null,
        'richiesta_sostituzione_by_user_uuid': !requested ? byUuid : null,
      }).eq('id_uuid', id);
      if (!requested) {
        try {
          await _notifyLogisticaRolesForReplacement(row);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifica inviata a logistica.')),
            );
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Richiesta salvata, ma notifica logistica non inviata.')),
          );
        }
      }
    } finally {
      await _loadRows();
    }
  }

  Color _replacementColor(Map<String, dynamic> row) {
    final requested = (row['richiesta_sostituzione'] ?? false) == true;
    if (!requested) return Colors.grey;
    return _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.25);
  }

  void _showReplacementAudit(Map<String, dynamic> row) {
    final byUuid =
        (row['richiesta_sostituzione_by_user_uuid'] ?? '').toString().trim();
    final byName = _utentiByUuid[byUuid] ?? byUuid;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Richiesta sostituzione'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Richiesta: ${(row['richiesta_sostituzione'] ?? false) == true ? 'SI' : 'NO'}'),
            Text('Richiesta da: ${byName.isEmpty ? '—' : byName}'),
            Text(
                'Richiesta il: ${_fmtDateTime(row['richiesta_sostituzione_at']).isEmpty ? '—' : _fmtDateTime(row['richiesta_sostituzione_at'])}'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Widget _header(String text, {Color bg = const Color(0xFFD6E4C7)}) {
    return Container(
      alignment: Alignment.center,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFC10F0F),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  static const List<double> _casColW = <double>[
    36, 220, 220, 320, 210, 120, 110, 220, 180, 86, 140,
  ];

  double get _casTableWidth =>
      _casColW.fold<double>(0, (sum, w) => sum + w);

  Widget _withAudit(Widget child, Map<String, dynamic> row, String fieldKey) {
    return wrapWithAuditHover(
      child,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  Widget _casColText(double width, String text, {TextStyle? style, int maxLines = 1}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }

  Widget _buildDesktopLazyTable() {
    if (_rows.isEmpty) {
      return const Center(child: Text('Nessuna cassetta trovata'));
    }
    const dataStyle = TextStyle(fontSize: 12, color: Colors.black87);
    final headers = <Widget>[
      _header('#'),
      _header('COD. INTERNO'),
      _header('TIPO DI CASSETTA\n(ALLEGATO 1 / ALLEGATO 2)'),
      _header('COMMESSA'),
      _header('SCADENZE', bg: const Color(0xFFB8CEA9)),
      _header('N. LOTO'),
      _header('Materiale'),
      _header('Ubicazione'),
      _header('Posizione GPS'),
      _header('Rich. Sost.'),
      _header('Azioni'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableW = _casTableWidth < constraints.maxWidth
            ? constraints.maxWidth
            : _casTableWidth;
        return LinkedScrollbar(
          controller: _tableHorizontalCtrl,
          axis: Axis.horizontal,
          child: SingleChildScrollView(
            controller: _tableHorizontalCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  SizedBox(
                    height: _desktopHeadingH,
                    child: Row(
                      children: [
                        for (var i = 0; i < headers.length; i++)
                          SizedBox(width: _casColW[i], child: headers[i]),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LinkedScrollbar(
                      controller: _tableVerticalCtrl,
                      child: ListView.builder(
                      controller: _tableVerticalCtrl,
                      itemExtent: _desktopRowH,
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final r = _rows[index];
                        final id = _rowUuid(r);
                        final flash =
                            id.isNotEmpty && deadlineFlashLit(id);
                        final matSummary = casettaPsMaterialeSummary(r);
                        return KeyedSubtree(
                          key: _deadlineUuidAnchorsMatch(id)
                              ? _deadlineScrollAnchorKey
                              : ValueKey<String>('casetta_desk_$id$index'),
                          child: Material(
                            color: flash
                                ? Colors.amber.withValues(alpha: 0.42)
                                : (index.isEven
                                    ? CronosAppThemes.cardOf(context)
                                    : CronosAppThemes.cardMutedOf(context)),
                            child: InkWell(
                              onTap: () => _openForm(row: r),
                              child: Row(
                                children: [
                                  _casColText(
                                    _casColW[0],
                                    '${index + 1}',
                                    style: dataStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[1],
                                      (r['codice_interno'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'codice_interno',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[2],
                                      (r['tipo_cassetta'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'tipo_cassetta',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[3],
                                      _commesse[(r['commessa_id'] ?? '')
                                              .toString()] ??
                                          '',
                                      style: dataStyle,
                                    ),
                                    r,
                                    'commessa_id',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[4],
                                      _fmtMonthYear(r['scadenze']),
                                      style: dataStyle.copyWith(
                                        color: _scadenzaColor(r['scadenze']),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    r,
                                    'scadenze',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[5],
                                      (r['n_loto'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'n_loto',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[6],
                                      matSummary.totali > 0
                                          ? '${matSummary.presenti}/${matSummary.totali}'
                                          : '—',
                                      style: dataStyle,
                                    ),
                                    r,
                                    'materiale_contenuto',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[7],
                                      (r['ubicazione'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'ubicazione',
                                  ),
                                  _withAudit(
                                    _casColText(
                                      _casColW[8],
                                      (r['posizione_gps'] ?? '').toString(),
                                      style: dataStyle,
                                      maxLines: 2,
                                    ),
                                    r,
                                    'posizione_gps',
                                  ),
                                  _withAudit(
                                    SizedBox(
                                      width: _casColW[9],
                                      child: Row(
                                        children: [
                                          Icon(
                                            (r['richiesta_sostituzione'] ??
                                                        false) ==
                                                    true
                                                ? Icons.notifications_active
                                                : Icons.notifications_none,
                                            size: 16,
                                            color: _replacementColor(r),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Audit richiesta sostituzione',
                                            onPressed: () =>
                                                _showReplacementAudit(r),
                                            icon: const Icon(
                                                Icons.info_outline, size: 14),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                    width: 22, height: 22),
                                          ),
                                        ],
                                      ),
                                    ),
                                    r,
                                    'richiesta_sostituzione',
                                  ),
                                  SizedBox(
                                    width: _casColW[10],
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip:
                                              'Check contenuto cassetta',
                                          onPressed: () =>
                                              _openMaterialeCheck(r),
                                          icon: const Icon(
                                            Icons.checklist_outlined,
                                            size: 18,
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 24, height: 24),
                                        ),
                                        IconButton(
                                          tooltip: (r['richiesta_sostituzione'] ??
                                                      false) ==
                                                  true
                                              ? 'Rimuovi richiesta sostituzione'
                                              : 'Richiedi sostituzione',
                                          onPressed: () =>
                                              _toggleReplacementRequest(r),
                                          icon: Icon(
                                            (r['richiesta_sostituzione'] ??
                                                        false) ==
                                                    true
                                                ? Icons.notifications_active
                                                : Icons.notifications_none,
                                            size: 18,
                                            color: _replacementColor(r),
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 24, height: 24),
                                        ),
                                        IconButton(
                                          tooltip: 'Storico',
                                          onPressed: () =>
                                              _showAuditPopup(r),
                                          icon: const Icon(Icons.history,
                                              size: 19),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 24, height: 24),
                                        ),
                                        IconButton(
                                          tooltip: 'Modifica',
                                          onPressed: () =>
                                              _openForm(row: r),
                                          icon: const Icon(
                                              Icons.edit_outlined, size: 19),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 24, height: 24),
                                        ),
                                        IconButton(
                                          tooltip: 'Elimina',
                                          onPressed: id.isEmpty
                                              ? null
                                              : () => _deleteRow(id),
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              size: 19,
                                              color: Colors.red),
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 24, height: 24),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _fmtMonthYear(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final mm = d.month.toString().padLeft(2, '0');
    return '$mm/${d.year}';
  }

  DateTime? _parseIsoDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  bool _isScadenzaScaduta(dynamic v) {
    final d = _parseIsoDate(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    return target.isBefore(today);
  }

  bool _isScadenzaIn30(dynamic v) {
    final d = _parseIsoDate(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final days = target.difference(today).inDays;
    return days >= 0 && days <= 30;
  }

  Color _scadenzaColor(dynamic v) {
    if (_isScadenzaScaduta(v)) {
      return _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.25);
    }
    if (_isScadenzaIn30(v)) {
      return Colors.orange.shade800;
    }
    return Colors.black87;
  }

  String _fmtDateTime(dynamic v) {
    final s = formatDateTimeItFromSupabase(v);
    if (s.isNotEmpty) return s;
    if (v == null) return '';
    return v.toString();
  }

  void _showAuditPopup(Map<String, dynamic> r) {
    final createdByUuid = (r['created_by_user_uuid'] ?? '').toString().trim();
    final updatedByUuid = (r['updated_by_user_uuid'] ?? '').toString().trim();
    final replacementByUuid =
        (r['richiesta_sostituzione_by_user_uuid'] ?? '').toString().trim();
    final createdBy = _utentiByUuid[createdByUuid] ?? createdByUuid;
    final updatedBy = _utentiByUuid[updatedByUuid] ?? updatedByUuid;
    final replacementBy = _utentiByUuid[replacementByUuid] ?? replacementByUuid;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dettaglio inserimento/modifica'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inserito il: ${_fmtDateTime(r['created_at'])}'),
            Text('Inserito da: ${createdBy.isEmpty ? '—' : createdBy}'),
            const SizedBox(height: 8),
            Text('Ultima modifica: ${_fmtDateTime(r['updated_at'])}'),
            Text('Modificato da: ${updatedBy.isEmpty ? '—' : updatedBy}'),
            const SizedBox(height: 8),
            Text(
                'Richiesta sostituzione: ${(r['richiesta_sostituzione'] ?? false) == true ? 'SI' : 'NO'}'),
            Text(
                'Richiesta da: ${replacementBy.isEmpty ? '—' : replacementBy}'),
            Text(
                'Richiesta il: ${_fmtDateTime(r['richiesta_sostituzione_at']).isEmpty ? '—' : _fmtDateTime(r['richiesta_sostituzione_at'])}'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Widget _buildMobileList() {
    final tableRows = _rows;
    if (tableRows.isEmpty) {
      return const Center(child: Text('Nessuna cassetta trovata'));
    }
    return ListView.separated(
      controller: _mobileListCtrl,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: tableRows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = tableRows[index];
        final id = (r['id_uuid'] ?? '').toString();
        final flash = id.isNotEmpty && deadlineFlashLit(id);
        return KeyedSubtree(
          key: _deadlineUuidAnchorsMatch(id)
              ? _deadlineScrollAnchorKey
              : ValueKey<String>('casetta_mobile_card_$id$index'),
          child: Card(
          color: flash ? Colors.amber.withValues(alpha: 0.42) : null,
          child: InkWell(
            onTap: () => _openForm(row: r),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${index + 1}. ${(r['codice_interno'] ?? '').toString()}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Tipo: ${(r['tipo_cassetta'] ?? '').toString()}'),
                  Text(
                      'Commessa: ${_commesse[(r['commessa_id'] ?? '').toString()] ?? ''}'),
                  Text(
                    'Scadenze: ${_fmtMonthYear(r['scadenze'])}',
                    style: TextStyle(
                      color: _scadenzaColor(r['scadenze']),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final nLoto = (r['n_loto'] ?? '').toString().trim();
                      if (nLoto.isEmpty) return const SizedBox.shrink();
                      return Text('N. LOTO: $nLoto');
                    },
                  ),
                  Builder(
                    builder: (_) {
                      final mat = casettaPsMaterialeSummary(r);
                      if (mat.totali == 0) return const SizedBox.shrink();
                      return Text('Materiale: ${mat.presenti}/${mat.totali} presenti');
                    },
                  ),
                  Text('Ubicazione: ${(r['ubicazione'] ?? '').toString()}'),
                  Text(
                      'Posizione GPS: ${(r['posizione_gps'] ?? '').toString()}'),
                  Text(
                    'Richiesta sostituzione: ${(r['richiesta_sostituzione'] ?? false) == true ? 'SI' : 'NO'}',
                    style: TextStyle(
                      color: _replacementColor(r),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Check contenuto cassetta',
                        onPressed: () => _openMaterialeCheck(r),
                        icon: const Icon(Icons.checklist_outlined),
                      ),
                      IconButton(
                        tooltip: 'Richiesta sostituzione',
                        onPressed: () => _toggleReplacementRequest(r),
                        icon: Icon(
                          (r['richiesta_sostituzione'] ?? false) == true
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          color: _replacementColor(r),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dettaglio richiesta sostituzione',
                        onPressed: () => _showReplacementAudit(r),
                        icon: const Icon(Icons.info_outline),
                      ),
                      IconButton(
                        tooltip: 'Storico',
                        onPressed: () => _showAuditPopup(r),
                        icon: const Icon(Icons.history),
                      ),
                      IconButton(
                        tooltip: 'Modifica',
                        onPressed: () => _openForm(row: r),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Elimina',
                        onPressed: id.isEmpty ? null : () => _deleteRow(id),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
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
        title: const ResponsiveAppBarTitle(title: 'Logistica - Cassette P.S.'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Nuova cassetta',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Sincronizza commessa/posizione da ubicazione',
            onPressed: _bulkSyncCommesseFromUbicazione,
            icon: const Icon(Icons.sync_alt),
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
            : Column(
                children: [
                  if (_rows
                      .where(
                          (e) => (e['richiesta_sostituzione'] ?? false) == true)
                      .isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _blinkOn
                            ? Colors.red.withValues(alpha: 0.12)
                            : Colors.red.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.55)),
                      ),
                      child: Text(
                        'ATTENZIONE: richieste sostituzione aperte: ${_rows.where((e) => (e['richiesta_sostituzione'] ?? false) == true).length}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFEDED00),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Text(
                      'ELENCO GENERALE - CASSETTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
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
                              labelText:
                                  'Cerca codice, tipo, scadenze, ubicazione...',
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
                          width: logisticaFieldWidth(context, desktop: 300),
                          child: Autocomplete<MapEntry<String, String>>(
                            initialValue: TextEditingValue(
                                text: _commessaFilterSearchCtrl.text),
                            optionsBuilder: (textEditingValue) {
                              final q =
                                  textEditingValue.text.trim().toLowerCase();
                              if (q.isEmpty) return commessaItems;
                              return commessaItems.where(
                                  (e) => e.value.toLowerCase().contains(q));
                            },
                            displayStringForOption: (opt) => opt.value,
                            onSelected: (opt) async {
                              _commessaFilterSearchCtrl.text = opt.value;
                              setState(() => _commessaFilter = opt.key);
                              await _loadRows();
                            },
                            fieldViewBuilder: (context, textCtrl, focusNode,
                                onFieldSubmitted) {
                              if (textCtrl.text !=
                                  _commessaFilterSearchCtrl.text) {
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
                                      e.value.toLowerCase() ==
                                      textCtrl.text.trim().toLowerCase());
                                  setState(() => _commessaFilter =
                                      exact.isNotEmpty
                                          ? exact.first.key
                                          : null);
                                  await _loadRows();
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: isMobileLayout
                        ? _buildMobileList()
                        : _buildDesktopLazyTable(),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CasettaPsDialog extends StatefulWidget {
  final Map<String, String> commesse;
  final Map<String, dynamic>? row;
  const _CasettaPsDialog({required this.commesse, this.row});

  @override
  State<_CasettaPsDialog> createState() => _CasettaPsDialogState();
}

class _CasettaPsDialogState extends State<_CasettaPsDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController codiceCtrl;
  late final TextEditingController scadenzeCtrl;
  late final TextEditingController nLotoCtrl;
  late final TextEditingController ubicazioneCtrl;
  late final TextEditingController posizioneGpsCtrl;
  late final TextEditingController commessaSearchCtrl;
  String? commessaSel;
  String? tipoSel;
  bool _gpsLoading = false;
  double? _latitudine;
  double? _longitudine;
  List<String> _ubicazioneOptions = <String>[];

  static const List<String> _tipiCasetta = [
    'ALLEGATO 1 (piu di 3 lavoratori)',
    'ALLEGATO 2 (fino a 3 lavoratori)',
  ];

  String _formatMonthYearFromDb(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final mm = d.month.toString().padLeft(2, '0');
    return '$mm/${d.year}';
  }

  String? _parseMonthYearToIso(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{2})\/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final mm = int.tryParse(m.group(1)!);
    final yyyy = int.tryParse(m.group(2)!);
    if (mm == null || yyyy == null || mm < 1 || mm > 12) return null;
    return '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-01';
  }

  String _extractUbicazioneRef(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    if (s.contains('-')) s = s.split('-').first.trim();
    s = s.split(RegExp(r'\s+')).first.trim();
    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _isAutoCommessaRef(String ref) {
    return RegExp(r'^(BOX|CON|A)\d+$', caseSensitive: false).hasMatch(ref);
  }

  String _normalizeLookupKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String? _findCommessaIdByText(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;
    final target = _normalizeLookupKey(raw);
    if (target.isEmpty) return null;

    String? containsMatch;
    for (final entry in widget.commesse.entries) {
      final normalizedName = _normalizeLookupKey(entry.value);
      if (normalizedName.isEmpty) continue;
      if (normalizedName == target) return entry.key;
      if (normalizedName.contains(target) || target.contains(normalizedName)) {
        containsMatch ??= entry.key;
      }
    }
    if (containsMatch != null) return containsMatch;
    return null;
  }

  Future<({String? commessaId, String source})>
      _resolveAutoCommessaFromUbicazione(String ubicazioneRaw) async {
    final ref = _extractUbicazioneRef(ubicazioneRaw);
    if (!_isAutoCommessaRef(ref)) return (commessaId: null, source: '');

    try {
      final boxRes = await _supa
          .from('logistica_box')
          .select('numero_interno,codice_box,nome_box,commessa_id,active')
          .eq('active', true);
      for (final e in (boxRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final commessaId = (m['commessa_id'] ?? '').toString().trim();
        if (commessaId.isEmpty) continue;
        final num =
            _extractUbicazioneRef((m['numero_interno'] ?? '').toString());
        final code = _extractUbicazioneRef((m['codice_box'] ?? '').toString());
        final name = _extractUbicazioneRef((m['nome_box'] ?? '').toString());
        if (ref == num || ref == code || ref == name) {
          return (commessaId: commessaId, source: 'BOX $ref');
        }
      }

      final mdoRes = await _supa
          .from('logistica_mdo_ferroviari')
          .select(
              'matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,active')
          .eq('active', true);
      for (final e in (mdoRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final mat =
            _extractUbicazioneRef((m['matricola_interna'] ?? '').toString());
        final desc =
            _extractUbicazioneRef((m['descrizione_mezzo'] ?? '').toString());
        if (ref != mat && ref != desc) continue;
        final commessaRaw = (m['commessa'] ?? '').toString().trim();
        final byCommessa = _findCommessaIdByText(commessaRaw);
        if (byCommessa != null) {
          return (commessaId: byCommessa, source: 'MDO $ref (campo commessa)');
        }
        final cantiereRaw = (m['cantiere_attuale'] ?? '').toString().trim();
        final byCantiere = _findCommessaIdByText(cantiereRaw);
        if (byCantiere != null) {
          return (commessaId: byCantiere, source: 'MDO $ref (cantiere)');
        }
      }
    } catch (_) {
      return (commessaId: null, source: '');
    }

    return (commessaId: null, source: '');
  }

  Future<void> _applyUbicazioneSyncFromUbicazione(String ubicazioneRaw) async {
    if (!isUbicazioneLinkedRef(_extractUbicazioneRef(ubicazioneRaw))) return;
    final merged = await mergeUbicazioneSyncIntoPayload(
      _supa,
      ubicazioneRaw,
      <String, dynamic>{},
      commesseById: widget.commesse,
    );
    if (!mounted || merged.isEmpty) return;
    setState(() {
      final commessaId = (merged['commessa_id'] ?? '').toString();
      if (commessaId.isNotEmpty) {
        commessaSel = commessaId;
        commessaSearchCtrl.text =
            widget.commesse[commessaId] ?? commessaSearchCtrl.text;
      }
      posizioneGpsCtrl.text = (merged['posizione_gps'] ?? '').toString();
      _latitudine = merged['latitudine'] as double?;
      _longitudine = merged['longitudine'] as double?;
    });
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? <String, dynamic>{};
    codiceCtrl =
        TextEditingController(text: (r['codice_interno'] ?? '').toString());
    final rawTipo = (r['tipo_cassetta'] ?? '').toString().trim().toUpperCase();
    if (rawTipo.contains('ALL1') || rawTipo.contains('ALLEGATO 1')) {
      tipoSel = _tipiCasetta[0];
    } else if (rawTipo.contains('ALL2') || rawTipo.contains('ALLEGATO 2')) {
      tipoSel = _tipiCasetta[1];
    } else {
      tipoSel = null;
    }
    scadenzeCtrl =
        TextEditingController(text: _formatMonthYearFromDb(r['scadenze']));
    nLotoCtrl = TextEditingController(text: (r['n_loto'] ?? '').toString());
    ubicazioneCtrl =
        TextEditingController(text: (r['ubicazione'] ?? '').toString());
    posizioneGpsCtrl =
        TextEditingController(text: (r['posizione_gps'] ?? '').toString());
    commessaSel = (r['commessa_id'] ?? '').toString().trim().isEmpty
        ? null
        : (r['commessa_id'] ?? '').toString();
    commessaSearchCtrl =
        TextEditingController(text: widget.commesse[commessaSel ?? ''] ?? '');
    _latitudine =
        (r['latitudine'] is num) ? (r['latitudine'] as num).toDouble() : null;
    _longitudine =
        (r['longitudine'] is num) ? (r['longitudine'] as num).toDouble() : null;
    _loadUbicazioneOptions();
  }

  @override
  void dispose() {
    codiceCtrl.dispose();
    scadenzeCtrl.dispose();
    nLotoCtrl.dispose();
    ubicazioneCtrl.dispose();
    posizioneGpsCtrl.dispose();
    commessaSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUbicazioneOptions() async {
    try {
      final boxRes = await _supa
          .from('logistica_box')
          .select('numero_interno,codice_box,nome_box,ubicazione,active')
          .eq('active', true)
          .order('numero_interno', ascending: true);
      final mdoRes = await _supa
          .from('logistica_mdo_ferroviari')
          .select('matricola_interna,descrizione_mezzo,cantiere_attuale,active')
          .eq('active', true)
          .order('matricola_interna', ascending: true);
      final mezziRes = await _supa
          .from('logistica_mezzi_stradali')
          .select('targa,marca,modello,assegnatario_attuale,active')
          .eq('active', true)
          .order('targa', ascending: true);
      final set = <String>{};
      for (final e in (boxRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final num = (m['numero_interno'] ?? '').toString().trim();
        final code = (m['codice_box'] ?? '').toString().trim();
        final name = (m['nome_box'] ?? '').toString().trim();
        final loc = (m['ubicazione'] ?? '').toString().trim();
        final id = num.isNotEmpty ? num : (code.isNotEmpty ? code : name);
        if (id.isEmpty) continue;
        final label = loc.isEmpty ? id : '$id - $loc';
        set.add(label);
      }
      for (final e in (mdoRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final mat = (m['matricola_interna'] ?? '').toString().trim();
        final desc = (m['descrizione_mezzo'] ?? '').toString().trim();
        final yard = (m['cantiere_attuale'] ?? '').toString().trim();
        final id = mat.isNotEmpty ? mat : desc;
        if (id.isEmpty) continue;
        final label = yard.isEmpty ? id : '$id - $yard';
        set.add(label);
      }
      for (final e in (mezziRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final targa = (m['targa'] ?? '').toString().trim();
        final marca = (m['marca'] ?? '').toString().trim();
        final modello = (m['modello'] ?? '').toString().trim();
        final assegnatario =
            (m['assegnatario_attuale'] ?? '').toString().trim();
        if (targa.isEmpty) continue;
        final desc = [marca, modello].where((v) => v.isNotEmpty).join(' ');
        final parts = <String>[targa];
        if (desc.isNotEmpty) parts.add(desc);
        if (assegnatario.isNotEmpty) parts.add(assegnatario);
        set.add(parts.join(' - '));
      }
      final options = set.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() => _ubicazioneOptions = options);
    } catch (_) {}
  }

  (double, double)? _extractCoords(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll('GPS:', '').trim();
    final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)')
        .firstMatch(cleaned);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  Future<void> _fillPosizioneFromGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'GPS disattivato: attiva la posizione sul dispositivo.')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
      setState(() {
        posizioneGpsCtrl.text = 'GPS: $lat, $lon';
        _latitudine = pos.latitude;
        _longitudine = pos.longitude;
      });
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<(double, double)?> _resolveCasettaMapCoords(
    Map<String, dynamic> row,
  ) async {
    final own = mdoGpsCoordsFromRow(row);
    if (own != null) return own;

    final ubicazione = (row['ubicazione'] ?? '').toString().trim();
    if (ubicazione.isEmpty) return null;

    try {
      final boxRes = await _supa
          .from('logistica_box')
          .select(
            'numero_interno, codice_box, nome_box, latitudine, longitudine, '
            'posizione_gps, active',
          )
          .eq('active', true);
      final mdoRes = await _supa
          .from('logistica_mdo_ferroviari')
          .select(
            'matricola_interna, descrizione_mezzo, latitudine, longitudine, '
            'posizione_gps, active',
          )
          .eq('active', true);
      final boxLookup = boxGpsLookupFromRows(
        (boxRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final mdoLookup = mdoGpsLookupFromRows(
        (mdoRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return casettaPsGpsCoords(row, boxLookup, mdoGpsByRef: mdoLookup);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openGpsOnMap() async {
    final own = (_latitudine != null && _longitudine != null)
        ? (_latitudine!, _longitudine!)
        : _extractCoords(posizioneGpsCtrl.text);
    final coords = own ??
        await _resolveCasettaMapCoords({
          'ubicazione': ubicazioneCtrl.text.trim(),
          'latitudine': _latitudine,
          'longitudine': _longitudine,
          'posizione_gps': posizioneGpsCtrl.text.trim(),
        });
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nessuna coordinata GPS: inseriscile sulla cassetta o sul BOX/MDO in ubicazione.',
          ),
        ),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final scadenzaIso = _parseMonthYearToIso(scadenzeCtrl.text);
    if (scadenzeCtrl.text.trim().isNotEmpty && scadenzaIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Formato Scadenze non valido (usa MM/AAAA).')),
      );
      return;
    }
    final ubicazioneText = ubicazioneCtrl.text.trim();
    final ubicazioneRef = _extractUbicazioneRef(ubicazioneText);
    final isLinkedUbicazione = isUbicazioneLinkedRef(ubicazioneRef);
    final hasAutoRef = _isAutoCommessaRef(ubicazioneRef);
    final autoResolved =
        await _resolveAutoCommessaFromUbicazione(ubicazioneText);
    final autoCommessaId = autoResolved.commessaId;
    final effectiveCommessaId = autoCommessaId ?? commessaSel;

    var payload = <String, dynamic>{
      'codice_interno':
          codiceCtrl.text.trim().isEmpty ? null : codiceCtrl.text.trim(),
      'tipo_cassetta': (tipoSel ?? '').trim().isEmpty ? null : tipoSel,
      'commessa_id': effectiveCommessaId,
      'scadenze': scadenzaIso,
      'n_loto': nLotoCtrl.text.trim().isEmpty ? null : nLotoCtrl.text.trim(),
      'ubicazione': ubicazioneCtrl.text.trim().isEmpty
          ? null
          : ubicazioneCtrl.text.trim(),
      'posizione_gps': posizioneGpsCtrl.text.trim().isEmpty
          ? null
          : posizioneGpsCtrl.text.trim(),
      'latitudine': _latitudine,
      'longitudine': _longitudine,
      'active': true,
    };
    if (isLinkedUbicazione) {
      payload = await mergeUbicazioneSyncIntoPayload(
        _supa,
        ubicazioneText,
        payload,
        commesseById: widget.commesse,
      );
    }
    final id = (widget.row?['id_uuid'] ?? '').toString();
    if (id.isEmpty) {
      await _supa.from('logistica_casette_ps').insert(payload);
    } else {
      await _supa
          .from('logistica_casette_ps')
          .update(payload)
          .eq('id_uuid', id);
    }
    if (isLinkedUbicazione && mounted) {
      final syncedCommessaId = (payload['commessa_id'] ?? '').toString();
      if (syncedCommessaId.isNotEmpty) {
        setState(() {
          commessaSel = syncedCommessaId;
          commessaSearchCtrl.text =
              widget.commesse[syncedCommessaId] ?? commessaSearchCtrl.text;
        });
      }
      final commessaName =
          widget.commesse[syncedCommessaId] ?? syncedCommessaId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            'Sincronizzato da $ubicazioneRef: commessa $commessaName, posizione GPS.',
          ),
        ),
      );
    } else if (autoCommessaId != null && mounted) {
      setState(() {
        commessaSel = autoCommessaId;
        commessaSearchCtrl.text =
            widget.commesse[autoCommessaId] ?? commessaSearchCtrl.text;
      });
      final commessaName = widget.commesse[autoCommessaId] ?? autoCommessaId;
      final sourceLabel =
          autoResolved.source.isEmpty ? 'ubicazione' : autoResolved.source;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('Commessa auto da $sourceLabel: $commessaName'),
        ),
      );
    } else if (hasAutoRef && !isLinkedUbicazione && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content:
              Text('Nessuna commessa trovata per ubicazione $ubicazioneRef'),
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final commessaItems = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: Text(
          widget.row == null ? 'Nuova cassetta P.S.' : 'Modifica cassetta P.S.'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: codiceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Codice interno',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: tipoSel,
                decoration: const InputDecoration(
                  labelText: 'Tipo di cassetta',
                  border: OutlineInputBorder(),
                ),
                items: _tipiCasetta
                    .map((t) =>
                        DropdownMenuItem<String>(value: t, child: Text(t)))
                    .toList(growable: false),
                onChanged: (v) => setState(() => tipoSel = v),
              ),
              const SizedBox(height: 8),
              Autocomplete<MapEntry<String, String>>(
                initialValue: TextEditingValue(text: commessaSearchCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return commessaItems;
                  return commessaItems
                      .where((e) => e.value.toLowerCase().contains(q));
                },
                displayStringForOption: (opt) => opt.value,
                onSelected: (opt) {
                  setState(() {
                    commessaSel = opt.key;
                    commessaSearchCtrl.text = opt.value;
                  });
                },
                fieldViewBuilder:
                    (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != commessaSearchCtrl.text) {
                    textCtrl.text = commessaSearchCtrl.text;
                  }
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
                      final exact = commessaItems
                          .where((e) => e.value == v)
                          .toList(growable: false);
                      setState(() => commessaSel =
                          exact.isNotEmpty ? exact.first.key : null);
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: scadenzeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenze (MM/AAAA)',
                  hintText: 'es. 06/2026',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nLotoCtrl,
                decoration: const InputDecoration(
                  labelText: 'N. LOTO',
                  hintText: 'Numero lotto cassetta / contenuto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: ubicazioneCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return _ubicazioneOptions;
                  return _ubicazioneOptions
                      .where((o) => o.toLowerCase().contains(q));
                },
                onSelected: (opt) {
                  ubicazioneCtrl.text = opt;
                  _applyUbicazioneSyncFromUbicazione(opt);
                },
                fieldViewBuilder:
                    (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != ubicazioneCtrl.text) {
                    textCtrl.text = ubicazioneCtrl.text;
                  }
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Ubicazione (BOX / MDO / Targa o manuale)',
                      hintText: 'Scrivi per cercare o inserisci manualmente',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Azzera ubicazione',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          textCtrl.clear();
                          ubicazioneCtrl.clear();
                        },
                      ),
                    ),
                    onChanged: (v) => ubicazioneCtrl.text = v,
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: posizioneGpsCtrl,
                decoration: InputDecoration(
                  labelText: 'Posizione GPS',
                  border: const OutlineInputBorder(),
                  suffixIcon: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rileva coordinate GPS',
                          onPressed: _gpsLoading ? null : _fillPosizioneFromGps,
                          icon: _gpsLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location),
                        ),
                        IconButton(
                          tooltip: 'Apri su mappa',
                          onPressed: _openGpsOnMap,
                          icon: const Icon(Icons.map_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                onChanged: (v) {
                  final coords = _extractCoords(v);
                  if (coords != null) {
                    _latitudine = coords.$1;
                    _longitudine = coords.$2;
                  } else if (!v.trim().toUpperCase().startsWith('GPS:')) {
                    _latitudine = null;
                    _longitudine = null;
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla')),
        AsyncFilledButton(onPressed: _save, child: const Text('Salva')),
      ],
    );
  }
}

/// Check contenuto minimo (Allegato 1 / 2) — separato dalla modifica anagrafica.
class _CasettaPsCheckDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  const _CasettaPsCheckDialog({required this.row});

  @override
  State<_CasettaPsCheckDialog> createState() => _CasettaPsCheckDialogState();
}

class _CasettaPsCheckDialogState extends State<_CasettaPsCheckDialog> {
  final _supa = Supabase.instance.client;
  late String? tipoSel;
  late List<CasettaPsMaterialeRiga> _materialeRighe;

  static const List<String> _tipiCasetta = [
    'ALLEGATO 1 (piu di 3 lavoratori)',
    'ALLEGATO 2 (fino a 3 lavoratori)',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    final rawTipo = (r['tipo_cassetta'] ?? '').toString().trim().toUpperCase();
    if (rawTipo.contains('ALL1') || rawTipo.contains('ALLEGATO 1')) {
      tipoSel = _tipiCasetta[0];
    } else if (rawTipo.contains('ALL2') || rawTipo.contains('ALLEGATO 2')) {
      tipoSel = _tipiCasetta[1];
    } else {
      tipoSel = null;
    }
    _materialeRighe = mergeCasettaPsMateriale(
      tipoCassetta: tipoSel,
      stored: r['materiale_contenuto'],
    );
  }

  void _onTipoChanged(String? v) {
    setState(() {
      tipoSel = v;
      _materialeRighe = mergeCasettaPsMateriale(
        tipoCassetta: tipoSel,
        stored: casettaPsMaterialeToJsonList(_materialeRighe),
      );
    });
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    if (tipoSel == null || tipoSel!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona il tipo di cassetta (Allegato 1 o 2).'),
        ),
      );
      return;
    }
    for (final r in _materialeRighe) {
      if (r.scadenzaMmYyyy.trim().isEmpty) continue;
      if (CasettaPsMaterialeRiga.scadenzaMmYyyyToIso(r.scadenzaMmYyyy) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scadenza non valida per «${r.descrizione}» (usa MM/AAAA).',
            ),
          ),
        );
        return;
      }
    }

    final id = (widget.row['id_uuid'] ?? '').toString();
    if (id.isEmpty) return;

    final payload = <String, dynamic>{
      'tipo_cassetta': tipoSel,
      'materiale_contenuto': casettaPsMaterialeToJsonList(_materialeRighe),
      'data_ultimo_check_materiale': supabaseNowIsoUtc(),
    };
    final earliest = earliestMaterialeScadenzaIso(_materialeRighe);
    if (earliest != null) {
      payload['scadenze'] = earliest;
    }

    await _supa.from('logistica_casette_ps').update(payload).eq('id_uuid', id);
    if (mounted) {
      Navigator.pop<String?>(
        context,
        'Check contenuto cassetta salvato.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final codice = (widget.row['codice_interno'] ?? '').toString();
    final nLoto = (widget.row['n_loto'] ?? '').toString();
    return AlertDialog(
      title: const Text('Check contenuto cassetta P.S.'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (codice.isNotEmpty)
                Text(
                  'Cassetta: $codice',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              if (nLoto.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'N. LOTO: $nLoto',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: tipoSel,
                decoration: const InputDecoration(
                  labelText: 'Tipo di cassetta',
                  border: OutlineInputBorder(),
                ),
                items: _tipiCasetta
                    .map((t) =>
                        DropdownMenuItem<String>(value: t, child: Text(t)))
                    .toList(growable: false),
                onChanged: _onTipoChanged,
              ),
              const SizedBox(height: 12),
              CasettaPsMaterialeChecklist(
                righe: _materialeRighe,
                onChanged: (righe) => setState(() => _materialeRighe = righe),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<String?>(context),
          child: const Text('Annulla'),
        ),
        AsyncFilledButton(onPressed: _save, child: const Text('Salva check')),
      ],
    );
  }
}
