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
import '../utils/date_formatters.dart';
import '../utils/logistica_ubicazione_ref.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/responsive.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/linked_scrollbar.dart';

enum _EstintoriOrdineRighe { scadenze, codice }

class AdminEstintoriPage extends StatefulWidget {
  const AdminEstintoriPage({super.key, this.highlightUuid});

  /// Riga da portare in cima e far lampeggiare (es. da Sedi sicurezza).
  final String? highlightUuid;

  @override
  State<AdminEstintoriPage> createState() => _AdminEstintoriPageState();
}

class _AdminEstintoriPageState extends State<AdminEstintoriPage>
    with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  bool _blinkOn = true;
  Timer? _blinkTimer;

  String? _commessaFilter;
  _EstintoriOrdineRighe _ordineRighe = _EstintoriOrdineRighe.scadenze;
  final Map<String, String> _commesse = <String, String>{};
  final Map<String, String> _utentiByUuid = <String, String>{};
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _expandedMobileId;
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();
  final ScrollController _desktopVerticalCtrl = ScrollController();
  final ScrollController _mobileListCtrl = ScrollController();
  final ScrollController _desktopHorizontalCtrl = ScrollController();

  String _rowUuid(Map<String, dynamic> row) =>
      (row['id_uuid'] ?? '').toString().trim();

  bool _deadlineUuidAnchorsMatch(String rowUuid) {
    final t = _deadlineScrollUuid?.trim().toLowerCase();
    final r = rowUuid.trim().toLowerCase();
    return t != null && t.isNotEmpty && r.isNotEmpty && t == r;
  }

  void _jumpDeadlineControllersToTop() {
    if (_desktopVerticalCtrl.hasClients) _desktopVerticalCtrl.jumpTo(0);
    if (_mobileListCtrl.hasClients) _mobileListCtrl.jumpTo(0);
  }

  void _scheduleDeadlineScrollAndClearAnchor({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final compact = useCompactPageLayout(context);
      final primary = compact ? _mobileListCtrl : _desktopVerticalCtrl;
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
    _desktopVerticalCtrl.dispose();
    _desktopHorizontalCtrl.dispose();
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
          (m['id_uuid'] ?? '').toString(),
          (m['nome'] ?? '').toString(),
        );
      }));
  }

  Future<void> _loadRows({bool consumeNavHighlight = true}) async {
    var q = _supa.from('estintori').select();
    if ((_commessaFilter ?? '').trim().isNotEmpty) {
      q = q.eq('commessa_id', _commessaFilter!);
    }
    final res = await q.order('codice_interno');
    var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final tokens = [
          r['id_uuid'],
          r['codice_interno'],
          r['numero_estintore'],
          r['matricola'],
          r['ubicazione'],
          r['posizione_gps'],
          r['tipo'],
          r['carica_kg_l'],
          r['anno_produzione'],
          r['potere_estinguente'],
          _commesse[(r['commessa_id'] ?? '').toString()],
        ].map((v) => (v ?? '').toString().toLowerCase());
        return tokens.any((t) => t.contains(k));
      }).toList();
    }
    _ordinaRighe(list);
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
      final res = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .inFilter('id_uuid', ids.toList());
      for (final e in (res as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString();
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
      final sheet = excel['Estintori'];
      sheet.appendRow([
        'Cod. interno',
        'Tipologia',
        'Numero',
        'Matricola',
        'Ubicazione',
        'Posizione GPS',
        'Carica KG/L',
        'Anno produzione',
        'Potere estinguente',
        'Scadenza controllo semestrale',
        'Scadenza revisione',
        'Scadenza collaudo',
        'Scadenza omologazione',
        'Richiesta sostituzione',
        'Commessa',
        'Note',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          (r['codice_interno'] ?? '').toString(),
          (r['tipo'] ?? '').toString(),
          (r['numero_estintore'] ?? '').toString(),
          (r['matricola'] ?? '').toString(),
          (r['ubicazione'] ?? '').toString(),
          (r['posizione_gps'] ?? '').toString(),
          (r['carica_kg_l'] ?? '').toString(),
          (r['anno_produzione'] ?? '').toString(),
          (r['potere_estinguente'] ?? '').toString(),
          _fmtMonthYear(r['prossimo_controllo']),
          _fmtMonthYear(r['prossima_revisione']),
          _fmtMonthYear(r['prossimo_collaudo']),
          _fmtMonthYear(r['scadenza_omologazione']),
          (r['richiesta_sostituzione'] ?? false) == true ? 'SI' : 'NO',
          _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
          (r['note'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Estintori',
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

  Future<void> _deleteRow(String idUuid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina estintore'),
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
    await _supa.from('estintori').delete().eq('id_uuid', idUuid);
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
    final code =
        (row['codice_interno'] ?? row['numero_estintore'] ?? 'N/D').toString();
    final bid = _notificationBookingId(row);
    await NotificationSender.sendToUserIds(
      userIds: ids,
      bookingId: bid,
      action: 'estintore_replace_request',
      title: 'Richiesta sostituzione estintore',
      message: 'Richiesta sostituzione per estintore $code',
      actorIdUuid: await _currentUserIdUuid(),
    );
  }

  Future<void> _toggleReplacementRequest(Map<String, dynamic> row) async {
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final requested = (row['richiesta_sostituzione'] ?? false) == true;
    try {
      final byUuid = await _currentUserIdUuid();
      await _supa.from('estintori').update({
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

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _EstintoreDialog(commesse: _commesse, row: row),
    );
    if (result == true) await _loadRows();
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

  static const List<String> _campiScadenza = <String>[
    'prossimo_controllo',
    'prossima_revisione',
    'prossimo_collaudo',
    'scadenza_omologazione',
  ];

  DateTime? _scadenzaPiuUrgente(Map<String, dynamic> r) {
    DateTime? min;
    for (final f in _campiScadenza) {
      final d = _parseIsoDate(r[f]);
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (min == null || day.isBefore(min)) min = day;
    }
    return min;
  }

  /// Giorni alla scadenza più vicina (negativo = già scaduto).
  int? _giorniAllaScadenza(Map<String, dynamic> r) {
    final target = _scadenzaPiuUrgente(r);
    if (target == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return target.difference(today).inDays;
  }

  int _compareCodice(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ca = (a['codice_interno'] ?? '').toString().toLowerCase();
    final cb = (b['codice_interno'] ?? '').toString().toLowerCase();
    return ca.compareTo(cb);
  }

  void _ordinaRighe(List<Map<String, dynamic>> list) {
    if (_ordineRighe == _EstintoriOrdineRighe.codice) {
      list.sort(_compareCodice);
      return;
    }
    list.sort((a, b) {
      final sostA = (a['richiesta_sostituzione'] ?? false) == true;
      final sostB = (b['richiesta_sostituzione'] ?? false) == true;
      if (sostA != sostB) return sostA ? -1 : 1;

      final ga = _giorniAllaScadenza(a);
      final gb = _giorniAllaScadenza(b);
      if (ga == null && gb == null) return _compareCodice(a, b);
      if (ga == null) return 1;
      if (gb == null) return -1;
      if (ga != gb) return ga.compareTo(gb);

      return _compareCodice(a, b);
    });
  }

  bool _isControlloScaduto(dynamic v) {
    final d = _parseIsoDate(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    return target.isBefore(today);
  }

  bool _isControlloInScadenza30(dynamic v) {
    final d = _parseIsoDate(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final days = target.difference(today).inDays;
    return days >= 0 && days <= 30;
  }

  Color _controlloTextColor(dynamic v) {
    if (_isControlloScaduto(v)) {
      return _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.25);
    }
    if (_isControlloInScadenza30(v)) {
      return Colors.orange.shade800;
    }
    return Colors.black87;
  }

  Future<(double, double)?> _resolveEstintoreMapCoords(
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
      return estintoreGpsCoords(row, boxLookup, mdoGpsByRef: mdoLookup);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCoordsOnMap(Map<String, dynamic> row) async {
    final coords = await _resolveEstintoreMapCoords(row);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nessuna coordinata GPS: inseriscile sull\'estintore o sul BOX/MDO in ubicazione.',
          ),
        ),
      );
      return;
    }
    final (mapLat, mapLon) = coords;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$mapLat,$mapLon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _header(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9B1C1C),
        ),
      );

  static const double _desktopHeadingH = 28;
  static const double _desktopRowH = 38;
  static const List<double> _estColW = <double>[
    36, 78, 124, 52, 70, 130, 104, 54, 50, 50, 80, 62, 62, 62, 72, 145, 130, 148,
  ];

  double get _estTableWidth =>
      _estColW.fold<double>(0, (sum, w) => sum + w);

  Widget _withAudit(Widget child, Map<String, dynamic> row, String fieldKey) {
    return wrapWithAuditHover(
      child,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  Widget _estColText(
    double width,
    String text, {
    TextStyle? style,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.left,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  Widget _buildDesktopLazyTable() {
    if (_rows.isEmpty) {
      return const Center(child: Text('Nessun estintore trovato'));
    }
    const headingBg = Color(0xFFE3E3E3);
    const dataStyle = TextStyle(fontSize: 11, color: Colors.black87);
    final headers = <Widget>[
      _header('#'),
      _header('COD INTERNO'),
      _header('TIPOLOGIA'),
      _header('NUMERO'),
      _header('MATRICOLA'),
      _header('UBICAZIONE'),
      _header('POSIZIONE'),
      _header('CARICA KG/L'),
      _header('ANNO DI'),
      _header('POTERE'),
      _header('SCAD. CONTR. SEM.'),
      _header('SCAD. REVISIONE'),
      _header('SCAD. COLLAUDO'),
      _header('SCAD. OMOLOGAZ.'),
      _header('RICH. SOST.'),
      _header('COMMESSA'),
      _header('NOTE'),
      _header('AZIONI'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableW = _estTableWidth < constraints.maxWidth
            ? constraints.maxWidth
            : _estTableWidth;
        return LinkedScrollbar(
          controller: _desktopHorizontalCtrl,
          axis: Axis.horizontal,
          child: SingleChildScrollView(
            controller: _desktopHorizontalCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Container(
                    height: _desktopHeadingH,
                    color: headingBg,
                    child: Row(
                      children: [
                        for (var i = 0; i < headers.length; i++)
                          SizedBox(
                            width: _estColW[i],
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: headers[i],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LinkedScrollbar(
                      controller: _desktopVerticalCtrl,
                      child: ListView.builder(
                      controller: _desktopVerticalCtrl,
                      itemExtent: _desktopRowH,
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final r = _rows[index];
                        final id = _rowUuid(r);
                        final flash =
                            id.isNotEmpty && deadlineFlashLit(id);
                        return KeyedSubtree(
                          key: _deadlineUuidAnchorsMatch(id)
                              ? _deadlineScrollAnchorKey
                              : ValueKey<String>('estintore_desk_$id$index'),
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
                                  _estColText(
                                    _estColW[0],
                                    '${index + 1}',
                                    style: dataStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[1],
                                      (r['codice_interno'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'codice_interno',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[2],
                                      (r['tipo'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'tipo',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[3],
                                      (r['numero_estintore'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'numero_estintore',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[4],
                                      (r['matricola'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'matricola',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[5],
                                      (r['ubicazione'] ?? '').toString(),
                                      style: dataStyle,
                                      maxLines: 2,
                                    ),
                                    r,
                                    'ubicazione',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[6],
                                      (r['posizione_gps'] ?? '').toString(),
                                      style: dataStyle,
                                      maxLines: 2,
                                    ),
                                    r,
                                    'posizione_gps',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[7],
                                      (r['carica_kg_l'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'carica_kg_l',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[8],
                                      (r['anno_produzione'] ?? '').toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'anno_produzione',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[9],
                                      (r['potere_estinguente'] ?? '')
                                          .toString(),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'potere_estinguente',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[10],
                                      _fmtMonthYear(r['prossimo_controllo']),
                                      style: dataStyle.copyWith(
                                        color: _controlloTextColor(
                                            r['prossimo_controllo']),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    r,
                                    'prossimo_controllo',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[11],
                                      _fmtMonthYear(r['prossima_revisione']),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'prossima_revisione',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[12],
                                      _fmtMonthYear(r['prossimo_collaudo']),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'prossimo_collaudo',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[13],
                                      _fmtMonthYear(
                                          r['scadenza_omologazione']),
                                      style: dataStyle,
                                    ),
                                    r,
                                    'scadenza_omologazione',
                                  ),
                                  _withAudit(
                                    SizedBox(
                                      width: _estColW[14],
                                      child: Row(
                                        children: [
                                          Icon(
                                            (r['richiesta_sostituzione'] ??
                                                        false) ==
                                                    true
                                                ? Icons.notifications_active
                                                : Icons.notifications_none,
                                            size: 18,
                                            color: _replacementColor(r),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Audit richiesta sostituzione',
                                            icon: const Icon(
                                                Icons.info_outline,
                                                size: 14),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                    width: 22, height: 22),
                                            onPressed: () =>
                                                _showReplacementAudit(r),
                                          ),
                                        ],
                                      ),
                                    ),
                                    r,
                                    'richiesta_sostituzione',
                                  ),
                                  _withAudit(
                                    _estColText(
                                      _estColW[15],
                                      _commesse[(r['commessa_id'] ?? '')
                                              .toString()] ??
                                          '',
                                      style: dataStyle,
                                      maxLines: 2,
                                    ),
                                    r,
                                    'commessa_id',
                                  ),
                                  _withAudit(
                                    SizedBox(
                                      width: _estColW[16],
                                      child: NotePreviewText(
                                        note: (r['note'] ?? '').toString(),
                                        maxChars: 10,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    r,
                                    'note',
                                  ),
                                  SizedBox(
                                    width: _estColW[17],
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: (r['richiesta_sostituzione'] ??
                                                      false) ==
                                                  true
                                              ? 'Rimuovi richiesta sostituzione'
                                              : 'Richiedi sostituzione',
                                          icon: Icon(
                                            (r['richiesta_sostituzione'] ??
                                                        false) ==
                                                    true
                                                ? Icons.notifications_active
                                                : Icons.notifications_none,
                                            color: _replacementColor(r),
                                          ),
                                          iconSize: 18,
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 22, height: 22),
                                          onPressed: () =>
                                              _toggleReplacementRequest(r),
                                        ),
                                        IconButton(
                                          tooltip: 'Apri mappa',
                                          icon: const Icon(
                                              Icons.map_outlined, size: 19),
                                          iconSize: 18,
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 22, height: 22),
                                          onPressed: () =>
                                              _openCoordsOnMap(r),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Storico inserimento/modifica',
                                          icon: const Icon(Icons.history,
                                              size: 19),
                                          iconSize: 18,
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 22, height: 22),
                                          onPressed: () =>
                                              _showAuditPopup(r),
                                        ),
                                        IconButton(
                                          tooltip: 'Modifica',
                                          icon: const Icon(
                                              Icons.edit_outlined),
                                          iconSize: 18,
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 22, height: 22),
                                          onPressed: () =>
                                              _openForm(row: r),
                                        ),
                                        IconButton(
                                          tooltip: 'Elimina',
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red),
                                          iconSize: 18,
                                          visualDensity:
                                              VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  width: 22, height: 22),
                                          onPressed: id.isEmpty
                                              ? null
                                              : () => _deleteRow(id),
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
  String _fmtDateTime(dynamic v) {
    final s = formatDateTimeItFromSupabase(v);
    if (s.isNotEmpty) return s;
    if (v == null) return '';
    return v.toString();
  }

  void _showAuditPopup(Map<String, dynamic> r) {
    final createdByUuid = (r['created_by_user_uuid'] ?? '').toString().trim();
    final updatedByUuid = (r['updated_by_user_uuid'] ?? '').toString().trim();
    final createdBy = _utentiByUuid[createdByUuid] ?? createdByUuid;
    final updatedBy = _utentiByUuid[updatedByUuid] ?? updatedByUuid;
    final createdAt = (r['created_at'] ?? '').toString();
    final updatedAt = (r['updated_at'] ?? '').toString();
    final replacementByUuid =
        (r['richiesta_sostituzione_by_user_uuid'] ?? '').toString().trim();
    final replacementBy = _utentiByUuid[replacementByUuid] ?? replacementByUuid;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dettaglio inserimento/modifica'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inserito il: ${_fmtDateTime(createdAt)}'),
            Text('Inserito da: ${createdBy.isEmpty ? '—' : createdBy}'),
            const SizedBox(height: 8),
            Text('Ultima modifica: ${_fmtDateTime(updatedAt)}'),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Widget _mobileInfo(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileList() {
    final tableRows = _rows;
    if (tableRows.isEmpty) {
      return const Center(child: Text('Nessun estintore trovato'));
    }
    return ListView.separated(
      controller: _mobileListCtrl,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: tableRows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = tableRows[index];
        final id = (r['id_uuid'] ?? '').toString();
        final tileKey = id.isEmpty ? 'row_$index' : id;
        final isExpanded = _expandedMobileId == tileKey;
        final flash = id.isNotEmpty && deadlineFlashLit(id);
        return KeyedSubtree(
          key: _deadlineUuidAnchorsMatch(id)
              ? _deadlineScrollAnchorKey
              : ValueKey<String>('estintore_mobile_card_$tileKey'),
          child: Card(
          margin: EdgeInsets.zero,
          color: flash ? Colors.amber.withValues(alpha: 0.42) : null,
          child: ExpansionTile(
            key: PageStorageKey<String>('estintore_mobile_$tileKey'),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _expandedMobileId = expanded ? tileKey : null;
              });
            },
            title: Text(
              '${index + 1}. ${(r['matricola'] ?? '').toString().trim().isEmpty ? 'Matricola: —' : 'Matricola: ${(r['matricola'] ?? '').toString()}'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text((r['tipo'] ?? 'Estintore').toString()),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            children: [
              _mobileInfo('Codice', (r['codice_interno'] ?? '').toString()),
              _mobileInfo('Numero', (r['numero_estintore'] ?? '').toString()),
              _mobileInfo('Ubicazione', (r['ubicazione'] ?? '').toString()),
              _mobileInfo('Posizione', (r['posizione_gps'] ?? '').toString()),
              Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Rich. sostituzione',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      (r['richiesta_sostituzione'] ?? false) == true
                          ? 'SI'
                          : 'NO',
                      style: TextStyle(
                        color: _replacementColor(r),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              _mobileInfo('Carica KG/L', (r['carica_kg_l'] ?? '').toString()),
              Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Scad. controllo',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtMonthYear(r['prossimo_controllo']).isEmpty
                          ? '—'
                          : _fmtMonthYear(r['prossimo_controllo']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _controlloTextColor(r['prossimo_controllo']),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              _mobileInfo(
                  'Scad. revisione', _fmtMonthYear(r['prossima_revisione'])),
              _mobileInfo(
                  'Scad. collaudo', _fmtMonthYear(r['prossimo_collaudo'])),
              _mobileInfo('Scad. omologazione',
                  _fmtMonthYear(r['scadenza_omologazione'])),
              _mobileInfo(
                'Commessa',
                _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Richiesta sostituzione',
                    icon: Icon(
                      (r['richiesta_sostituzione'] ?? false) == true
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      size: 20,
                      color: _replacementColor(r),
                    ),
                    onPressed: () => _toggleReplacementRequest(r),
                  ),
                  IconButton(
                    tooltip: 'Dettaglio richiesta sostituzione',
                    icon: const Icon(Icons.info_outline, size: 20),
                    onPressed: () => _showReplacementAudit(r),
                  ),
                  IconButton(
                    tooltip: 'Apri mappa',
                    icon: const Icon(Icons.map_outlined, size: 20),
                    onPressed: () => _openCoordsOnMap(r),
                  ),
                  IconButton(
                    tooltip: 'Storico',
                    icon: const Icon(Icons.history, size: 20),
                    onPressed: () => _showAuditPopup(r),
                  ),
                  IconButton(
                    tooltip: 'Modifica',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _openForm(row: r),
                  ),
                  IconButton(
                    tooltip: 'Elimina',
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    onPressed: id.isEmpty ? null : () => _deleteRow(id),
                  ),
                ],
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Future<void> _bulkSyncCommesseFromUbicazione() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizza da ubicazione'),
        content: const Text(
          'Allinea commessa e coordinate GPS di tutti gli estintori '
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

  @override
  Widget build(BuildContext context) {
    final commessaItems = _commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final isMobileLayout = useCompactPageLayout(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Admin Estintori'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportExcel,
          ),
          IconButton(
            tooltip: 'Nuovo estintore',
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(),
          ),
          IconButton(
            tooltip: 'Sincronizza commessa/posizione da ubicazione',
            icon: const Icon(Icons.sync_alt),
            onPressed: _bulkSyncCommesseFromUbicazione,
          ),
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRows,
          ),
          const SizedBox(width: 8),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: isMobileLayout
                              ? cronosFullFieldWidth(context)
                              : 320,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText:
                                  'Cerca (codice, numero, matricola, ubicazione...)',
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
                          width: isMobileLayout
                              ? cronosFullFieldWidth(context)
                              : 280,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            isDense: true,
                            initialValue: _commessaFilter,
                            decoration: const InputDecoration(
                              labelText: 'Commessa',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'Tutte',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...commessaItems
                                  .map((e) => DropdownMenuItem<String>(
                                        value: e.key,
                                        child: Text(
                                          e.value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                            ],
                            onChanged: (v) async {
                              setState(() => _commessaFilter = v);
                              await _loadRows();
                            },
                          ),
                        ),
                        FilterChip(
                          label: Text(
                            _ordineRighe == _EstintoriOrdineRighe.scadenze
                                ? 'Ordine: scadenze'
                                : 'Ordine: codice',
                          ),
                          selected:
                              _ordineRighe == _EstintoriOrdineRighe.scadenze,
                          onSelected: (sel) {
                            setState(() {
                              _ordineRighe = sel
                                  ? _EstintoriOrdineRighe.scadenze
                                  : _EstintoriOrdineRighe.codice;
                            });
                            _loadRows();
                          },
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

class _EstintoreDialog extends StatefulWidget {
  final Map<String, String> commesse;
  final Map<String, dynamic>? row;
  const _EstintoreDialog({required this.commesse, this.row});

  @override
  State<_EstintoreDialog> createState() => _EstintoreDialogState();
}

class _EstintoreDialogState extends State<_EstintoreDialog> {
  final _supa = Supabase.instance.client;
  final _form = GlobalKey<FormState>();

  late final TextEditingController codiceCtrl;
  late final TextEditingController matricolaCtrl;
  late final TextEditingController numeroCtrl;
  late final TextEditingController ubicazioneCtrl;
  late final TextEditingController posizioneGpsCtrl;
  late final TextEditingController caricaCtrl;
  late final TextEditingController annoCtrl;
  late final TextEditingController potereCtrl;
  late final TextEditingController noteCtrl;
  late final TextEditingController commessaSearchCtrl;
  late final TextEditingController prossimoControlloCtrl;
  late final TextEditingController prossimaRevisioneCtrl;
  late final TextEditingController prossimoCollaudoCtrl;
  late final TextEditingController scadenzaOmologazioneCtrl;

  String? commessaSel;
  String? tipoSel;
  bool _gpsLoading = false;
  double? _latitudine;
  double? _longitudine;
  List<String> _ubicazioneOptions = <String>[];

  static const List<String> _tipologieEstintore = [
    'Estintori a Polvere (ABC)',
    'Estintori CO2',
    'Estintori a Schiuma',
    'Estintori Idrici',
    'Estintori a Idrocarburi Alogenati',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? <String, dynamic>{};
    codiceCtrl =
        TextEditingController(text: (r['codice_interno'] ?? '').toString());
    numeroCtrl =
        TextEditingController(text: (r['numero_estintore'] ?? '').toString());
    matricolaCtrl =
        TextEditingController(text: (r['matricola'] ?? '').toString());
    ubicazioneCtrl =
        TextEditingController(text: (r['ubicazione'] ?? '').toString());
    posizioneGpsCtrl =
        TextEditingController(text: (r['posizione_gps'] ?? '').toString());
    caricaCtrl =
        TextEditingController(text: (r['carica_kg_l'] ?? '').toString());
    annoCtrl =
        TextEditingController(text: (r['anno_produzione'] ?? '').toString());
    potereCtrl =
        TextEditingController(text: (r['potere_estinguente'] ?? '').toString());
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
    commessaSel = (r['commessa_id'] ?? '').toString().trim().isEmpty
        ? null
        : (r['commessa_id'] ?? '').toString();
    final selectedCommessaName = widget.commesse[commessaSel ?? ''] ?? '';
    commessaSearchCtrl = TextEditingController(text: selectedCommessaName);
    final rawTipo = (r['tipo'] ?? '').toString().trim();
    tipoSel = _tipologieEstintore.contains(rawTipo) ? rawTipo : null;
    prossimoControlloCtrl = TextEditingController(
        text: _formatMonthYearFromDb(r['prossimo_controllo']));
    prossimaRevisioneCtrl = TextEditingController(
        text: _formatMonthYearFromDb(r['prossima_revisione']));
    prossimoCollaudoCtrl = TextEditingController(
        text: _formatMonthYearFromDb(r['prossimo_collaudo']));
    scadenzaOmologazioneCtrl = TextEditingController(
        text: _formatMonthYearFromDb(r['scadenza_omologazione']));
    _latitudine =
        (r['latitudine'] is num) ? (r['latitudine'] as num).toDouble() : null;
    _longitudine =
        (r['longitudine'] is num) ? (r['longitudine'] as num).toDouble() : null;
    _loadUbicazioneOptions();
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
    } catch (_) {
      // Non blocchiamo il form: resta possibile inserire ubicazione manuale.
    }
  }

  String _formatMonthYearFromDb(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
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

  String? _parseMonthYearOrYearToIso(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final monthYear = RegExp(r'^(\d{2})\/(\d{4})$').firstMatch(s);
    if (monthYear != null) {
      final mm = int.tryParse(monthYear.group(1)!);
      final yyyy = int.tryParse(monthYear.group(2)!);
      if (mm == null || yyyy == null || mm < 1 || mm > 12) return null;
      return '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-01';
    }
    final m = RegExp(r'^(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final yyyy = int.tryParse(m.group(1)!);
    if (yyyy == null) return null;
    return '${yyyy.toString().padLeft(4, '0')}-01-01';
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

    final firstToken = raw.split(RegExp(r'[\s\-/]+')).first.trim();
    if (firstToken.isEmpty) return null;
    final token = _normalizeLookupKey(firstToken);
    if (token.isEmpty) return null;
    for (final entry in widget.commesse.entries) {
      final normalizedName = _normalizeLookupKey(entry.value);
      if (normalizedName.startsWith(token) || normalizedName.contains(token)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<({String? commessaId, String source})> _resolveAutoCommessaWithSource(
      String ubicazioneRaw) async {
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
        final commessaRaw =
            (m['commessa'] ?? '').toString().trim().toLowerCase();
        if (commessaRaw.isNotEmpty) {
          final byCommessaField = _findCommessaIdByText(commessaRaw);
          if (byCommessaField != null) {
            return (
              commessaId: byCommessaField,
              source: 'MDO $ref (campo commessa)'
            );
          }
        }
        final cantiere =
            (m['cantiere_attuale'] ?? '').toString().trim().toLowerCase();
        if (cantiere.isEmpty) return (commessaId: null, source: '');
        final byCantiere = _findCommessaIdByText(cantiere);
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
  void dispose() {
    codiceCtrl.dispose();
    matricolaCtrl.dispose();
    numeroCtrl.dispose();
    ubicazioneCtrl.dispose();
    posizioneGpsCtrl.dispose();
    caricaCtrl.dispose();
    annoCtrl.dispose();
    potereCtrl.dispose();
    noteCtrl.dispose();
    commessaSearchCtrl.dispose();
    prossimoControlloCtrl.dispose();
    prossimaRevisioneCtrl.dispose();
    prossimoCollaudoCtrl.dispose();
    scadenzaOmologazioneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final controlloIso = _parseMonthYearToIso(prossimoControlloCtrl.text);
    final revisioneIso = _parseMonthYearOrYearToIso(prossimaRevisioneCtrl.text);
    final collaudoIso = _parseMonthYearOrYearToIso(prossimoCollaudoCtrl.text);
    final omologazioneIso =
        _parseMonthYearOrYearToIso(scadenzaOmologazioneCtrl.text);

    if (prossimoControlloCtrl.text.trim().isNotEmpty && controlloIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Formato Scadenza controllo semestrale non valido (usa MM/AAAA).')),
      );
      return;
    }
    if (prossimaRevisioneCtrl.text.trim().isNotEmpty && revisioneIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Formato Prossima revisione non valido (usa MM/AAAA).')),
      );
      return;
    }
    if (prossimoCollaudoCtrl.text.trim().isNotEmpty && collaudoIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Formato Prossimo collaudo non valido (usa MM/AAAA).')),
      );
      return;
    }
    if (scadenzaOmologazioneCtrl.text.trim().isNotEmpty &&
        omologazioneIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Formato Scadenza omologazione non valido (usa MM/AAAA).')),
      );
      return;
    }

    final ubicazioneText = ubicazioneCtrl.text.trim();
    final ubicazioneRef = _extractUbicazioneRef(ubicazioneText);
    final isLinkedUbicazione = isUbicazioneLinkedRef(ubicazioneRef);
    final hasAutoRef = _isAutoCommessaRef(ubicazioneRef);
    final autoResolved =
        await _resolveAutoCommessaWithSource(ubicazioneText);
    final autoCommessaId = autoResolved.commessaId;
    final effectiveCommessaId = autoCommessaId ?? commessaSel;

    var payload = <String, dynamic>{
      'codice_interno':
          codiceCtrl.text.trim().isEmpty ? null : codiceCtrl.text.trim(),
      'numero_estintore':
          numeroCtrl.text.trim().isEmpty ? null : numeroCtrl.text.trim(),
      'matricola':
          matricolaCtrl.text.trim().isEmpty ? null : matricolaCtrl.text.trim(),
      'ubicazione': ubicazioneCtrl.text.trim().isEmpty
          ? null
          : ubicazioneCtrl.text.trim(),
      'posizione_gps': posizioneGpsCtrl.text.trim().isEmpty
          ? null
          : posizioneGpsCtrl.text.trim(),
      'tipo': (tipoSel ?? '').trim().isEmpty ? null : tipoSel,
      'carica_kg_l':
          caricaCtrl.text.trim().isEmpty ? null : caricaCtrl.text.trim(),
      'anno_produzione':
          annoCtrl.text.trim().isEmpty ? null : annoCtrl.text.trim(),
      'potere_estinguente':
          potereCtrl.text.trim().isEmpty ? null : potereCtrl.text.trim(),
      'prossimo_controllo': controlloIso,
      'prossima_revisione': revisioneIso,
      'prossimo_collaudo': collaudoIso,
      'scadenza_omologazione': omologazioneIso,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'commessa_id': effectiveCommessaId,
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
      await _supa.from('estintori').insert(payload);
    } else {
      await _supa.from('estintori').update(payload).eq('id_uuid', id);
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

  Future<void> _fillUbicazioneFromGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('GPS disattivato: attiva la posizione sul telefono.')),
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile leggere coordinate GPS.')),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
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

  Future<void> _openGpsOnMap() async {
    final coords = (_latitudine != null && _longitudine != null)
        ? (_latitudine!, _longitudine!)
        : _extractCoords(posizioneGpsCtrl.text);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Nessuna coordinata GPS valida nel campo ubicazione.')),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final commessaItems = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title:
          Text(widget.row == null ? 'Nuovo estintore' : 'Modifica estintore'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: codiceCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Codice interno',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: matricolaCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Matricola', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: numeroCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Numero estintore',
                      border: OutlineInputBorder()),
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
                    return TextFormField(
                      controller: textCtrl,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Commessa (cerca e seleziona)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Azzera commessa',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              commessaSel = null;
                              commessaSearchCtrl.clear();
                              textCtrl.clear();
                            });
                          },
                        ),
                      ),
                      onChanged: (v) {
                        commessaSearchCtrl.text = v;
                        final exact =
                            commessaItems.where((e) => e.value == v).toList();
                        setState(() {
                          commessaSel =
                              exact.isNotEmpty ? exact.first.key : null;
                        });
                      },
                    );
                  },
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
                    return TextFormField(
                      controller: textCtrl,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Ubicazione (BOX / MDO / Targa o manuale)',
                        hintText:
                            'Scrivi per cercare, oppure inserisci manualmente',
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
                TextFormField(
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
                            tooltip: 'Prendi coordinate GPS',
                            onPressed:
                                _gpsLoading ? null : _fillUbicazioneFromGps,
                            icon: _gpsLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
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
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: tipoSel,
                  decoration: const InputDecoration(
                    labelText: 'Tipologia estintore',
                    border: OutlineInputBorder(),
                  ),
                  items: _tipologieEstintore
                      .map((t) =>
                          DropdownMenuItem<String>(value: t, child: Text(t)))
                      .toList(growable: false),
                  onChanged: (v) => setState(() => tipoSel = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: caricaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Carica KG/L',
                    hintText: 'es. 6 Kg o 5 L',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: annoCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Anno di produzione',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: potereCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Potere estinguente',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: prossimoControlloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Scadenza controllo semestrale (MM/AAAA)',
                    hintText: 'es. 04/2026',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: prossimaRevisioneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prossima revisione (MM/AAAA)',
                    hintText: 'es. 11/2026',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: prossimoCollaudoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prossimo collaudo (MM/AAAA)',
                    hintText: 'es. 11/2033',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: scadenzaOmologazioneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Scadenza omologazione (MM/AAAA)',
                    hintText: 'es. 11/2041',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Note', border: OutlineInputBorder()),
                ),
              ],
            ),
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
