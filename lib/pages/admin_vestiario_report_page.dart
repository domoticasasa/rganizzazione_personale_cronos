import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';

import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/employee_taglie_editor_dialog.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum _VestReportFilter { compilati, mancanti }

class AdminVestiarioReportPage extends StatefulWidget {
  const AdminVestiarioReportPage({super.key});

  @override
  State<AdminVestiarioReportPage> createState() => _AdminVestiarioReportPageState();
}

class _AdminVestiarioReportPageState extends State<AdminVestiarioReportPage> {
  bool _loading = true;
  String _search = '';
  _VestReportFilter _filter = _VestReportFilter.compilati;
  final TextEditingController _searchCtrl = TextEditingController();
  List<_EmpVestSummary> _all = <_EmpVestSummary>[];
  final Map<String, String> _auditUserNamesByUuid = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pRes = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, email, active')
          .eq('active', true)
          .order('full_name');
      final vRes = await SupabaseService.client
          .from('vestiario_dotazioni')
          .select(
              'id, personale_id, categoria, quantita_assegnata, taglia, matricola, '
              'scadenza, data_consegna, created_at, field_timestamps, updated_at')
          .order('categoria');
      List<Map<String, dynamic>> taglieRows = <Map<String, dynamic>>[];
      try {
        final tRes = await SupabaseService.client.from('personale_taglie').select(
            'personale_id, taglia_tshirt, taglia_pantalone, taglia_felpa, taglia_giacca, taglia_gilet, taglia_scarpe, taglia_guanti');
        taglieRows = List<Map<String, dynamic>>.from(tRes as List);
      } catch (_) {
        taglieRows = <Map<String, dynamic>>[];
      }

      final personaleRows = List<Map<String, dynamic>>.from(pRes as List);
      final vestRows = List<Map<String, dynamic>>.from(vRes as List);
      final taglieByPersonale = <String, Map<String, String>>{};
      for (final t in taglieRows) {
        final pid = (t['personale_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        taglieByPersonale[pid] = {
          'T-shirt': (t['taglia_tshirt'] ?? '').toString(),
          'Pantalone': (t['taglia_pantalone'] ?? '').toString(),
          'Felpa': (t['taglia_felpa'] ?? '').toString(),
          'Giacca': (t['taglia_giacca'] ?? '').toString(),
          'Gilet': (t['taglia_gilet'] ?? '').toString(),
          'Scarpe': (t['taglia_scarpe'] ?? '').toString(),
          'Guanti': (t['taglia_guanti'] ?? '').toString(),
        };
      }
      final byP = <String, List<Map<String, dynamic>>>{};
      for (final d in vestRows) {
        final pid = (d['personale_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        byP.putIfAbsent(pid, () => <Map<String, dynamic>>[]).add(d);
      }

      final out = <_EmpVestSummary>[];
      for (final p in personaleRows) {
        final id = (p['id_uuid'] ?? '').toString().trim();
        final raw = byP[id] ?? const <Map<String, dynamic>>[];
        final latestByCat = <String, _VestEntry>{};
        for (final r in raw) {
          final e = _VestEntry.fromRow(r);
          final k = e.categoria.toLowerCase().trim();
          final curr = latestByCat[k];
          if (curr == null || e.createdAt.isAfter(curr.createdAt)) {
            latestByCat[k] = e;
          }
        }
        final list = latestByCat.values.toList()
          ..sort((a, b) => a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase()));
        out.add(
          _EmpVestSummary(
            personaleId: id,
            fullName: (p['full_name'] ?? '').toString(),
            email: (p['email'] ?? '').toString(),
            rows: list,
            taglie: taglieByPersonale[id] ?? const <String, String>{},
          ),
        );
      }
      out.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      final auditIds = <String>{};
      for (final d in vestRows) {
        mergeFieldTimestampActorUuids(d, auditIds);
      }
      final auditNames = await loadUserNamesByUuid(auditIds);

      if (!mounted) return;
      setState(() {
        _auditUserNamesByUuid
          ..clear()
          ..addAll(auditNames);
        _all = out;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento riepilogo vestiario: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _countCompilati => _all.where(_hasAnyTaglie).length;

  int get _countMancanti => _all.length - _countCompilati;

  List<_EmpVestSummary> get _filtered {
    final q = _search.trim().toLowerCase();
    Iterable<_EmpVestSummary> base = _all;
    if (_filter == _VestReportFilter.compilati) {
      base = base.where(_hasAnyTaglie);
    } else {
      base = base.where((e) => !_hasAnyTaglie(e));
    }
    if (q.isEmpty) return base.toList();
    return base.where((e) {
      final baseMatch =
          e.fullName.toLowerCase().contains(q) || e.email.toLowerCase().contains(q);
      if (baseMatch) return true;
      final taglieValues = e.taglie.values.map((v) => v.toLowerCase());
      return taglieValues.any((v) => v.contains(q));
    }).toList();
  }

  bool _hasAnyTaglie(_EmpVestSummary e) {
    return e.taglie.values.any((v) => v.trim().isNotEmpty);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  static const _taglieColumns = <String>[
    'T-shirt',
    'Pantalone',
    'Felpa',
    'Giacca',
    'Gilet',
    'Scarpe',
    'Guanti',
  ];

  Future<void> _exportExcel() async {
    try {
      final rows = _filtered;
      if (rows.isEmpty) {
        _snack('Nessun dato da esportare con i filtri attuali', error: true);
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow(<String>[
        'Dipendente',
        'Email',
        'Stato taglie',
        ..._taglieColumns,
        'N. consegne registrate',
      ]);
      for (final e in rows) {
        final has = _hasAnyTaglie(e);
        sheet.appendRow(<dynamic>[
          e.fullName,
          e.email,
          has ? 'Compilato' : 'Mancante',
          for (final col in _taglieColumns) (e.taglie[col] ?? '').trim(),
          e.rows.length,
        ]);
      }
      final encoded = excel.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Impossibile generare file Excel');
      }
      final filterLabel =
          _filter == _VestReportFilter.mancanti ? 'mancanti' : 'compilati';
      await ExcelExportHelper.saveAndReveal(
        pageName: 'riepilogo_vestiario_$filterLabel',
        bytes: Uint8List.fromList(encoded),
        openFile: true,
      );
      _snack('Export Excel completato (${rows.length} righe)');
    } catch (e) {
      _snack('Export Excel non riuscito: $e', error: true);
    }
  }

  Future<void> _openTaglieEditor(_EmpVestSummary e) async {
    await showEmployeeTaglieEditorDialog(
      context,
      personaleIdUuid: e.personaleId,
      dialogTitle: e.fullName.isEmpty ? 'Taglie vestiario' : 'Taglie — ${e.fullName}',
      messenger: _snack,
    );
    if (!mounted) return;
    await _load();
  }

  DataCell _vestAuditCell(
    Widget child,
    Map<String, dynamic> row,
    String fieldKey,
  ) {
    return decorateDataCellWithAuditHover(
      DataCell(child),
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _auditUserNamesByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  String _taglieSummary(_EmpVestSummary e) {
    final parts = <String>[];
    e.taglie.forEach((k, v) {
      final vv = v.trim();
      if (vv.isNotEmpty) parts.add('$k: $vv');
    });
    return parts.join(' · ');
  }

  void _showTaglieDialog(BuildContext context, _EmpVestSummary e) {
    final entries =
        e.taglie.entries.where((kv) => kv.value.trim().isNotEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Taglie dipendente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.fullName,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (e.email.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: SelectableText(
                    e.email,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              if (entries.isEmpty)
                Text(
                  'Nessuna taglia registrata in anagrafica per questo dipendente.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entries
                      .map((kv) => Chip(label: Text('${kv.key}: ${kv.value}')))
                      .toList(),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openTaglieEditor(e);
            },
            child: Text(entries.isEmpty ? 'Inserisci taglie' : 'Modifica taglie'),
          ),
        ],
      ),
    );
  }

  void _showUltimaConsegnaDialog(BuildContext context, _EmpVestSummary e) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          constraints: const BoxConstraints(maxWidth: 720),
          title: const Text('Riepilogo ultima consegna'),
          content: SizedBox(
            width: double.maxFinite,
            child: e.rows.isEmpty
                ? Text(
                    'Nessuna consegna registrata per ${e.fullName}.',
                    style: theme.textTheme.bodyMedium,
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.fullName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (e.email.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: SelectableText(
                              e.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Text(
                          'Dettaglio',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Builder(
                            builder: (bctx) {
                              final tot = e.rows.fold<int>(
                                  0, (a, r) => a + r.quantita);
                              final dataRows = e.rows
                                  .map(
                                    (r) => DataRow(
                                      cells: [
                                        _vestAuditCell(
                                          Text(r.categoria),
                                          r.sourceRow,
                                          'categoria',
                                        ),
                                        _vestAuditCell(
                                          Text('${r.quantita}'),
                                          r.sourceRow,
                                          'quantita_assegnata',
                                        ),
                                        _vestAuditCell(
                                          Text(r.taglia),
                                          r.sourceRow,
                                          'taglia',
                                        ),
                                        _vestAuditCell(
                                          Text(_toDdMmYyyy(r.scadenza)),
                                          r.sourceRow,
                                          'scadenza',
                                        ),
                                        _vestAuditCell(
                                          Text(_toDdMmYyyy(r.dataConsegna)),
                                          r.sourceRow,
                                          'data_consegna',
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList();
                              final bold = theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700);
                              dataRows.add(
                                DataRow(
                                  cells: [
                                    DataCell(Text('Totale', style: bold)),
                                    DataCell(Text('$tot', style: bold)),
                                    const DataCell(SizedBox.shrink()),
                                    const DataCell(SizedBox.shrink()),
                                    const DataCell(SizedBox.shrink()),
                                  ],
                                ),
                              );
                              return DataTable(
                                columns: const [
                                  DataColumn(label: Text('Categoria')),
                                  DataColumn(label: Text('Qta')),
                                  DataColumn(label: Text('Taglia')),
                                  DataColumn(label: Text('Scadenza')),
                                  DataColumn(label: Text('Data consegna')),
                                ],
                                rows: dataRows,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final isMobileLayout = useMobileUi(context) || useCompactPageLayout(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Impostazioni App — Riepilogo Vestiario',
          desktopLogoSize: 40,
        ),
        actions: [
          IconButton(
            tooltip: 'Esporta Excel (vista corrente)',
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    width: isMobileLayout ? cronosFullFieldWidth(context, horizontalMargin: 24) : 360,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        hintText: 'Cerca dipendente o taglia...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<_VestReportFilter>(
                        segments: const [
                          ButtonSegment(
                            value: _VestReportFilter.compilati,
                            label: Text('Compilati'),
                            icon: Icon(Icons.check_circle_outline, size: 18),
                          ),
                          ButtonSegment(
                            value: _VestReportFilter.mancanti,
                            label: Text('Mancanti'),
                            icon: Icon(Icons.person_off_outlined, size: 18),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) => setState(() => _filter = s.first),
                      ),
                      Text(
                        'Compilati: $_countCompilati · Mancanti: $_countMancanti',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      OutlinedButton.icon(
                        onPressed: rows.isEmpty ? null : _exportExcel,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Esporta Excel'),
                      ),
                    ],
                  ),
                  if (_filter == _VestReportFilter.mancanti && _countMancanti > 0) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Dipendenti attivi senza taglie vestiario in anagrafica.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(
                            child: Text(
                              _filter == _VestReportFilter.mancanti
                                  ? 'Tutti i dipendenti attivi hanno almeno una taglia compilata.'
                                  : 'Nessun dipendente con taglie compilate.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final e = rows[i];
                              final hasTaglie = _hasAnyTaglie(e);
                              final summary = _taglieSummary(e);
                              return Card(
                                color: !hasTaglie
                                    ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isMobileLayout) ...[
                                        Text(
                                          e.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (e.email.trim().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            e.email,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: () => _openTaglieEditor(e),
                                            icon: Icon(
                                              hasTaglie ? Icons.edit_outlined : Icons.add,
                                              size: 18,
                                            ),
                                            label: Text(hasTaglie ? 'Modifica taglie' : 'Inserisci taglie'),
                                          ),
                                        ),
                                        if (hasTaglie) ...[
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () => _showTaglieDialog(context, e),
                                              icon: const Icon(Icons.straighten, size: 18),
                                              label: const Text('Visualizza taglie'),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _showUltimaConsegnaDialog(context, e),
                                              icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                              label: const Text('Riepilogo ultima consegna'),
                                            ),
                                          ),
                                        ],
                                      ] else
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 4, top: 2, bottom: 2),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.fullName,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (e.email.trim().isNotEmpty)
                                                    Text(
                                                      e.email,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            FilledButton.icon(
                                              onPressed: () => _openTaglieEditor(e),
                                              icon: Icon(
                                                hasTaglie ? Icons.edit_outlined : Icons.add,
                                                size: 18,
                                              ),
                                              label: Text(
                                                hasTaglie ? 'Modifica taglie' : 'Inserisci taglie',
                                              ),
                                            ),
                                            if (hasTaglie) ...[
                                              OutlinedButton.icon(
                                                onPressed: () => _showTaglieDialog(context, e),
                                                icon: const Icon(Icons.straighten, size: 18),
                                                label: const Text('Visualizza taglie'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: () =>
                                                    _showUltimaConsegnaDialog(context, e),
                                                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                                label: const Text('Riepilogo ultima consegna'),
                                              ),
                                            ],
                                          ],
                                        ),
                                      const SizedBox(height: 6),
                                      Text(
                                        hasTaglie
                                            ? summary
                                            : 'Nessuna taglia registrata — inserimento manuale disponibile.',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: hasTaglie
                                                  ? null
                                                  : Theme.of(context).colorScheme.error,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  String _toDdMmYyyy(String iso) {
    final s = iso.trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year.toString().padLeft(4, '0')}';
  }
}

class _EmpVestSummary {
  final String personaleId;
  final String fullName;
  final String email;
  final List<_VestEntry> rows;
  final Map<String, String> taglie;
  const _EmpVestSummary({
    required this.personaleId,
    required this.fullName,
    required this.email,
    required this.rows,
    required this.taglie,
  });
}

class _VestEntry {
  final String id;
  final String categoria;
  final int quantita;
  final String taglia;
  final String matricola;
  final String scadenza;
  final String dataConsegna;
  final DateTime createdAt;
  final Map<String, dynamic> sourceRow;
  const _VestEntry({
    required this.id,
    required this.categoria,
    required this.quantita,
    required this.taglia,
    required this.matricola,
    required this.scadenza,
    required this.dataConsegna,
    required this.createdAt,
    required this.sourceRow,
  });

  factory _VestEntry.fromRow(Map<String, dynamic> r) => _VestEntry(
        id: (r['id'] ?? '').toString(),
        categoria: (r['categoria'] ?? '').toString(),
        quantita: (r['quantita_assegnata'] is int)
            ? (r['quantita_assegnata'] as int)
            : int.tryParse((r['quantita_assegnata'] ?? '0').toString()) ?? 0,
        taglia: (r['taglia'] ?? '').toString(),
        matricola: (r['matricola'] ?? '').toString(),
        scadenza: (r['scadenza'] ?? '').toString(),
        dataConsegna: (r['data_consegna'] ?? '').toString(),
        createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sourceRow: r,
      );
}

