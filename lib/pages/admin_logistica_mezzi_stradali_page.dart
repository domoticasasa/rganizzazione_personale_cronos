import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/confirm_sound_service.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/mezzi_km_service.dart';
import '../utils/date_formatters.dart';
import '../utils/field_timestamps.dart';
import '../utils/excel_export_helper.dart';
import '../services/logistica_asset_storico_service.dart';
import '../utils/logistica_layout.dart';
import '../utils/logistica_multicard_mezzo_sync.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../utils/viaggi_mezzi_qr_export.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/logistica_assignee_giustificativi_confirm_dialog.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';
import 'employee_mezzi_stradali_page.dart';

class _AssegnatarioOption {
  final String label;
  final String assignedName;
  final String? userUuid;
  const _AssegnatarioOption({
    required this.label,
    required this.assignedName,
    this.userUuid,
  });
}

class AdminLogisticaMezziStradaliPage extends StatelessWidget {
  final bool dipendenteMode;
  final bool forceMobileLayout;

  const AdminLogisticaMezziStradaliPage({
    super.key,
    this.dipendenteMode = false,
    this.forceMobileLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    if (dipendenteMode) {
      return EmployeeMezziStradaliPage(
        forceMobileLayout: forceMobileLayout,
      );
    }
    return _AdminLogisticaMezziStradaliPage(
      forceMobileLayout: forceMobileLayout,
    );
  }
}

class _AdminLogisticaMezziStradaliPage extends StatefulWidget {
  final bool forceMobileLayout;

  const _AdminLogisticaMezziStradaliPage({
    this.forceMobileLayout = false,
  });

  @override
  State<_AdminLogisticaMezziStradaliPage> createState() =>
      _AdminLogisticaMezziStradaliPageState();
}

class _AdminLogisticaMezziStradaliPageState
    extends State<_AdminLogisticaMezziStradaliPage> with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  final ScrollController _desktopHorizontalCtrl = ScrollController();
  final ScrollController _desktopVerticalCtrl = ScrollController();
  bool _loading = true;
  bool _compactView = true;
  String _search = '';
  Timer? _searchDebounce;
  final Set<String> _expandedMobileRowIds = <String>{};
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Map<String, String> _utentiByUuid = <String, String>{};
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
    setState(() => _deadlineScrollUuid = trimmed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleDeadlineScrollToAnchor(_deadlineScrollAnchorKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deadlineScrollUuid = null);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    disposeDeadlineFlash();
    _searchDebounce?.cancel();
    _desktopHorizontalCtrl.dispose();
    _desktopVerticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadRows();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _showKmColumn(BuildContext context) {
    if (_loading) return false;
    return true;
  }

  String _formatKmDisplay(int km) {
    final negative = km < 0;
    var n = km.abs();
    final parts = <String>[];
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    final body = parts.join('.');
    return negative ? '-$body' : body;
  }

  String _kmAttualiLabel(Map<String, dynamic> row) =>
      MezziKmService.kmAttualiLabel(row, formatKm: _formatKmDisplay);

  String _kmUltimoAggLabel(Map<String, dynamic> row) =>
      MezziKmService.kmUltimoAggiornamentoLabel(row);

  String _mezzoLabel(Map<String, dynamic> row) => mezzoLabelFromParts(
        targa: (row['targa'] ?? '').toString(),
        marca: (row['marca'] ?? '').toString(),
        modello: (row['modello'] ?? '').toString(),
      );

  Future<void> _showViaggioQrDialog(Map<String, dynamic> row) async {
    await showViaggiMezziQrExportDialog(
      context: context,
      client: _supa,
      mezzoIdUuid: (row['id_uuid'] ?? '').toString(),
      mezzoLabel: _mezzoLabel(row),
    );
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    final res = await _supa
        .from('logistica_mezzi_stradali')
        .select()
        .order('numerazione', ascending: true);
    var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    try {
      final cardRes = await _supa
          .from('logistica_multicard')
          .select('multicard,mezzo_targa');
      applyGestioneMulticardOntoMezziRows(
        mezzi: list,
        multicardRows: List<Map<String, dynamic>>.from(
          (cardRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
        ),
      );
      } catch (_) {}
      if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final fields = [
          r['numerazione'],
          r['targa'],
          r['marca'],
          r['modello'],
          r['tipologia_mezzo'],
          r['assegnatario_attuale'],
          r['noleggiatore'],
          r['multicard'],
          r['deposito_gomme'],
          r['note'],
        ].map((v) => (v ?? '').toString().toLowerCase());
        return fields.any((f) => f.contains(k));
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
      try {
        final users = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', ids.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString();
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          if (id.isNotEmpty) userMap[id] = full.isNotEmpty ? full : user;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _rows = list;
      _utentiByUuid
        ..clear()
        ..addAll(userMap);
      if (showLoader) _loading = false;
    });
    maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
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

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadRows(showLoader: false);
    });
  }

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  Future<void> _exportExcel() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ModifyFeedback.hint(context, 'Nessun dato da esportare');
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Mezzi_Stradali'];
      sheet.appendRow([
        'Numerazione',
        'Targa',
        'Marca',
        'Modello',
        'Tipologia mezzo',
        'Assegnatario',
        'Periodo assegnatario',
        'Noleggiatore',
        'Scadenza contratto',
        'Scadenza assicurazione',
        'Scadenza bolli',
        'Scadenza revisione',
        'Scadenza verifica periodica gru',
        'Scadenza revisione biennale cronotachigrafo',
        'Multicard',
        'Telepass',
        'Kit ruota di scorta',
        'Deposito gomme',
        'Km attuali',
        'Ultimo agg. km',
        'Note',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          (r['numerazione'] ?? '').toString(),
          (r['targa'] ?? '').toString(),
          (r['marca'] ?? '').toString(),
          (r['modello'] ?? '').toString(),
          (r['tipologia_mezzo'] ?? '').toString(),
          (r['assegnatario_attuale'] ?? '').toString(),
          _fmtDate(r['periodo_assegnatario_attuale']),
          (r['noleggiatore'] ?? '').toString(),
          _fmtDate(r['scadenza_contratto']),
          _fmtDate(r['scadenza_assicurazione']),
          _fmtDate(r['scadenza_bolli']),
          _fmtDate(r['scadenza_revisione']),
          _fmtDate(r['scadenza_verifica_periodica_gru']),
          _fmtDate(r['scadenza_revisione_biennale_cronotachigrafo']),
          (r['multicard'] ?? '').toString(),
          (r['telepass'] ?? '').toString(),
          (r['kit_ruota_di_scorta'] ?? '').toString(),
          (r['deposito_gomme'] ?? '').toString(),
          MezziKmService.kmAttualiLabel(r, formatKm: _formatKmDisplay),
          _kmUltimoAggLabel(r),
          (r['note'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Mezzi_Stradali',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ModifyFeedback.success(
        context,
        p.isEmpty ? 'Export Excel completato.' : 'Export Excel completato.\n$p',
      );
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    }
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MezzoDialog(row: row),
    );
    if (ok != true || !mounted) return;

    ModifyFeedback.success(
      context,
      row == null ? 'Mezzo salvato.' : 'Mezzo aggiornato.',
    );
    unawaited(ConfirmSoundService.play());

    try {
      await _loadRows(showLoader: false);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(
          context,
          'Mezzo salvato, ma errore nel ricaricamento elenco: $e',
        );
      }
    }
  }

  Future<void> _openGommeForm(Map<String, dynamic> row) async {
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _GommeDialog(row: row),
    );
    if (ok != true || !mounted) return;

    ModifyFeedback.success(context, 'Dati gomme aggiornati.');
    unawaited(ConfirmSoundService.play());

    try {
      await _loadRows(showLoader: false);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(
          context,
          'Dati salvati, ma errore nel ricaricamento elenco: $e',
        );
      }
    }
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina mezzo'),
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
    await _supa.from('logistica_mezzi_stradali').delete().eq('id_uuid', id);
    await _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout =
        isLogisticaCompactLayout(context, force: widget.forceMobileLayout);
    final showKm = _showKmColumn(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Logistica - Mezzi Stradali',
        ),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Nuovo mezzo',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: () => _loadRows(),
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
                          width: 360,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText:
                                  'Cerca targa, modello, assegnatario...',
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
                            final assegnatarioLabel =
                                (r['assegnatario_attuale'] ?? '')
                                    .toString()
                                    .trim();
                            final showKmRow = showKm;
                            final detailsExpanded =
                                _expandedMobileRowIds.contains(rowKey);
                            final flash = id.isNotEmpty && deadlineFlashLit(id);
                            return KeyedSubtree(
                              key: _deadlineUuidAnchorsMatch(id)
                                  ? _deadlineScrollAnchorKey
                                  : ValueKey<String>('mezzi_mobile_$rowKey'),
                              child: Card(
                                margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: flash
                                        ? Colors.amber
                                        : Colors.transparent,
                                    width: flash ? 3 : 0,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () => _openForm(row: r),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (r['targa'] ?? '').toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (assegnatarioLabel.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            assegnatarioLabel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                            '${(r['marca'] ?? '').toString()} ${(r['modello'] ?? '').toString()}'),
                                        if (showKmRow) ...[
                                          Text(
                                            'Km attuali: ${_kmAttualiLabel(r)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Ultimo agg.: ${_kmUltimoAggLabel(r)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ],
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 0),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            minimumSize: const Size(0, 32),
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              if (detailsExpanded) {
                                                _expandedMobileRowIds
                                                    .remove(rowKey);
                                              } else {
                                                _expandedMobileRowIds
                                                    .add(rowKey);
                                              }
                                            });
                                          },
                                          icon: Icon(
                                            detailsExpanded
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down,
                                          ),
                                          label: Text(detailsExpanded
                                              ? 'Nascondi dettagli'
                                              : 'Mostra dettagli'),
                                        ),
                                        if (detailsExpanded) ...[
                                          Text(
                                              'N: ${(r['numerazione'] ?? '').toString()}'),
                                          Text(
                                              'Tipologia mezzo: ${(r['tipologia_mezzo'] ?? '').toString()}'),
                                          Text(
                                              'Periodo assegnatario: ${_fmtDate(r['periodo_assegnatario_attuale'])}'),
                                          Text(
                                              'Noleggiatore: ${(r['noleggiatore'] ?? '').toString()}'),
                                          Text(
                                              'Scad. contratto: ${_fmtDate(r['scadenza_contratto'])}'),
                                          Text(
                                              'Scad. assicurazione: ${_fmtDate(r['scadenza_assicurazione'])}'),
                                          Text(
                                              'Scad. bolli: ${_fmtDate(r['scadenza_bolli'])}'),
                                          Text(
                                              'Scad. revisione: ${_fmtDate(r['scadenza_revisione'])}'),
                                          Text(
                                              'Scad. verifica gru: ${_fmtDate(r['scadenza_verifica_periodica_gru'])}'),
                                          Text(
                                              'Scad. cronotachigrafo: ${_fmtDate(r['scadenza_revisione_biennale_cronotachigrafo'])}'),
                                          Text(
                                              'Multicard: ${(r['multicard'] ?? '').toString()}'),
                                          Text(
                                              'Telepass: ${(r['telepass'] ?? '').toString()}'),
                                        ],
                                        Text(
                                            'Kit ruota: ${(r['kit_ruota_di_scorta'] ?? '').toString()}'),
                                        Text(
                                            'Deposito gomme: ${(r['deposito_gomme'] ?? '').toString()}'),
                                        if ((r['note'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                              'Note: ${(r['note'] ?? '').toString()}'),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.tonalIcon(
                                              onPressed: () =>
                                                  _openForm(row: r),
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18),
                                              label: const Text('Modifica'),
                                            ),
                                            if (id.isNotEmpty)
                                              FilledButton.tonalIcon(
                                                onPressed: () =>
                                                    _showViaggioQrDialog(r),
                                                icon: const Icon(
                                                    Icons.qr_code_2_outlined,
                                                    size: 18),
                                                label: const Text('QR viaggio'),
                                              ),
                                            if (id.isNotEmpty)
                                              FilledButton.tonalIcon(
                                                onPressed: () =>
                                                    _openGommeForm(r),
                                                icon: const Icon(
                                                    Icons.location_on_outlined,
                                                    size: 18),
                                                label: const Text(
                                                    'Modifica gomme'),
                                              ),
                                            FilledButton.tonalIcon(
                                              onPressed: id.isEmpty
                                                  ? null
                                                  : () => _deleteRow(id),
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18),
                                              label: const Text('Elimina'),
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
                                  labelText:
                                      'Cerca targa, modello, assegnatario...',
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
                                    icon: Icon(Icons.view_week_outlined,
                                        size: 16),
                                  ),
                                  ButtonSegment<bool>(
                                    value: false,
                                    label: Text('Completa'),
                                    icon: Icon(Icons.table_rows_outlined,
                                        size: 16),
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
                          minWidth: _compactView ? 1860 : 3000,
                          fixedTopRows: 1,
                          fixedLeftColumns: 2,
                          scrollController: _desktopVerticalCtrl,
                          horizontalScrollController: _desktopHorizontalCtrl,
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: true,
                          columnSpacing: _compactView ? 12 : 8,
                          horizontalMargin: _compactView ? 10 : 10,
                          columns: [
                            const DataColumn(
                                label: SizedBox(width: 42, child: Text('N'))),
                            const DataColumn(
                                label:
                                    SizedBox(width: 90, child: Text('Targa'))),
                            const DataColumn(
                                label:
                                    SizedBox(width: 95, child: Text('Marca'))),
                            const DataColumn(
                                label: SizedBox(
                                    width: 180, child: Text('Modello'))),
                            const DataColumn(label: Text('Tipologia mezzo')),
                            const DataColumn(label: Text('Assegnatario')),
                            if (!_compactView)
                              const DataColumn(
                                  label: Text('Periodo assegnatario')),
                            if (!_compactView)
                              const DataColumn(label: Text('Noleggiatore')),
                            if (!_compactView)
                              const DataColumn(label: Text('Scad. contratto')),
                            if (!_compactView)
                              const DataColumn(
                                  label: Text('Scad. assicurazione')),
                            if (!_compactView)
                              const DataColumn(label: Text('Scad. bolli')),
                            if (!_compactView)
                              const DataColumn(label: Text('Scad. revisione')),
                            if (!_compactView)
                              const DataColumn(
                                  label: Text('Scad. verifica gru')),
                            if (!_compactView)
                              const DataColumn(
                                  label: Text('Scad. cronotachigrafo')),
                            const DataColumn(label: Text('Multicard')),
                            const DataColumn(label: Text('Telepass')),
                            const DataColumn(label: Text('Kit ruota')),
                            const DataColumn(label: Text('Deposito gomme')),
                            if (showKm) ...[
                              const DataColumn(label: Text('Km attuali')),
                              const DataColumn(label: Text('Ultimo agg.')),
                            ],
                            const DataColumn(label: Text('Note')),
                            const DataColumn(label: Text('Azioni')),
                          ],
                          rows: _rows.map((r) {
                            final id = (r['id_uuid'] ?? '').toString();
                            return DataRow(
                                color: WidgetStateProperty.resolveWith<Color?>(
                                    (_) => deadlineFlashLit(id)
                                        ? Colors.amber.withValues(alpha: 0.42)
                                        : null),
                                onSelectChanged: (_) => _openForm(row: r),
                                cells: [
                                  _hoverCell(
                                    SizedBox(
                                      key: _deadlineUuidAnchorsMatch(id)
                                          ? _deadlineScrollAnchorKey
                                          : null,
                                      width: 42,
                                      child: Text(
                                          (r['numerazione'] ?? '').toString()),
                                    ),
                                    r,
                                    'numerazione',
                                  ),
                                  _hoverCell(
                                    SizedBox(
                                      width: 90,
                                      child:
                                          Text((r['targa'] ?? '').toString()),
                                    ),
                                    r,
                                    'targa',
                                  ),
                                  _hoverCell(
                                    SizedBox(
                                      width: 95,
                                      child:
                                          Text((r['marca'] ?? '').toString()),
                                    ),
                                    r,
                                    'marca',
                                  ),
                                  _hoverCell(
                                    SizedBox(
                                      width: 180,
                                      child: Text(
                                          (r['modello'] ?? '').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    r,
                                    'modello',
                                  ),
                                  _hoverCell(
                                      Text((r['tipologia_mezzo'] ?? '')
                                          .toString()),
                                      r,
                                      'tipologia_mezzo'),
                                  _hoverCell(
                                    SizedBox(
                                      width: 220,
                                      child: Text(
                                          (r['assegnatario_attuale'] ?? '')
                                              .toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    r,
                                    'assegnatario_attuale',
                                  ),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(
                                            r['periodo_assegnatario_attuale'])),
                                        r,
                                        'periodo_assegnatario_attuale'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text((r['noleggiatore'] ?? '')
                                            .toString()),
                                        r,
                                        'noleggiatore'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(r['scadenza_contratto'])),
                                        r,
                                        'scadenza_contratto'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(
                                            r['scadenza_assicurazione'])),
                                        r,
                                        'scadenza_assicurazione'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(r['scadenza_bolli'])),
                                        r,
                                        'scadenza_bolli'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(r['scadenza_revisione'])),
                                        r,
                                        'scadenza_revisione'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(r[
                                            'scadenza_verifica_periodica_gru'])),
                                        r,
                                        'scadenza_verifica_periodica_gru'),
                                  if (!_compactView)
                                    _hoverCell(
                                        Text(_fmtDate(r[
                                            'scadenza_revisione_biennale_cronotachigrafo'])),
                                        r,
                                        'scadenza_revisione_biennale_cronotachigrafo'),
                                  _hoverCell(
                                      Text((r['multicard'] ?? '').toString()),
                                      r,
                                      'multicard'),
                                  _hoverCell(
                                      Text((r['telepass'] ?? '').toString()),
                                      r,
                                      'telepass'),
                                  _hoverCell(
                                      Text((r['kit_ruota_di_scorta'] ?? '')
                                          .toString()),
                                      r,
                                      'kit_ruota_di_scorta'),
                                  _hoverCell(
                                    SizedBox(
                                      width: 180,
                                      child: Text(
                                          (r['deposito_gomme'] ?? '')
                                              .toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    r,
                                    'deposito_gomme',
                                  ),
                                  if (showKm) ...[
                                    _hoverCell(
                                      Text(
                                        _kmAttualiLabel(r),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      r,
                                      'km_attuali',
                                    ),
                                    _hoverCell(
                                      Text(_kmUltimoAggLabel(r)),
                                      r,
                                      'km_aggiornato_il',
                                    ),
                                  ],
                                  _hoverCell(
                                    SizedBox(
                                      width: 220,
                                      child: Text((r['note'] ?? '').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    r,
                                    'note',
                                  ),
                                  _hoverCell(
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Modifica',
                                            onPressed: () => _openForm(row: r),
                                            icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                    width: 24, height: 24),
                                          ),
                                          if (id.isNotEmpty)
                                            IconButton(
                                              tooltip: 'QR viaggio',
                                              onPressed: () =>
                                                  _showViaggioQrDialog(r),
                                              icon: const Icon(
                                                  Icons.qr_code_2_outlined,
                                                  size: 18),
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
                                                color: Colors.red,
                                                size: 18),
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
                                    r,
                                    'updated_at',
                                  ),
                                ]);
                          }).toList(growable: false),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _MezzoDialog extends StatefulWidget {
  final Map<String, dynamic>? row;
  const _MezzoDialog({this.row});

  @override
  State<_MezzoDialog> createState() => _MezzoDialogState();
}

class _MezzoDialogState extends State<_MezzoDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController numerazioneCtrl;
  late final TextEditingController targaCtrl;
  late final TextEditingController marcaCtrl;
  late final TextEditingController modelloCtrl;
  late final TextEditingController tipologiaMezzoCtrl;
  late final TextEditingController assegnatarioSearchCtrl;
  late final TextEditingController periodoAssegnatarioCtrl;
  late final TextEditingController dataFineAssegnatarioCtrl;
  late final TextEditingController noleggiatoreCtrl;
  late final TextEditingController scadContrattoCtrl;
  late final TextEditingController scadAssicurazioneCtrl;
  late final TextEditingController scadBolliCtrl;
  late final TextEditingController scadRevisioneCtrl;
  late final TextEditingController scadVerificaGruCtrl;
  late final TextEditingController scadCronoCtrl;
  late final TextEditingController multicardCtrl;
  late final TextEditingController telepassCtrl;
  late final TextEditingController kitRuotaCtrl;
  late final TextEditingController depositoGommeCtrl;
  late final TextEditingController noteCtrl;
  final List<_AssegnatarioOption> _assegnatariOptions = <_AssegnatarioOption>[];
  String? _assegnatarioUserUuid;

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? <String, dynamic>{};
    numerazioneCtrl =
        TextEditingController(text: (r['numerazione'] ?? '').toString());
    targaCtrl = TextEditingController(text: (r['targa'] ?? '').toString());
    marcaCtrl = TextEditingController(text: (r['marca'] ?? '').toString());
    modelloCtrl = TextEditingController(text: (r['modello'] ?? '').toString());
    tipologiaMezzoCtrl =
        TextEditingController(text: (r['tipologia_mezzo'] ?? '').toString());
    _assegnatarioUserUuid =
        (r['assegnatario_user_uuid'] ?? '').toString().trim().isEmpty
            ? null
            : (r['assegnatario_user_uuid'] ?? '').toString().trim();
    assegnatarioSearchCtrl = TextEditingController(
        text: (r['assegnatario_attuale'] ?? '').toString());
    periodoAssegnatarioCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['periodo_assegnatario_attuale']));
    dataFineAssegnatarioCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['data_fine_assegnatario_attuale']));
    noleggiatoreCtrl =
        TextEditingController(text: (r['noleggiatore'] ?? '').toString());
    scadContrattoCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['scadenza_contratto']));
    scadAssicurazioneCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['scadenza_assicurazione']));
    scadBolliCtrl =
        TextEditingController(text: formatDateDdMmYyyy(r['scadenza_bolli']));
    scadRevisioneCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['scadenza_revisione']));
    scadVerificaGruCtrl = TextEditingController(
        text: formatDateDdMmYyyy(r['scadenza_verifica_periodica_gru']));
    scadCronoCtrl = TextEditingController(
        text: formatDateDdMmYyyy(
            r['scadenza_revisione_biennale_cronotachigrafo']));
    multicardCtrl =
        TextEditingController(text: (r['multicard'] ?? '').toString());
    telepassCtrl =
        TextEditingController(text: (r['telepass'] ?? '').toString());
    kitRuotaCtrl = TextEditingController(
        text: (r['kit_ruota_di_scorta'] ?? '').toString());
    depositoGommeCtrl =
        TextEditingController(text: (r['deposito_gomme'] ?? '').toString());
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
    _loadDipendentiOptions();
    unawaited(_fillMulticardFromGestione());
  }

  Future<void> _fillMulticardFromGestione() async {
    final targa = targaCtrl.text.trim();
    if (targa.isEmpty) return;
    final rows = await fetchMulticardRowsForTarga(_supa, targa);
    final nums = <String>[];
    for (final r in rows) {
      final n = (r['multicard'] ?? '').toString().trim();
      if (n.isNotEmpty && !nums.contains(n)) nums.add(n);
    }
    if (!mounted) return;
    multicardCtrl.text = nums.join(' ');
  }

  Future<void> _loadDipendentiOptions() async {
    try {
      final personaleRows = await _supa
          .from('personale')
          .select('id_uuid,full_name,matricola,user_id,active')
          .order('full_name', ascending: true);
      final personaleList = List<Map<String, dynamic>>.from(
          (personaleRows as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));

      final userIds = <int>{};
      for (final p in personaleList) {
        final uid = p['user_id'];
        if (uid is int) userIds.add(uid);
        final uidParsed = int.tryParse((uid ?? '').toString().trim());
        if (uidParsed != null) userIds.add(uidParsed);
      }

      final userById = <int, String>{};
      if (userIds.isNotEmpty) {
        final users = await _supa
            .from('users')
            .select('id,id_uuid')
            .inFilter('id', userIds.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = m['id'] is int
              ? m['id'] as int
              : int.tryParse((m['id'] ?? '').toString());
          final uuid = (m['id_uuid'] ?? '').toString().trim();
          if (id != null && uuid.isNotEmpty) userById[id] = uuid;
        }
      }

      final options = <_AssegnatarioOption>[];
      for (final p in personaleList) {
        final fullName = (p['full_name'] ?? '').toString().trim();
        if (fullName.isEmpty) continue;
        final matricola = (p['matricola'] ?? '').toString().trim();
        final active = p['active'] == true;
        final labelParts = <String>[fullName];
        if (matricola.isNotEmpty) labelParts.add('Matr. $matricola');
        if (!active) labelParts.add('Inattivo');
        final label = labelParts.join(' - ');
        final uid = p['user_id'];
        int? userId;
        if (uid is int) userId = uid;
        userId ??= int.tryParse((uid ?? '').toString().trim());
        options.add(_AssegnatarioOption(
          label: label,
          assignedName: fullName,
          userUuid: userId != null ? userById[userId] : null,
        ));
      }
      options.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _assegnatariOptions
          ..clear()
          ..addAll(options);
        if ((_assegnatarioUserUuid ?? '').isNotEmpty) {
          final matched = _assegnatariOptions
              .where((o) => o.userUuid == _assegnatarioUserUuid);
          if (matched.isNotEmpty) {
            assegnatarioSearchCtrl.text = matched.first.assignedName;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    numerazioneCtrl.dispose();
    targaCtrl.dispose();
    marcaCtrl.dispose();
    modelloCtrl.dispose();
    tipologiaMezzoCtrl.dispose();
    assegnatarioSearchCtrl.dispose();
    periodoAssegnatarioCtrl.dispose();
    dataFineAssegnatarioCtrl.dispose();
    noleggiatoreCtrl.dispose();
    scadContrattoCtrl.dispose();
    scadAssicurazioneCtrl.dispose();
    scadBolliCtrl.dispose();
    scadRevisioneCtrl.dispose();
    scadVerificaGruCtrl.dispose();
    scadCronoCtrl.dispose();
    multicardCtrl.dispose();
    telepassCtrl.dispose();
    kitRuotaCtrl.dispose();
    depositoGommeCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    try {
      String? toIso(String value) => parseFlexibleDateToIsoDate(value.trim());
      final assigneeName = assegnatarioSearchCtrl.text.trim();
    if (assigneeName.isNotEmpty && (_assegnatarioUserUuid ?? '').isEmpty) {
      final map = await MezziKmService.loadAssigneeNameToUserUuidMap();
      final resolved = MezziKmService.resolveAssigneeUserUuid(
        <String, dynamic>{'assegnatario_attuale': assigneeName},
        assigneeNameToUserUuid: map,
      );
      if (resolved != null && resolved.isNotEmpty) {
        _assegnatarioUserUuid = resolved;
      }
    }
    final prevSnap =
        LogisticaAssigneeSnapshot.fromMezzoRow(widget.row);
    final nextName = assegnatarioSearchCtrl.text.trim();
    final nextSnap = LogisticaAssigneeSnapshot(
      name: nextName.isEmpty ? null : nextName,
      userUuid: _assegnatarioUserUuid,
    );
    final assigneeChanged =
        LogisticaAssetStoricoService.assigneeChanged(prevSnap, nextSnap);
    if (assigneeChanged && prevSnap.hasAssignee) {
      if (!mounted) return;
      final targaLabel = targaCtrl.text.trim().isNotEmpty
          ? 'mezzo ${targaCtrl.text.trim()}'
          : 'questo mezzo';
      final ok = await confirmPreviousAssigneeGiustificativi(
        context: context,
        previousAssigneeName: prevSnap.name ?? '',
        assetLabel: targaLabel,
      );
      if (!ok || !mounted) return;
    }
    if (assigneeChanged && nextSnap.hasAssignee) {
      periodoAssegnatarioCtrl.text =
          LogisticaAssetStoricoService.todayDisplayDate();
    }
    final inizioIso = LogisticaAssetStoricoService.resolveDataInizioOnSave(
      previous: prevSnap,
      next: nextSnap,
      manualInizioIso: toIso(periodoAssegnatarioCtrl.text),
    );

    final payload = <String, dynamic>{
      'numerazione': numerazioneCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(numerazioneCtrl.text.trim()),
      'targa': targaCtrl.text.trim().isEmpty ? null : targaCtrl.text.trim(),
      'marca': marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
      'modello':
          modelloCtrl.text.trim().isEmpty ? null : modelloCtrl.text.trim(),
      'tipologia_mezzo': tipologiaMezzoCtrl.text.trim().isEmpty
          ? null
          : tipologiaMezzoCtrl.text.trim(),
      'assegnatario_user_uuid': _assegnatarioUserUuid,
      'assegnatario_attuale': nextName.isEmpty ? null : nextName,
      'periodo_assegnatario_attuale': inizioIso,
      'data_fine_assegnatario_attuale': toIso(dataFineAssegnatarioCtrl.text),
      'noleggiatore': noleggiatoreCtrl.text.trim().isEmpty
          ? null
          : noleggiatoreCtrl.text.trim(),
      'scadenza_contratto': toIso(scadContrattoCtrl.text),
      'scadenza_assicurazione': toIso(scadAssicurazioneCtrl.text),
      'scadenza_bolli': toIso(scadBolliCtrl.text),
      'scadenza_revisione': toIso(scadRevisioneCtrl.text),
      'scadenza_verifica_periodica_gru': toIso(scadVerificaGruCtrl.text),
      'scadenza_revisione_biennale_cronotachigrafo': toIso(scadCronoCtrl.text),
      'kit_ruota_di_scorta':
          kitRuotaCtrl.text.trim().isEmpty ? null : kitRuotaCtrl.text.trim(),
      'deposito_gomme': depositoGommeCtrl.text.trim().isEmpty
          ? null
          : depositoGommeCtrl.text.trim(),
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'active': true,
    };
    final id = (widget.row?['id_uuid'] ?? '').toString().trim();
    final targa = targaCtrl.text.trim();

    await LogisticaAssetStoricoService.handleMezzoAssigneeOnSave(
      supa: _supa,
      previousRow: widget.row,
      targa: targa,
      mezzoIdUuid: id.isEmpty ? null : id,
      next: nextSnap,
      telepass: telepassCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );

    String? savedId = id.isEmpty ? null : id;
    if (id.isEmpty) {
      final inserted = await _supa
          .from('logistica_mezzi_stradali')
          .insert(payload)
          .select('id_uuid')
          .single();
      savedId = (inserted['id_uuid'] ?? '').toString();
    } else {
      await _supa
          .from('logistica_mezzi_stradali')
          .update(payload)
          .eq('id_uuid', id);
    }
    await LogisticaAssetStoricoService.ensureForMezzo(
      supa: _supa,
      targa: targa,
      mezzoIdUuid: savedId,
      telepass: telepassCtrl.text.trim(),
    );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore salvataggio: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dipendentiItems = _assegnatariOptions;
    final fields = <Widget>[
      TextField(
          controller: numerazioneCtrl,
          decoration: const InputDecoration(
              labelText: 'Numerazione', border: OutlineInputBorder())),
      TextField(
          controller: targaCtrl,
          decoration: const InputDecoration(
              labelText: 'Targa', border: OutlineInputBorder())),
      TextField(
          controller: marcaCtrl,
          decoration: const InputDecoration(
              labelText: 'Marca', border: OutlineInputBorder())),
      TextField(
          controller: modelloCtrl,
          decoration: const InputDecoration(
              labelText: 'Modello', border: OutlineInputBorder())),
      TextField(
          controller: tipologiaMezzoCtrl,
          decoration: const InputDecoration(
              labelText: 'Tipologia mezzo', border: OutlineInputBorder())),
      Autocomplete<_AssegnatarioOption>(
        initialValue: TextEditingValue(text: assegnatarioSearchCtrl.text),
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.trim().toLowerCase();
          if (q.isEmpty) return dipendentiItems;
          return dipendentiItems.where((e) =>
              e.label.toLowerCase().contains(q) ||
              e.assignedName.toLowerCase().contains(q));
        },
        displayStringForOption: (opt) => opt.label,
        onSelected: (opt) {
          setState(() {
            _assegnatarioUserUuid = opt.userUuid;
            assegnatarioSearchCtrl.text = opt.assignedName;
            periodoAssegnatarioCtrl.text =
                LogisticaAssetStoricoService.todayDisplayDate();
            dataFineAssegnatarioCtrl.clear();
          });
        },
        fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
          if (textCtrl.text != assegnatarioSearchCtrl.text) {
            textCtrl.text = assegnatarioSearchCtrl.text;
          }
          return TextField(
            controller: textCtrl,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Assegnatario (seleziona dipendente)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Azzera assegnatario',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _assegnatarioUserUuid = null;
                    assegnatarioSearchCtrl.clear();
                    textCtrl.clear();
                  });
                },
              ),
            ),
            onChanged: (v) {
              assegnatarioSearchCtrl.text = v;
              final exact = dipendentiItems
                  .where((e) =>
                      e.label.toLowerCase() == v.trim().toLowerCase() ||
                      e.assignedName.toLowerCase() == v.trim().toLowerCase())
                  .toList(growable: false);
              setState(() {
                _assegnatarioUserUuid =
                    exact.isNotEmpty ? exact.first.userUuid : null;
              });
            },
          );
        },
      ),
      TextField(
          controller: periodoAssegnatarioCtrl,
          decoration: const InputDecoration(
              labelText: 'Data inizio assegnatario (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: dataFineAssegnatarioCtrl,
          decoration: const InputDecoration(
              labelText: 'Data fine assegnatario attuale (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: noleggiatoreCtrl,
          decoration: const InputDecoration(
              labelText: 'Noleggiatore', border: OutlineInputBorder())),
      TextField(
          controller: scadContrattoCtrl,
          decoration: const InputDecoration(
              labelText: 'Scadenza contratto (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: scadAssicurazioneCtrl,
          decoration: const InputDecoration(
              labelText: 'Scadenza assicurazione (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: scadBolliCtrl,
          decoration: const InputDecoration(
              labelText: 'Scadenza bolli (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: scadRevisioneCtrl,
          decoration: const InputDecoration(
              labelText: 'Scadenza revisione (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: scadVerificaGruCtrl,
          decoration: const InputDecoration(
              labelText: 'Scad. verifica periodica gru (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: scadCronoCtrl,
          decoration: const InputDecoration(
              labelText: 'Scad. revisione cronotachigrafo (GG/MM/AAAA)',
              border: OutlineInputBorder())),
      TextField(
          controller: multicardCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: InputDecoration(
            labelText: 'Multicard',
            helperText:
                'Solo lettura: si assegna da Gestione Multicard.',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
          )),
      TextField(
          controller: telepassCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: const InputDecoration(
            labelText: 'Telepass',
            helperText: 'Solo lettura: si assegna da Gestione Telepass.',
            border: OutlineInputBorder(),
          )),
      TextField(
          controller: kitRuotaCtrl,
          decoration: const InputDecoration(
              labelText: 'Kit ruota di scorta', border: OutlineInputBorder())),
      TextField(
          controller: depositoGommeCtrl,
          decoration: const InputDecoration(
              labelText: 'Deposito gomme', border: OutlineInputBorder())),
      TextField(
          controller: noteCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Note', border: OutlineInputBorder())),
    ];
    final dialogW = logisticaDialogWidth(context, desktop: 680);
    return AlertDialog(
      title: Text(widget.row == null
          ? 'Nuovo mezzo stradale'
          : 'Modifica mezzo stradale'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: fields
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: w,
                    ))
                .toList(growable: false),
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

class _GommeDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  const _GommeDialog({required this.row});

  @override
  State<_GommeDialog> createState() => _GommeDialogState();
}

class _GommeDialogState extends State<_GommeDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController kitRuotaCtrl;
  late final TextEditingController depositoGommeCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    kitRuotaCtrl = TextEditingController(
        text: (r['kit_ruota_di_scorta'] ?? '').toString());
    depositoGommeCtrl =
        TextEditingController(text: (r['deposito_gomme'] ?? '').toString());
  }

  @override
  void dispose() {
    kitRuotaCtrl.dispose();
    depositoGommeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = (widget.row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    try {
      await _supa.from('logistica_mezzi_stradali').update({
        'kit_ruota_di_scorta':
            kitRuotaCtrl.text.trim().isEmpty ? null : kitRuotaCtrl.text.trim(),
        'deposito_gomme': depositoGommeCtrl.text.trim().isEmpty
            ? null
            : depositoGommeCtrl.text.trim(),
      }).eq('id_uuid', id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore salvataggio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogW = logisticaDialogWidth(context, desktop: 540);
    return AlertDialog(
      title: const Text('Modifica sezione gomme'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: kitRuotaCtrl,
                decoration: const InputDecoration(
                    labelText: 'Kit ruota di scorta',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: depositoGommeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Deposito gomme', border: OutlineInputBorder()),
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
