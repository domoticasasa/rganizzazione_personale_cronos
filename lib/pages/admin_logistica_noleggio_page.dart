import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_box_linked_sync.dart';
import '../utils/date_formatters.dart';
import '../utils/dt_user_list.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/logistica_layout.dart';
import '../utils/mdo_gps_coords.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class AdminLogisticaNoleggioPage extends StatefulWidget {
  final bool forceMobileLayout;
  const AdminLogisticaNoleggioPage({super.key, this.forceMobileLayout = false});

  @override
  State<AdminLogisticaNoleggioPage> createState() =>
      _AdminLogisticaNoleggioPageState();
}

class _AdminLogisticaNoleggioPageState
    extends State<AdminLogisticaNoleggioPage> {
  final _supa = Supabase.instance.client;
  final ScrollController _desktopHorizontalCtrl = ScrollController();
  final ScrollController _desktopVerticalCtrl = ScrollController();
  bool _loading = true;
  bool _compactView = true;
  String _search = '';
  Timer? _searchDebounce;
  Timer? _blinkTimer;
  bool _blinkOn = true;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Map<String, String> _utentiByUuid = <String, String>{};
  final Set<String> _selectedIds = <String>{};
  final List<String> _commessaOptions = <String>[];
  final Map<String, String> _commesseById = <String, String>{};
  final Map<String, Map<String, dynamic>> _commesseRowsById =
      <String, Map<String, dynamic>>{};
  final List<String> _dtOptions = <String>[];

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _loadCommesseOptions();
    _loadDtOptions();
    _loadRows();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _searchDebounce?.cancel();
    _desktopHorizontalCtrl.dispose();
    _desktopVerticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    final res = await _supa
        .from('logistica_noleggio')
        .select()
        .order('commessa', ascending: true);
    var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    if (_search.trim().isNotEmpty) {
      final k = _search.toLowerCase().trim();
      list = list.where((r) {
        final fields = [
          r['commessa'],
          _resolveCommessaFullLabel(r['commessa']),
          _resolveCommessaCoords(r['commessa']),
          r['luogo_commessa'],
          r['fornitore'],
          r['descrizione'],
          r['qta_mdo'],
          r['accessori_1'],
          r['qta_1'],
          r['accessori_2'],
          r['qta_2'],
          r['numero_contratto'],
          r['oda'],
          r['nolo_dal'],
          r['nolo_al'],
          r['stato'],
          r['richiedente'],
          r['utilizzatore'],
          r['note'],
        ].map((v) => (v ?? '').toString().toLowerCase());
        return fields.any((f) => f.contains(k));
      }).toList(growable: false);
    }
    list.sort((a, b) {
      final sa = _normalizeStato(a['stato']);
      final sb = _normalizeStato(b['stato']);
      int rank(String s) {
        if (s == 'OPEN') return 0;
        if (s == 'CLOSED') return 1;
        return 2;
      }

      final byStato = rank(sa).compareTo(rank(sb));
      if (byStato != 0) return byStato;

      final ca = (a['commessa'] ?? '').toString().toLowerCase();
      final cb = (b['commessa'] ?? '').toString().toLowerCase();
      final byCommessa = ca.compareTo(cb);
      if (byCommessa != 0) return byCommessa;

      final da = (a['descrizione'] ?? '').toString().toLowerCase();
      final db = (b['descrizione'] ?? '').toString().toLowerCase();
      return da.compareTo(db);
    });
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
      final visibleIds = list
          .map((r) => (r['id_uuid'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      _selectedIds.removeWhere((id) => !visibleIds.contains(id));
      if (showLoader) _loading = false;
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

  void _toggleSelectAllVisible() {
    final ids = _visibleRowIds;
    if (ids.isEmpty) return;
    setState(() {
      if (_allVisibleSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

  List<String> get _visibleRowIds => _rows
      .map((r) => (r['id_uuid'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toList();

  bool get _allVisibleSelected {
    final ids = _visibleRowIds;
    return ids.isNotEmpty && ids.every(_selectedIds.contains);
  }

  Widget? _selectionActionBar() {
    if (_selectedIds.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${_selectedIds.length} righe selezionate',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          FilledButton.icon(
            onPressed: _bulkDeleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Elimina selezionati'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text('Annulla selezione'),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Elimina selezionati ($count)'),
        content: Text(
          'Confermi l\'eliminazione di $count righe di noleggio? '
          'L\'azione è irreversibile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final ids = _selectedIds.toList();
      const chunkSize = 80;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(
          i,
          i + chunkSize > ids.length ? ids.length : i + chunkSize,
        );
        await _supa
            .from('logistica_noleggio')
            .delete()
            .inFilter('id_uuid', chunk);
      }
      if (!mounted) return;
      setState(() => _selectedIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eliminate $count righe.')),
      );
      await _loadRows(showLoader: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore eliminazione multipla: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadRows(showLoader: false);
    });
  }

  String _normalizeStato(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.contains('clos')) return 'CLOSED';
    if (s.contains('open')) return 'OPEN';
    return (raw ?? '').toString().trim().toUpperCase();
  }

  Color _statoColor(String stato) {
    switch (stato) {
      case 'OPEN':
        return Colors.green;
      case 'CLOSED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _fmtDate(dynamic raw) => formatDateDdMmYyyy(raw);

  DateTime? _parseNoloAlDate(dynamic raw) {
    final iso = parseFlexibleDateToIsoDate((raw ?? '').toString());
    if ((iso ?? '').isEmpty) return null;
    final dt = DateTime.tryParse(iso!);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  int? _daysToNoloAl(dynamic raw) {
    final dt = _parseNoloAlDate(raw);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dt.difference(today).inDays;
  }

  Widget _buildNoloAlCell(dynamic raw) {
    final text = _fmtDate(raw);
    final days = _daysToNoloAl(raw);
    final expired = days != null && days < 0;
    final dueSoon = days != null && days >= 0 && days <= 3;
    final showAlert = expired || (dueSoon && _blinkOn);
    final color = Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: showAlert
          ? BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color),
            )
          : null,
      child: Text(
        text,
        style: TextStyle(
          color: showAlert ? color : null,
          fontWeight: showAlert ? FontWeight.w700 : null,
        ),
      ),
    );
  }

  Future<void> _loadCommesseOptions() async {
    try {
      final res = await _supa
          .from('commesse')
          .select('id_uuid,nome,latitudine,longitudine')
          .order('nome');
      final options = <String>{};
      final byId = <String, String>{};
      final rowsById = <String, Map<String, dynamic>>{};
      for (final row in (res as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        final nome = (m['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) options.add(nome);
        if (id.isNotEmpty) {
          byId[id] = nome;
          rowsById[id] = m;
        }
      }
      if (!mounted) return;
      setState(() {
        _commessaOptions
          ..clear()
          ..addAll(options.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
        _commesseById
          ..clear()
          ..addAll(byId);
        _commesseRowsById
          ..clear()
          ..addAll(rowsById);
      });
    } catch (_) {
      // Non bloccare la pagina se il caricamento commesse fallisce.
    }
  }

  String _displayOrDash(String value) => value.trim().isEmpty ? '—' : value.trim();

  String _resolveCommessaFullLabel(dynamic raw) {
    final trimmed = (raw ?? '').toString().trim();
    if (trimmed.isEmpty) return '';
    final id = findCommessaIdByText(trimmed, _commesseById);
    if (id != null) {
      final nome = (_commesseById[id] ?? '').trim();
      if (nome.isNotEmpty) return nome;
    }
    return trimmed;
  }

  String _resolveCommessaCoords(dynamic raw) {
    final trimmed = (raw ?? '').toString().trim();
    if (trimmed.isEmpty) return '';
    final id = findCommessaIdByText(trimmed, _commesseById);
    if (id == null) return '';
    final row = _commesseRowsById[id];
    if (row == null) return '';
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) return '';
    return formatGpsCoordsText(coords.$1, coords.$2);
  }

  Widget _commessaInfoCell(BuildContext context, dynamic raw) {
    final desc = _resolveCommessaFullLabel(raw);
    return Text(
      desc.isEmpty ? '—' : desc,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
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
      // fallback non bloccante
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
      final sheet = excel['Noleggio'];
      sheet.appendRow([
        'Commessa',
        'Coordinate commessa',
        'Fornitore',
        'Descrizione',
        "Q.ta MDO",
        'Accessori 1',
        "Q.ta 1",
        'Accessori 2',
        "Q.ta 2",
        'N. contratto',
        'ODA',
        'Nolo dal',
        'Nolo al',
        'Stato',
        'Richiedente',
        'Utilizzatore',
        'Note',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          _resolveCommessaFullLabel(r['commessa']),
          _resolveCommessaCoords(r['commessa']),
          (r['fornitore'] ?? '').toString(),
          (r['descrizione'] ?? '').toString(),
          (r['qta_mdo'] ?? '').toString(),
          (r['accessori_1'] ?? '').toString(),
          (r['qta_1'] ?? '').toString(),
          (r['accessori_2'] ?? '').toString(),
          (r['qta_2'] ?? '').toString(),
          (r['numero_contratto'] ?? '').toString(),
          (r['oda'] ?? '').toString(),
          _fmtDate(r['nolo_dal']),
          _fmtDate(r['nolo_al']),
          (r['stato'] ?? '').toString(),
          (r['richiedente'] ?? '').toString(),
          (r['utilizzatore'] ?? '').toString(),
          (r['note'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Noleggio',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Excel completato: $p')),
      );
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Percorso file esportato'),
          content: SelectableText(p.isEmpty ? 'Percorso non disponibile' : p),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
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
      builder: (_) => _NoleggioDialog(
        row: row,
        commesse: _commessaOptions,
        dtOptions: _dtOptions,
      ),
    );
    if (ok == true) await _loadRows();
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina noleggio'),
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
    await _supa.from('logistica_noleggio').delete().eq('id_uuid', id);
    if (mounted) setState(() => _selectedIds.remove(id));
    await _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout =
        isLogisticaCompactLayout(context, force: widget.forceMobileLayout);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Logistica - Noleggio'),
        actions: [
          if (_selectedIds.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${_selectedIds.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          IconButton(
            tooltip: _allVisibleSelected ? 'Deseleziona tutto' : 'Seleziona tutto',
            onPressed: _rows.isEmpty ? null : _toggleSelectAllVisible,
            icon: Icon(
              _allVisibleSelected ? Icons.deselect : Icons.select_all,
            ),
          ),
          IconButton(
            tooltip: 'Elimina selezionati',
            onPressed: _selectedIds.isEmpty ? null : _bulkDeleteSelected,
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
          ),
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Nuovo noleggio',
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
                          width: 380,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText:
                                  'Cerca commessa, fornitore, contratto, stato...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                      ),
                      if (_selectionActionBar() != null) _selectionActionBar()!,
                      Expanded(
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final r = _rows[index];
                            final id = (r['id_uuid'] ?? '').toString();
                            final stato = _normalizeStato(r['stato']);
                            return Card(
                              margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                              child: ListTile(
                                leading: Checkbox(
                                  value: id.isNotEmpty &&
                                      _selectedIds.contains(id),
                                  onChanged: id.isEmpty
                                      ? null
                                      : (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedIds.add(id);
                                            } else {
                                              _selectedIds.remove(id);
                                            }
                                          });
                                        },
                                ),
                                title: Text(
                                  _displayOrDash(
                                    _resolveCommessaFullLabel(r['commessa']),
                                  ),
                                ),
                                subtitle: Builder(builder: (_) {
                                  final noloAl = _fmtDate(r['nolo_al']);
                                  final days = _daysToNoloAl(r['nolo_al']);
                                  final expired = days != null && days < 0;
                                  final dueSoon =
                                      days != null && days >= 0 && days <= 3;
                                  final redAlert = expired || (dueSoon && _blinkOn);
                                  final coords =
                                      _resolveCommessaCoords(r['commessa']);
                                  return RichText(
                                    text: TextSpan(
                                      style: DefaultTextStyle.of(context).style,
                                      children: [
                                        if (coords.isNotEmpty)
                                          TextSpan(
                                            text: 'Coordinate: $coords\n',
                                          ),
                                        TextSpan(
                                            text:
                                                'Descrizione: ${(r['descrizione'] ?? '').toString()}\n'),
                                        TextSpan(
                                            text:
                                                'Fornitore: ${(r['fornitore'] ?? '').toString()}\n'),
                                        TextSpan(
                                            text:
                                                'Contratto: ${(r['numero_contratto'] ?? '').toString()} - Stato: $stato\n'),
                                        TextSpan(
                                            text:
                                                'Richiedente: ${(r['richiedente'] ?? '').toString()}\n'),
                                        TextSpan(text: 'Nolo al: '),
                                        TextSpan(
                                          text: noloAl,
                                          style: TextStyle(
                                            color: redAlert ? Colors.red : null,
                                            fontWeight: redAlert
                                                ? FontWeight.w700
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                isThreeLine: true,
                                onTap: () => _openForm(row: r),
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _statoColor(stato)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                            color: _statoColor(stato)),
                                      ),
                                      child: Text(
                                        stato.isEmpty ? '-' : stato,
                                        style: TextStyle(
                                          color: _statoColor(stato),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    IconButton(
                                      tooltip: 'Elimina',
                                      onPressed: id.isEmpty
                                          ? null
                                          : () => _deleteRow(id),
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                    ),
                                  ],
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
                              width: 430,
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText:
                                      'Cerca commessa, fornitore, contratto, stato...',
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
                      if (_selectionActionBar() != null) _selectionActionBar()!,
                      Expanded(
                        child: DataTable2(
                          minWidth: _compactView ? 1600 : 2500,
                          fixedTopRows: 1,
                          fixedLeftColumns: 2,
                          showCheckboxColumn: true,
                          scrollController: _desktopVerticalCtrl,
                          horizontalScrollController: _desktopHorizontalCtrl,
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: true,
                          columnSpacing: _compactView ? 12 : 8,
                          horizontalMargin: 10,
                          columns: [
                            const DataColumn(label: Text('Commessa')),
                            const DataColumn(label: Text('Coordinate commessa')),
                            const DataColumn(label: Text('Fornitore')),
                            const DataColumn(label: Text('Descrizione')),
                            const DataColumn(label: Text("Q.ta MDO")),
                            if (!_compactView)
                              const DataColumn(label: Text('Accessori 1')),
                            if (!_compactView)
                              const DataColumn(label: Text('Q.ta 1')),
                            if (!_compactView)
                              const DataColumn(label: Text('Accessori 2')),
                            if (!_compactView)
                              const DataColumn(label: Text('Q.ta 2')),
                            const DataColumn(label: Text('N. contratto')),
                            const DataColumn(label: Text('ODA')),
                            const DataColumn(label: Text('Nolo dal')),
                            const DataColumn(label: Text('Nolo al')),
                            const DataColumn(label: Text('Stato')),
                            const DataColumn(label: Text('Richiedente')),
                            const DataColumn(label: Text('Utilizzatore')),
                            const DataColumn(label: Text('Note')),
                            const DataColumn(label: Text('Azioni')),
                          ],
                          rows: _rows.map((r) {
                            final id = (r['id_uuid'] ?? '').toString();
                            return DataRow(
                              selected: id.isNotEmpty && _selectedIds.contains(id),
                              onSelectChanged: id.isEmpty
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedIds.add(id);
                                        } else {
                                          _selectedIds.remove(id);
                                        }
                                      });
                                    },
                              cells: [
                                _hoverCell(
                                  _commessaInfoCell(context, r['commessa']),
                                  r,
                                  'commessa',
                                ),
                                _hoverCell(
                                  Text(
                                    _displayOrDash(
                                      _resolveCommessaCoords(r['commessa']),
                                    ),
                                  ),
                                  r,
                                  'commessa',
                                ),
                                _hoverCell(
                                    Text((r['fornitore'] ?? '').toString()), r, 'fornitore'),
                                _hoverCell(
                                  SizedBox(
                                    width: 260,
                                    child: Text(
                                        (r['descrizione'] ?? '').toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  r,
                                  'descrizione',
                                ),
                                _hoverCell(Text((r['qta_mdo'] ?? '').toString()), r, 'qta_mdo'),
                                if (!_compactView)
                                  _hoverCell(Text(
                                      (r['accessori_1'] ?? '').toString()), r, 'accessori_1'),
                                if (!_compactView)
                                  _hoverCell(Text((r['qta_1'] ?? '').toString()), r, 'qta_1'),
                                if (!_compactView)
                                  _hoverCell(Text(
                                      (r['accessori_2'] ?? '').toString()), r, 'accessori_2'),
                                if (!_compactView)
                                  _hoverCell(Text((r['qta_2'] ?? '').toString()), r, 'qta_2'),
                                _hoverCell(Text(
                                    (r['numero_contratto'] ?? '').toString()), r, 'numero_contratto'),
                                _hoverCell(Text((r['oda'] ?? '').toString()), r, 'oda'),
                                _hoverCell(Text(_fmtDate(r['nolo_dal'])), r, 'nolo_dal'),
                                _hoverCell(_buildNoloAlCell(r['nolo_al']), r, 'nolo_al'),
                                _hoverCell(
                                  Builder(builder: (_) {
                                    final stato = _normalizeStato(r['stato']);
                                    final color = _statoColor(stato);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: color),
                                      ),
                                      child: Text(
                                        stato.isEmpty ? '-' : stato,
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }),
                                  r,
                                  'stato',
                                ),
                                _hoverCell(
                                    Text((r['richiedente'] ?? '').toString()), r, 'richiedente'),
                                _hoverCell(
                                    Text((r['utilizzatore'] ?? '').toString()), r, 'utilizzatore'),
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
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifica',
                                        onPressed: () => _openForm(row: r),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        visualDensity: VisualDensity.compact,
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
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red, size: 18),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 24, height: 24),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(growable: false),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _NoleggioDialog extends StatefulWidget {
  final Map<String, dynamic>? row;
  final List<String> commesse;
  final List<String> dtOptions;
  const _NoleggioDialog({
    this.row,
    required this.commesse,
    required this.dtOptions,
  });

  @override
  State<_NoleggioDialog> createState() => _NoleggioDialogState();
}

class _NoleggioDialogState extends State<_NoleggioDialog> {
  final _supa = Supabase.instance.client;
  static const List<String> _statoOptions = <String>['OPEN', 'CLOSED'];
  late final TextEditingController commessaCtrl;
  late final TextEditingController luogoCommessaCtrl;
  late final TextEditingController fornitoreCtrl;
  late final TextEditingController descrizioneCtrl;
  late final TextEditingController qtaMdoCtrl;
  late final TextEditingController accessori1Ctrl;
  late final TextEditingController qta1Ctrl;
  late final TextEditingController accessori2Ctrl;
  late final TextEditingController qta2Ctrl;
  late final TextEditingController numeroContrattoCtrl;
  late final TextEditingController odaCtrl;
  late final TextEditingController noloDalCtrl;
  late final TextEditingController noloAlCtrl;
  late final TextEditingController statoCtrl;
  late final TextEditingController richiedenteCtrl;
  late final TextEditingController utilizzatoreCtrl;
  late final TextEditingController noteCtrl;
  String? _statoSel;

  String _normalizeStato(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.contains('clos')) return 'CLOSED';
    if (s.contains('open')) return 'OPEN';
    return raw.trim().toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? <String, dynamic>{};
    commessaCtrl =
        TextEditingController(text: (r['commessa'] ?? '').toString());
    luogoCommessaCtrl =
        TextEditingController(text: (r['luogo_commessa'] ?? '').toString());
    fornitoreCtrl =
        TextEditingController(text: (r['fornitore'] ?? '').toString());
    descrizioneCtrl =
        TextEditingController(text: (r['descrizione'] ?? '').toString());
    qtaMdoCtrl = TextEditingController(text: (r['qta_mdo'] ?? '').toString());
    accessori1Ctrl =
        TextEditingController(text: (r['accessori_1'] ?? '').toString());
    qta1Ctrl = TextEditingController(text: (r['qta_1'] ?? '').toString());
    accessori2Ctrl =
        TextEditingController(text: (r['accessori_2'] ?? '').toString());
    qta2Ctrl = TextEditingController(text: (r['qta_2'] ?? '').toString());
    numeroContrattoCtrl =
        TextEditingController(text: (r['numero_contratto'] ?? '').toString());
    odaCtrl = TextEditingController(text: (r['oda'] ?? '').toString());
    noloDalCtrl =
        TextEditingController(text: formatDateDdMmYyyy(r['nolo_dal']));
    noloAlCtrl = TextEditingController(text: formatDateDdMmYyyy(r['nolo_al']));
    final statoNormalized = _normalizeStato((r['stato'] ?? '').toString());
    statoCtrl = TextEditingController(text: statoNormalized);
    _statoSel = _statoOptions.contains(statoNormalized) ? statoNormalized : null;
    richiedenteCtrl =
        TextEditingController(text: (r['richiedente'] ?? '').toString());
    utilizzatoreCtrl =
        TextEditingController(text: (r['utilizzatore'] ?? '').toString());
    noteCtrl = TextEditingController(text: (r['note'] ?? '').toString());
  }

  @override
  void dispose() {
    commessaCtrl.dispose();
    luogoCommessaCtrl.dispose();
    fornitoreCtrl.dispose();
    descrizioneCtrl.dispose();
    qtaMdoCtrl.dispose();
    accessori1Ctrl.dispose();
    qta1Ctrl.dispose();
    accessori2Ctrl.dispose();
    qta2Ctrl.dispose();
    numeroContrattoCtrl.dispose();
    odaCtrl.dispose();
    noloDalCtrl.dispose();
    noloAlCtrl.dispose();
    statoCtrl.dispose();
    richiedenteCtrl.dispose();
    utilizzatoreCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final commessaRaw = commessaCtrl.text.trim();
    final matchedCommessa = widget.commesse.firstWhere(
      (c) => c.toLowerCase() == commessaRaw.toLowerCase(),
      orElse: () => '',
    );
    if (commessaRaw.isNotEmpty &&
        widget.commesse.isNotEmpty &&
        matchedCommessa.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Commessa non valida: seleziona una commessa presente nell'app."),
          ),
        );
      }
      return;
    }
    final richiedenteRaw = richiedenteCtrl.text.trim();
    final matchedDt = widget.dtOptions.firstWhere(
      (d) => d.toLowerCase() == richiedenteRaw.toLowerCase(),
      orElse: () => '',
    );
    if (richiedenteRaw.isNotEmpty &&
        widget.dtOptions.isNotEmpty &&
        matchedDt.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Richiedente non valido: seleziona un nome dalla lista DT.'),
          ),
        );
      }
      return;
    }
    final payload = <String, dynamic>{
      'commessa': commessaRaw.isEmpty
          ? null
          : (matchedCommessa.isEmpty ? commessaRaw : matchedCommessa),
      'luogo_commessa': luogoCommessaCtrl.text.trim().isEmpty
          ? null
          : luogoCommessaCtrl.text.trim(),
      'fornitore':
          fornitoreCtrl.text.trim().isEmpty ? null : fornitoreCtrl.text.trim(),
      'descrizione': descrizioneCtrl.text.trim().isEmpty
          ? null
          : descrizioneCtrl.text.trim(),
      'qta_mdo': qtaMdoCtrl.text.trim().isEmpty ? null : qtaMdoCtrl.text.trim(),
      'accessori_1': accessori1Ctrl.text.trim().isEmpty
          ? null
          : accessori1Ctrl.text.trim(),
      'qta_1': qta1Ctrl.text.trim().isEmpty ? null : qta1Ctrl.text.trim(),
      'accessori_2': accessori2Ctrl.text.trim().isEmpty
          ? null
          : accessori2Ctrl.text.trim(),
      'qta_2': qta2Ctrl.text.trim().isEmpty ? null : qta2Ctrl.text.trim(),
      'numero_contratto': numeroContrattoCtrl.text.trim().isEmpty
          ? null
          : numeroContrattoCtrl.text.trim(),
      'oda': odaCtrl.text.trim().isEmpty ? null : odaCtrl.text.trim(),
      'nolo_dal': () {
        final raw = noloDalCtrl.text.trim();
        if (raw.isEmpty) return null;
        return parseFlexibleDateToIsoDate(raw) ?? raw;
      }(),
      'nolo_al': () {
        final raw = noloAlCtrl.text.trim();
        if (raw.isEmpty) return null;
        return parseFlexibleDateToIsoDate(raw) ?? raw;
      }(),
      'stato': _statoSel,
      'richiedente': matchedDt.isEmpty ? null : matchedDt,
      'utilizzatore': utilizzatoreCtrl.text.trim().isEmpty
          ? null
          : utilizzatoreCtrl.text.trim(),
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'active': true,
    };
    final id = (widget.row?['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) {
      await _supa.from('logistica_noleggio').insert(payload);
    } else {
      await _supa.from('logistica_noleggio').update(payload).eq('id_uuid', id);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      Autocomplete<String>(
        initialValue: TextEditingValue(text: commessaCtrl.text),
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.trim().toLowerCase();
          if (q.isEmpty) return widget.commesse;
          return widget.commesse.where((e) => e.toLowerCase().contains(q));
        },
        displayStringForOption: (opt) => opt,
        onSelected: (opt) => commessaCtrl.text = opt,
        fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
          if (textCtrl.text != commessaCtrl.text) {
            textCtrl.text = commessaCtrl.text;
          }
          return TextField(
            controller: textCtrl,
            focusNode: focusNode,
            onChanged: (v) => commessaCtrl.text = v,
            decoration: const InputDecoration(
              labelText: 'Commessa (da anagrafica app)',
              border: OutlineInputBorder(),
            ),
          );
        },
      ),
      TextField(
          controller: luogoCommessaCtrl,
          decoration: const InputDecoration(
              labelText: 'Luogo commessa', border: OutlineInputBorder())),
      TextField(
          controller: fornitoreCtrl,
          decoration: const InputDecoration(
              labelText: 'Fornitore', border: OutlineInputBorder())),
      TextField(
          controller: descrizioneCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Descrizione', border: OutlineInputBorder())),
      TextField(
          controller: qtaMdoCtrl,
          decoration: const InputDecoration(
              labelText: "Q.ta MDO", border: OutlineInputBorder())),
      TextField(
          controller: accessori1Ctrl,
          decoration: const InputDecoration(
              labelText: 'Accessori 1', border: OutlineInputBorder())),
      TextField(
          controller: qta1Ctrl,
          decoration: const InputDecoration(
              labelText: "Q.ta 1", border: OutlineInputBorder())),
      TextField(
          controller: accessori2Ctrl,
          decoration: const InputDecoration(
              labelText: 'Accessori 2', border: OutlineInputBorder())),
      TextField(
          controller: qta2Ctrl,
          decoration: const InputDecoration(
              labelText: "Q.ta 2", border: OutlineInputBorder())),
      TextField(
          controller: numeroContrattoCtrl,
          decoration: const InputDecoration(
              labelText: 'N. contratto', border: OutlineInputBorder())),
      TextField(
          controller: odaCtrl,
          decoration: const InputDecoration(
              labelText: 'ODA', border: OutlineInputBorder())),
      TextField(
          controller: noloDalCtrl,
          decoration: const InputDecoration(
              labelText: 'Nolo dal', border: OutlineInputBorder())),
      TextField(
          controller: noloAlCtrl,
          decoration: const InputDecoration(
              labelText: 'Nolo al', border: OutlineInputBorder())),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _statoSel,
        hint: const Text('Seleziona stato'),
        decoration: const InputDecoration(
          labelText: 'Stato',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem<String>(value: 'OPEN', child: Text('OPEN')),
          DropdownMenuItem<String>(value: 'CLOSED', child: Text('CLOSED')),
        ],
        onChanged: (v) {
          setState(() {
            _statoSel = v;
            statoCtrl.text = v ?? '';
          });
        },
      ),
      Autocomplete<String>(
        initialValue: TextEditingValue(text: richiedenteCtrl.text),
        optionsBuilder: (textEditingValue) {
          final q = textEditingValue.text.trim().toLowerCase();
          if (q.isEmpty) return widget.dtOptions;
          return widget.dtOptions.where((e) => e.toLowerCase().contains(q));
        },
        displayStringForOption: (opt) => opt,
        onSelected: (opt) => richiedenteCtrl.text = opt,
        fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
          if (textCtrl.text != richiedenteCtrl.text) {
            textCtrl.text = richiedenteCtrl.text;
          }
          return TextField(
            controller: textCtrl,
            focusNode: focusNode,
            onChanged: (v) => richiedenteCtrl.text = v,
            decoration: const InputDecoration(
              labelText: 'Richiedente (DT)',
              border: OutlineInputBorder(),
            ),
          );
        },
      ),
      TextField(
          controller: utilizzatoreCtrl,
          decoration: const InputDecoration(
              labelText: 'Utilizzatore', border: OutlineInputBorder())),
      TextField(
          controller: noteCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Note', border: OutlineInputBorder())),
    ];

    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo noleggio' : 'Modifica noleggio'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
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
