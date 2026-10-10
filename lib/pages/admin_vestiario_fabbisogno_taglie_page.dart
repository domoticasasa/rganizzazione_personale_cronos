import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/supabase_service.dart';
import '../services/vestiario_fabbisogno_service.dart';
import '../utils/gestopro_data_palette.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../utils/responsive.dart';
import '../utils/vestiario_catalog.dart';
import '../widgets/cronos_app_background.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminVestiarioFabbisognoTagliePage extends StatefulWidget {
  const AdminVestiarioFabbisognoTagliePage({super.key});

  @override
  State<AdminVestiarioFabbisognoTagliePage> createState() =>
      _AdminVestiarioFabbisognoTagliePageState();
}

class _AdminVestiarioFabbisognoTagliePageState
    extends State<AdminVestiarioFabbisognoTagliePage> {
  late GestoproDataPalette _palette;
  bool _loading = true;
  bool _saving = false;
  int _activePersonnelCount = 0;
  int _compiledPersonnelCount = 0;

  final Map<String, int> _multiplierEstivo = <String, int>{
    'tshirt': 1,
    'pantalone': 1,
    'felpa': 1,
    VestiarioCatalog.articoloGiaccaLeggera: 1,
    'gilet': 1,
    'scarpe': 1,
  };
  final Map<String, int> _multiplierInvernale = <String, int>{
    'tshirt': 1,
    'pantalone': 1,
    'felpa': 1,
    VestiarioCatalog.articoloGiaccaInvernale: 1,
    'gilet': 1,
    'guanti_pelle': 1,
    'guanti_tessuto': 1,
    'scarpe': 1,
  };
  final Map<String, int> _legacyMultiplier = <String, int>{
    'tshirt': 1,
    'pantalone': 1,
    'felpa': 1,
    'giacca': 1,
    'gilet': 1,
    'scarpe': 1,
    'guanti_pelle': 1,
    'guanti_tessuto': 1,
  };

  final List<_ItemAgg> _rows = <_ItemAgg>[];
  final Map<String, int> _lastSavedEstivo = <String, int>{};
  final Map<String, int> _lastSavedInvernale = <String, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadMultipliers();
      await _loadAggregations();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore caricamento fabbisogno: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMultipliers() async {
    try {
      final loaded = await VestiarioFabbisognoService.loadMultipliers();
      _multiplierEstivo
        ..clear()
        ..addAll(loaded.estivo);
      _multiplierInvernale
        ..clear()
        ..addAll(loaded.invernale);
      for (final k in _legacyMultiplier.keys) {
        _legacyMultiplier[k] = loaded.invernale[k] ?? loaded.estivo[k] ?? 1;
      }
    } catch (_) {
      // tabella non presente: fallback ai default locali.
    } finally {
      _lastSavedEstivo
        ..clear()
        ..addAll(_multiplierEstivo);
      _lastSavedInvernale
        ..clear()
        ..addAll(_multiplierInvernale);
    }
  }

  Future<void> _loadAggregations() async {
    final aggregations = await VestiarioFabbisognoService.loadAggregations();
    final activeRows = await SupabaseService.client
        .from('personale')
        .select('id_uuid')
        .eq('active', true);
    final active = (activeRows as List)
        .map((e) => (e['id_uuid'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final taglieRows = await SupabaseService.client.from('personale_taglie').select(
        'personale_id, taglia_tshirt, taglia_pantalone, taglia_felpa, taglia_giacca, taglia_gilet, taglia_scarpe, taglia_guanti');
    final compiledPersonnel = <String>{};
    for (final raw in (taglieRows as List)) {
      final r = Map<String, dynamic>.from(raw as Map);
      final pid = (r['personale_id'] ?? '').toString().trim();
      if (!active.contains(pid)) continue;
      final hasAny = [
        r['taglia_tshirt'],
        r['taglia_pantalone'],
        r['taglia_felpa'],
        r['taglia_giacca'],
        r['taglia_gilet'],
        r['taglia_scarpe'],
        r['taglia_guanti'],
      ].any((v) => (v ?? '').toString().trim().isNotEmpty);
      if (hasAny) compiledPersonnel.add(pid);
    }

    final out = aggregations
        .map((r) => _ItemAgg(item: r.item, size: r.size, employeeCount: r.employeeCount))
        .toList(growable: false);

    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(out);
      _activePersonnelCount = active.length;
      _compiledPersonnelCount = compiledPersonnel.length;
    });
  }

  Future<void> _saveMultipliers() async {
    setState(() => _saving = true);
    final changes = _collectMultiplierChanges();
    try {
      await VestiarioFabbisognoService.saveMultipliers(
        estivo: Map<String, int>.from(_multiplierEstivo),
        invernale: Map<String, int>.from(_multiplierInvernale),
      );
      if (!mounted) return;
      _lastSavedEstivo
        ..clear()
        ..addAll(_multiplierEstivo);
      _lastSavedInvernale
        ..clear()
        ..addAll(_multiplierInvernale);
      await _showSaveResultDialog(
        saved: true,
        changes: changes,
      );
    } catch (e) {
      if (!mounted) return;
      await _showSaveResultDialog(
        saved: false,
        changes: changes,
        errorText: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _collectMultiplierChanges() {
    final out = <String>[];
    for (final key in _multiplierEstivo.keys) {
      final oldVal = _lastSavedEstivo[key] ?? _multiplierEstivo[key] ?? 0;
      final newVal = _multiplierEstivo[key] ?? 0;
      if (oldVal != newVal) {
        out.add('${VestiarioCatalog.label(key)} estivo: $oldVal -> $newVal');
      }
    }
    for (final key in _multiplierInvernale.keys) {
      final oldVal = _lastSavedInvernale[key] ?? _multiplierInvernale[key] ?? 0;
      final newVal = _multiplierInvernale[key] ?? 0;
      if (oldVal != newVal) {
        out.add('${VestiarioCatalog.label(key)} invernale: $oldVal -> $newVal');
      }
    }
    return out;
  }

  Future<void> _showSaveResultDialog({
    required bool saved,
    required List<String> changes,
    String? errorText,
  }) async {
    if (!mounted) return;
    final title = saved ? 'Salvataggio completato' : 'Salvataggio non riuscito';
    final icon = saved ? Icons.check_circle_outline : Icons.error_outline;
    final color = saved ? Colors.green : Colors.red;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(saved ? 'Dati salvati correttamente.' : 'Si e verificato un errore durante il salvataggio.'),
                if ((errorText ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dettaglio: $errorText',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Modifiche:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (changes.isEmpty)
                  const Text('Nessuna modifica rilevata.')
                else
                  ...changes.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('- $c'),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportRiepilogoExcel({
    required String stagione,
    required List<String> itemKeys,
    required Map<String, List<_ItemAgg>> grouped,
    required Map<String, int> bySeason,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheetName = 'Riepilogo ${stagione[0].toUpperCase()}${stagione.substring(1)}';
      final sheet = excel[sheetName];
      sheet.appendRow([
        'Stagione',
        'Articolo',
        'Taglia',
        'N. dipendenti',
        'Moltiplicatore',
        'Fabbisogno',
      ]);
      for (final item in itemKeys) {
        final rows = grouped[item] ?? const <_ItemAgg>[];
        for (final r in rows) {
          final need = _annualNeed(r, bySeason);
          sheet.appendRow([
            stagione,
            VestiarioCatalog.label(item),
            r.size,
            r.employeeCount,
            bySeason[item] ?? 0,
            need,
          ]);
        }
      }
      final encoded = excel.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Impossibile generare file Excel');
      }
      final bytes = Uint8List.fromList(encoded);
      final stamp = DateTime.now();
      final stampStr =
          '${stamp.year.toString().padLeft(4, '0')}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}';
      final fileName = 'riepilogo_fabbisogno_${stagione}_$stampStr.xlsx';

      if (!kIsWeb && Platform.isWindows) {
        final downloads = p.join(
          Platform.environment['USERPROFILE'] ?? Directory.current.path,
          'Downloads',
        );
        final outFile = File(p.join(downloads, fileName));
        await outFile.writeAsBytes(bytes, flush: true);
        await _openFolderAndSelect(outFile.path);
        await _openFile(outFile.path);
      } else {
        await FileSaver.instance.saveFile(
          name: fileName.replaceAll('.xlsx', ''),
          bytes: bytes,
          ext: 'xlsx',
          mimeType: MimeType.other,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export riepilogo $stagione completato')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export $stagione non riuscito: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFolderAndSelect(String path) async {
    if (kIsWeb || !Platform.isWindows) return;
    await Process.run('explorer', ['/select,', path]);
  }

  Future<void> _openFile(String path) async {
    if (kIsWeb || !Platform.isWindows) return;
    await Process.run('cmd', ['/c', 'start', '', path]);
  }

  int _annualNeed(_ItemAgg r, Map<String, int> bySeason) =>
      r.employeeCount * (bySeason[r.item] ?? 1);
  int get _missingPersonnelCount =>
      (_activePersonnelCount - _compiledPersonnelCount).clamp(0, 1 << 30);
  double get _compiledPercentage {
    if (_activePersonnelCount == 0) return 0;
    return (_compiledPersonnelCount / _activePersonnelCount) * 100;
  }

  bool _narrowLayout(BuildContext context) =>
      useMobileUi(context) || useCompactPageLayout(context);

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _palette.textMuted),
      border: OutlineInputBorder(borderSide: BorderSide(color: _palette.border)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _palette.border)),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _palette.estivo, width: 1.4),
      ),
      filled: _palette.futuristic,
      fillColor: _palette.futuristic ? _palette.canvas : null,
      isDense: true,
    );
  }

  TextStyle get _titleStyle => TextStyle(
        fontWeight: FontWeight.w700,
        color: _palette.textPrimary,
        fontSize: GestoproDataPalette.fsTitle,
      );

  TextStyle get _bodyStyle => TextStyle(
        color: _palette.textPrimary,
        fontSize: GestoproDataPalette.fsBody,
      );

  TextStyle get _mutedStyle => TextStyle(
        color: _palette.textMuted,
        fontSize: GestoproDataPalette.fsLabel,
      );

  Widget _surfaceCard({required Widget child, EdgeInsets? padding}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(_palette.radius),
        border: Border.all(color: _palette.border),
        boxShadow: _palette.cardShadow,
      ),
      child: Padding(
        padding: padding ?? GestoproDataPalette.padCard,
        child: child,
      ),
    );
  }

  Widget _dataTable({
    required List<_ItemAgg> rows,
    required String item,
    required Map<String, int> seasonMap,
  }) {
    Text cell(String v, {Color? color, FontWeight? weight}) => Text(
          v,
          style: TextStyle(
            color: color ?? _palette.textPrimary,
            fontSize: GestoproDataPalette.fsBody,
            fontWeight: weight,
          ),
        );

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: _palette.border,
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(
            _palette.panelHeader,
          ),
          headingTextStyle: TextStyle(
            color: _palette.tableHeader,
            fontWeight: FontWeight.w700,
            fontSize: GestoproDataPalette.fsLabel,
          ),
          dataTextStyle: TextStyle(
            color: _palette.textPrimary,
            fontSize: GestoproDataPalette.fsBody,
          ),
        ),
      ),
      child: DataTable(
        columns: [
          DataColumn(label: cell('Taglia', weight: FontWeight.w700)),
          DataColumn(label: cell('N. dipendenti', weight: FontWeight.w700)),
          DataColumn(label: cell('Moltiplicatore annuo', weight: FontWeight.w700)),
          DataColumn(label: cell('Fabbisogno', weight: FontWeight.w700)),
        ],
        rows: rows
            .map(
              (r) => DataRow(
                cells: [
                  DataCell(cell(r.size)),
                  DataCell(cell('${r.employeeCount}')),
                  DataCell(cell('${seasonMap[item]}')),
                  DataCell(cell('${_annualNeed(r, seasonMap)}')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _multiplierDropdown({
    required String itemKey,
    required int value,
    required ValueChanged<int> onChanged,
    required bool narrow,
  }) {
    final field = DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: _palette.surface,
      style: TextStyle(color: _palette.textPrimary, fontSize: GestoproDataPalette.fsBody),
      decoration: _fieldDecoration('${VestiarioCatalog.label(itemKey)} / anno'),
      items: List.generate(
        21,
        (i) => DropdownMenuItem(
          value: i,
          child: Text('$i', style: TextStyle(color: _palette.textPrimary)),
        ),
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: field,
      );
    }
    return SizedBox(width: 170, child: field);
  }

  Widget _multiplierSection({
    required String title,
    required List<String> keys,
    required Map<String, int> values,
    required void Function(String key, int value) onChanged,
    required bool narrow,
  }) {
    final fields = keys
        .map(
          (k) => _multiplierDropdown(
            itemKey: k,
            value: values[k] ?? 1,
            onChanged: (v) => onChanged(k, v),
            narrow: narrow,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _titleStyle),
        const SizedBox(height: 6),
        if (narrow)
          ...fields
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: fields,
          ),
      ],
    );
  }

  Widget _actionButtons({
    required bool narrow,
    required List<String> estivoKeys,
    required List<String> invernaleKeys,
    required Map<String, List<_ItemAgg>> grouped,
  }) {
    Widget btn(Widget child) {
      if (!narrow) return child;
      return SizedBox(width: double.infinity, child: child);
    }

    final children = [
      btn(
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => _exportRiepilogoExcel(
                    stagione: 'estivo',
                    itemKeys: estivoKeys,
                    grouped: grouped,
                    bySeason: _multiplierEstivo,
                  ),
          icon: Icon(Icons.file_download_outlined, color: _palette.estivo),
          label: Text(
            narrow ? 'Export estivo' : 'Export riepilogo estivo',
            style: TextStyle(color: _palette.estivo),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _palette.estivo.withValues(alpha: 0.6)),
          ),
        ),
      ),
      btn(
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => _exportRiepilogoExcel(
                    stagione: 'invernale',
                    itemKeys: invernaleKeys,
                    grouped: grouped,
                    bySeason: _multiplierInvernale,
                  ),
          icon: Icon(Icons.file_download_outlined, color: _palette.invernale),
          label: Text(
            narrow ? 'Export invernale' : 'Export riepilogo invernale',
            style: TextStyle(color: _palette.invernale),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _palette.invernale.withValues(alpha: 0.6)),
          ),
        ),
      ),
      btn(
        FilledButton.icon(
          onPressed: _saving ? null : _saveMultipliers,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Salva'),
        ),
      ),
    ];

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: children,
      ),
    );
  }

  Widget _buildSeasonSection({
    required BuildContext context,
    required String title,
    required List<String> itemKeys,
    required Map<String, List<_ItemAgg>> grouped,
    required Map<String, int> bySeason,
    required Map<String, int> invernaleSeason,
    required bool isMobileLayout,
  }) {
    final items = itemKeys.where(grouped.containsKey).toList();
    final seasonTotal = items.fold<int>(
      0,
      (a, item) => a + grouped[item]!.fold<int>(0, (x, r) => x + _annualNeed(r, bySeason)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: isMobileLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _titleStyle.copyWith(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Fabbisogno stagione: $seasonTotal', style: _mutedStyle),
                  ],
                )
              : Row(
                  children: [
                    Text(title, style: _titleStyle.copyWith(fontSize: 16)),
                    const SizedBox(width: 10),
                    Text('Fabbisogno stagione: $seasonTotal', style: _mutedStyle),
                  ],
                ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Nessun dato disponibile per questa stagione.', style: _mutedStyle),
          )
        else
          ...items.map((item) {
            final rows = grouped[item]!;
            final totalDip = rows.fold<int>(0, (a, r) => a + r.employeeCount);
            final totalNeed = rows.fold<int>(0, (a, r) => a + _annualNeed(r, bySeason));
            final totalNeedInvernale =
                rows.fold<int>(0, (a, r) => a + _annualNeed(r, invernaleSeason));

            Widget buildTablePanel({
              required String tableTitle,
              required Map<String, int> seasonMap,
              required bool invernalePanel,
            }) {
              final accent = invernalePanel ? _palette.invernale : _palette.estivo;
              final bg = invernalePanel ? _palette.invernaleBg : _palette.estivoBg;
              return Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(_palette.radius),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tableTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontSize: GestoproDataPalette.fsLabel,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _dataTable(
                            rows: rows,
                            item: item,
                            seasonMap: seasonMap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      VestiarioCatalog.label(item),
                      style: _titleStyle.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dipendenti: $totalDip · Moltiplicatore: ${bySeason[item]} · '
                      'Fabbisogno: $totalNeed · Fabbisogno invernale: $totalNeedInvernale',
                      style: _mutedStyle,
                    ),
                    const SizedBox(height: 8),
                    if (isMobileLayout)
                      ...rows.map(
                        (r) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Taglia ${r.size}', style: _bodyStyle),
                          subtitle: Text(
                            'Dipendenti: ${r.employeeCount} · Moltiplicatore: ${bySeason[item]}',
                            style: _mutedStyle,
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _palette.invernaleBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _palette.invernale.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              'Inv ${_annualNeed(r, invernaleSeason)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: GestoproDataPalette.fsTiny,
                                color: _palette.invernale,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildTablePanel(
                            tableTitle: 'Fabbisogno ${title.toLowerCase()}',
                            seasonMap: bySeason,
                            invernalePanel: false,
                          ),
                          const SizedBox(width: 10),
                          buildTablePanel(
                            tableTitle: 'Fabbisogno invernale',
                            seasonMap: invernaleSeason,
                            invernalePanel: true,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _palette = GestoproDataPalette.of(context);
    final narrow = _narrowLayout(context);
    final grouped = <String, List<_ItemAgg>>{};
    for (final r in _rows) {
      grouped.putIfAbsent(r.item, () => <_ItemAgg>[]).add(r);
    }
    final estivoKeys = VestiarioCatalog.articoliPerStagione('estivo');
    final invernaleKeys = VestiarioCatalog.articoliPerStagione('invernale');
    final pageTitle = narrow ? 'Fabbisogno' : 'Fabbisogno taglie';
    final toolbarActions = <Widget>[
      IconButton(
        tooltip: 'Ricarica',
        onPressed: _loading ? null : _load,
        icon: Icon(
          Icons.refresh,
          color: _palette.futuristic ? _palette.textPrimary : null,
        ),
      ),
      const SizedBox(width: 4),
    ];

    final scrollBody = _loading
        ? Center(
            child: CircularProgressIndicator(
              color: _palette.futuristic ? _palette.estivo : null,
            ),
          )
        : CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _surfaceCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'Compilazione vestiario: ${_compiledPercentage.toStringAsFixed(1)}%',
                                  style: _titleStyle,
                                ),
                                Text(
                                  'Compilati: $_compiledPersonnelCount / $_activePersonnelCount',
                                  style: _bodyStyle,
                                ),
                                Text(
                                  'Mancano: $_missingPersonnelCount',
                                  style: _bodyStyle,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _multiplierSection(
                              title: 'Quantità estivo',
                              keys: estivoKeys,
                              values: _multiplierEstivo,
                              onChanged: (k, v) => setState(() => _multiplierEstivo[k] = v),
                              narrow: narrow,
                            ),
                            const SizedBox(height: 12),
                            _multiplierSection(
                              title: 'Quantità invernale',
                              keys: invernaleKeys,
                              values: _multiplierInvernale,
                              onChanged: (k, v) => setState(() => _multiplierInvernale[k] = v),
                              narrow: narrow,
                            ),
                            const SizedBox(height: 12),
                            _actionButtons(
                              narrow: narrow,
                              estivoKeys: estivoKeys,
                              invernaleKeys: invernaleKeys,
                              grouped: grouped,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverToBoxAdapter(
                      child: _buildSeasonSection(
                        context: context,
                        title: 'Vestiario estivo',
                        itemKeys: estivoKeys,
                        grouped: grouped,
                        isMobileLayout: narrow,
                        bySeason: _multiplierEstivo,
                        invernaleSeason: _multiplierInvernale,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(
                      child: _buildSeasonSection(
                        context: context,
                        title: 'Vestiario invernale',
                        itemKeys: invernaleKeys,
                        grouped: grouped,
                        isMobileLayout: narrow,
                        bySeason: _multiplierInvernale,
                        invernaleSeason: _multiplierInvernale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: toolbarActions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text(pageTitle),
        actions: toolbarActions,
      )),
      wrapClassicBody: (ctx, child) => Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: CronosAppBackground()),
          ColoredBox(
            color: _palette.canvas.withValues(alpha: 0.92),
            child: child,
          ),
        ],
      ),
      body: scrollBody,
    );
  }
}

class _ItemAgg {
  final String item;
  final String size;
  final int employeeCount;
  const _ItemAgg({
    required this.item,
    required this.size,
    required this.employeeCount,
  });
}

