import 'package:flutter/material.dart';

import '../services/carburante_giustificativi_stats_service.dart';
import '../utils/carburante_giustificativi_excel_export.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/carburante_consumo_modello_panel.dart';
import '../widgets/carburante_giustificativi_riepilogo_panel.dart';
import '../widgets/carburante_soglia_litro_verifica_panel.dart';
import '../widgets/futuristic/gestopro_count_up.dart';
import '../widgets/classic_app_bar_chrome.dart';

class CarburanteGiustificativiRiepilogoPage extends StatefulWidget {
  const CarburanteGiustificativiRiepilogoPage({super.key});

  @override
  State<CarburanteGiustificativiRiepilogoPage> createState() =>
      _CarburanteGiustificativiRiepilogoPageState();
}

class _CarburanteGiustificativiRiepilogoPageState
    extends State<CarburanteGiustificativiRiepilogoPage> {
  bool _loading = true;
  bool _exporting = false;
  int? _selectedYear;
  int? _selectedMonth;
  CarburanteGiustificativiReport _report = const CarburanteGiustificativiReport(
    totals: CarburanteGiustificativiStats(),
    months: [],
  );
  List<Map<String, dynamic>> _rccRows = const [];
  List<Map<String, dynamic>> _mdoRows = const [];
  Map<String, Map<String, dynamic>> _mezziById = const {};
  Map<String, Map<String, dynamic>> _mezziByTarga = const {};

  List<CarburanteConsumoModelloStats> get _consumoMese {
    final y = _selectedYear;
    final m = _selectedMonth;
    if (y == null || m == null) return const [];
    return CarburanteGiustificativiStatsService.buildConsumoPerModello(
      rccRows: _rccRows,
      mezziById: _mezziById,
      mezziByTarga: _mezziByTarga,
      year: y,
      month: m,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await CarburanteGiustificativiStatsService.loadWithRows();
      if (!mounted) return;
      setState(() {
        _report = data.report;
        _rccRows = data.rccRows;
        _mdoRows = data.mdoRows;
        _mezziById = data.mezziById;
        _mezziByTarga = data.mezziByTarga;
        syncCarburanteRiepilogoMonthSelection(
          report: _report,
          currentYear: _selectedYear,
          currentMonth: _selectedMonth,
          apply: (y, m) {
            _selectedYear = y;
            _selectedMonth = m;
          },
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento: $e');
    }
  }

  CarburanteGiustificativiMonthBucket? get _selectedBucket {
    if (_selectedYear == null || _selectedMonth == null) return null;
    for (final bucket in _report.months) {
      if (bucket.year == _selectedYear && bucket.month == _selectedMonth) {
        return bucket;
      }
    }
    return null;
  }

  Future<void> _exportExcel() async {
    final year = _selectedYear;
    final month = _selectedMonth;
    final bucket = _selectedBucket;
    if (year == null || month == null || bucket == null) {
      ModifyFeedback.hint(context, 'Seleziona un mese con dati da esportare.');
      return;
    }
    setState(() => _exporting = true);
    try {
      final rccMonth = CarburanteGiustificativiStatsService.filterRowsForMonth(
        _rccRows,
        year,
        month,
      );
      final mdoMonth = CarburanteGiustificativiStatsService.filterRowsForMonth(
        _mdoRows,
        year,
        month,
      );
      final bytes = CarburanteGiustificativiExcelExport.build(
        year: year,
        month: month,
        stats: bucket.stats,
        rccRows: rccMonth,
        mdoRows: mdoMonth,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: CarburanteGiustificativiExcelExport.fileNameForMonth(
          year,
          month,
        ),
        bytes: bytes,
      );
      if (!mounted) return;
      if (!saved) {
        ModifyFeedback.hint(context, 'Export annullato.');
        return;
      }
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ModifyFeedback.success(
        context,
        p.isEmpty ? 'Export Excel completato.' : 'Export Excel completato.\n$p',
      );
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _onYearChanged(int year) {
    setState(() {
      _selectedYear = year;
      final nextMonths = _report.months
          .where((m) => m.year == year)
          .map((m) => m.month)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));
      _selectedMonth = nextMonths.contains(_selectedMonth)
          ? _selectedMonth
          : (nextMonths.isEmpty ? null : nextMonths.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Riepilogo giustificativi';
    final toolbarActions = <Widget>[
      IconButton(
        tooltip: 'Export Excel',
        onPressed: _loading || _exporting ? null : _exportExcel,
        icon: _exporting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.table_chart_outlined),
      ),
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ];

    final panel = CarburanteGiustificativiRiepilogoPanel(
      loading: _loading,
      report: _report,
      selectedYear: _selectedYear,
      selectedMonth: _selectedMonth,
      onYearChanged: _onYearChanged,
      onMonthChanged: (m) => setState(() => _selectedMonth = m),
    );

    final gestopro = isGestoproFuturisticUi(context);
    final countUpKey =
        '${_selectedYear ?? 0}_${_selectedMonth ?? 0}_${_loading ? 1 : 0}';

    final scrollBody = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        gestopro ? 8 : 12,
        16,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: GestoproCountUpScope(
            enabled: gestopro && !_loading,
            restartKey: countUpKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                panel,
                const SizedBox(height: 16),
                CarburanteConsumoModelloPanel(
                  loading: _loading,
                  rows: _consumoMese,
                  year: _selectedYear,
                  month: _selectedMonth,
                ),
                const SizedBox(height: 16),
                CarburanteSogliaLitroVerificaPanel(
                  loading: _loading,
                  selectedYear: _selectedYear,
                  selectedMonth: _selectedMonth,
                  rccRows: _rccRows,
                  mdoRows: _mdoRows,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final body = gestopro
        ? scrollBody
        : PageWithTopLogo(child: scrollBody);

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: toolbarActions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: pageTitle),
        actions: toolbarActions,
      )),
      body: body,
    );
  }
}
