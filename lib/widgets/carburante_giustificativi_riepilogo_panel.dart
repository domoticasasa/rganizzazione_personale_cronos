import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/carburante_giustificativi_stats_service.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/gestopro_data_palette.dart';
import '../utils/gestopro_page_chrome.dart';
import 'futuristic/gestopro_count_up.dart';
import 'carburante_giustificativi_charts.dart';

/// Pannello riepilogo giustificativi (filtri mese + card statistiche).
class CarburanteGiustificativiRiepilogoPanel extends StatelessWidget {
  const CarburanteGiustificativiRiepilogoPanel({
    super.key,
    required this.loading,
    required this.report,
    required this.selectedYear,
    required this.selectedMonth,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  final bool loading;
  final CarburanteGiustificativiReport report;
  final int? selectedYear;
  final int? selectedMonth;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;

  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');
  static final NumberFormat _euroLitroFmt =
      NumberFormat('#,##0.000', 'it_IT');

  static const List<String> monthNames = <String>[
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];

  String _fmtNum(double v) => _numFmt.format(v);

  List<int> _availableYears() {
    final years = report.months.map((m) => m.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<int> _availableMonthsForYear() {
    if (selectedYear == null) return const [];
    final months = report.months
        .where((m) => m.year == selectedYear)
        .map((m) => m.month)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return months;
  }

  CarburanteGiustificativiMonthBucket? _selectedBucket() {
    if (selectedYear == null || selectedMonth == null) return null;
    for (final bucket in report.months) {
      if (bucket.year == selectedYear && bucket.month == selectedMonth) {
        return bucket;
      }
    }
    return null;
  }

  Color _rccAccent(BuildContext context, ThemeData theme) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.electricBright
        : theme.colorScheme.primary;
  }

  Color _mdoAccent(BuildContext context, ThemeData theme) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonPurple
        : theme.colorScheme.tertiary;
  }

  Color _totalAccent(BuildContext context, ThemeData theme) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonCyan
        : theme.colorScheme.secondary;
  }

  Color _benzinaAccent(BuildContext context) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonGreen
        : const Color(0xFF2E7D32);
  }

  Color _gasolioAccent(BuildContext context) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonOrange
        : const Color(0xFFE65100);
  }

  Color _adBlueAccent(BuildContext context) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF1565C0);
  }

  Color _hvoAccent(BuildContext context) {
    return isGestoproFuturisticUi(context)
        ? CronosFuturisticTheme.neonPurple
        : const Color(0xFF6A1B9A);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GestoproDataPalette.of(context);
    if (loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedBucket = _selectedBucket();
    final years = _availableYears();
    final monthsForYear = _availableMonthsForYear();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dettaglio mese',
          style: TextStyle(
            fontSize: GestoproDataPalette.fsTitle,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (report.months.isEmpty)
          Text(
            'Nessun giustificativo con data rifornimento.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: years.contains(selectedYear)
                      ? selectedYear
                      : years.first,
                  items: years
                      .map(
                        (y) => DropdownMenuItem<int>(
                          value: y,
                          child: Text('$y'),
                        ),
                      )
                      .toList(),
                  onChanged: (y) {
                    if (y == null) return;
                    onYearChanged(y);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Anno',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: monthsForYear.contains(selectedMonth)
                      ? selectedMonth
                      : (monthsForYear.isEmpty ? null : monthsForYear.first),
                  items: monthsForYear
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text(monthNames[m - 1]),
                        ),
                      )
                      .toList(),
                  onChanged: monthsForYear.isEmpty
                      ? null
                      : (m) {
                          if (m == null) return;
                          onMonthChanged(m);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Mese',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selectedBucket != null) ...[
            _statsRow(context, theme, selectedBucket.stats),
            const SizedBox(height: 12),
            _fuelTypeRow(context, theme, selectedBucket.stats.perTipo),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Benzina, Gasolio, HVO e AdBlue includono RCC e MDO con tipo carburante indicato.',
                style: TextStyle(
                  fontSize: GestoproDataPalette.fsTiny,
                  color: GestoproDataPalette.of(context).textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
            CarburanteGiustificativiCharts(stats: selectedBucket.stats),
          ] else
            Text(
              'Nessun dato per il mese selezionato.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }

  Widget _fuelTypeRow(
    BuildContext context,
    ThemeData theme,
    CarburantePerTipoStats perTipo,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final children = [
          _tipoSection(
            context,
            theme,
            title: 'Totale Benzina',
            totals: perTipo.benzina,
            accent: _benzinaAccent(context),
          ),
          _tipoSection(
            context,
            theme,
            title: 'Totale Gasolio',
            totals: perTipo.gasolio,
            accent: _gasolioAccent(context),
          ),
          _tipoSection(
            context,
            theme,
            title: 'Totale HVO',
            totals: perTipo.hvo,
            accent: _hvoAccent(context),
          ),
          _tipoSection(
            context,
            theme,
            title: 'Totale AdBlue',
            totals: perTipo.adBlue,
            accent: _adBlueAccent(context),
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _tipoSection(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required CarburanteTipoTotals totals,
    required Color accent,
  }) {
    final palette = GestoproDataPalette.of(context);
    return Container(
      padding: GestoproDataPalette.padCard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(palette.radius),
        color: accent.withValues(alpha: palette.futuristic ? 0.12 : 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTitle,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          _metricCount(context, theme, 'Giustificativi', totals.count),
          _metricLitri(context, theme, totals.litri),
          _metricEuro(context, theme, totals.euro),
          _metricEuroLitro(
            context,
            theme,
            euro: totals.euro,
            litri: totals.litri,
          ),
        ],
      ),
    );
  }

  Widget _statsRow(
    BuildContext context,
    ThemeData theme,
    CarburanteGiustificativiStats stats,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(
                context,
                theme,
                title: 'RCC Stradali',
                count: stats.rccCount,
                litri: stats.rccLitri,
                euro: stats.rccEuro,
                accent: _rccAccent(context, theme),
              ),
              const SizedBox(height: 8),
              _section(
                context,
                theme,
                title: 'MDO',
                count: stats.mdoCount,
                litri: stats.mdoLitri,
                euro: stats.mdoEuro,
                accent: _mdoAccent(context, theme),
              ),
              const SizedBox(height: 8),
              _section(
                context,
                theme,
                title: 'Totale',
                count: stats.totalCount,
                litri: stats.totalLitri,
                euro: stats.totalEuro,
                accent: _totalAccent(context, theme),
                emphasized: true,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _section(
                context,
                theme,
                title: 'RCC Stradali',
                count: stats.rccCount,
                litri: stats.rccLitri,
                euro: stats.rccEuro,
                accent: _rccAccent(context, theme),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _section(
                context,
                theme,
                title: 'MDO',
                count: stats.mdoCount,
                litri: stats.mdoLitri,
                euro: stats.mdoEuro,
                accent: _mdoAccent(context, theme),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _section(
                context,
                theme,
                title: 'Totale',
                count: stats.totalCount,
                litri: stats.totalLitri,
                euro: stats.totalEuro,
                accent: _totalAccent(context, theme),
                emphasized: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required int count,
    required double litri,
    required double euro,
    required Color accent,
    bool emphasized = false,
  }) {
    final palette = GestoproDataPalette.of(context);
    return Container(
      padding: GestoproDataPalette.padCard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(palette.radius),
        color: accent.withValues(alpha: emphasized ? 0.16 : 0.1),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTitle,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          _metricCount(context, theme, 'Giustificativi', count),
          _metricLitri(context, theme, litri),
          _metricEuro(context, theme, euro),
          _metricEuroLitro(context, theme, euro: euro, litri: litri),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    ThemeData theme,
    String label,
    Widget value,
  ) {
    final palette = GestoproDataPalette.of(context);
    final valueStyle = TextStyle(
      fontSize: GestoproDataPalette.fsLabel,
      fontWeight: FontWeight.w700,
      color: palette.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: GestoproDataPalette.fsLabel,
                color: palette.textMuted,
              ),
            ),
          ),
          DefaultTextStyle(style: valueStyle, child: value),
        ],
      ),
    );
  }

  Widget _metricCount(
    BuildContext context,
    ThemeData theme,
    String label,
    int count,
  ) {
    final palette = GestoproDataPalette.of(context);
    return _metric(
      context,
      theme,
      label,
      GestoproCountUpText(
        target: count.toDouble(),
        format: (v) => _numFmt.format(v.round()),
        style: TextStyle(
          fontSize: GestoproDataPalette.fsLabel,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
    );
  }

  Widget _metricLitri(BuildContext context, ThemeData theme, double litri) {
    final palette = GestoproDataPalette.of(context);
    return _metric(
      context,
      theme,
      'Litri',
      GestoproCountUpText(
        target: litri,
        format: (v) => '${_fmtNum(v)} L',
        style: TextStyle(
          fontSize: GestoproDataPalette.fsLabel,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
    );
  }

  Widget _metricEuro(BuildContext context, ThemeData theme, double euro) {
    final palette = GestoproDataPalette.of(context);
    return _metric(
      context,
      theme,
      'Euro',
      GestoproCountUpText(
        target: euro,
        format: (v) => '€ ${_fmtNum(v)}',
        style: TextStyle(
          fontSize: GestoproDataPalette.fsLabel,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
    );
  }

  Widget _metricEuroLitro(
    BuildContext context,
    ThemeData theme, {
    required double euro,
    required double litri,
  }) {
    final palette = GestoproDataPalette.of(context);
    if (litri <= 0) {
      return _metric(context, theme, '€/litro medio', const Text('—'));
    }
    final target = euro / litri;
    return _metric(
      context,
      theme,
      '€/litro medio',
      GestoproCountUpText(
        target: target,
        format: (v) => '€ ${_euroLitroFmt.format(v)}/L',
        style: TextStyle(
          fontSize: GestoproDataPalette.fsLabel,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

/// Sincronizza anno/mese selezionati dopo caricamento report.
void syncCarburanteRiepilogoMonthSelection({
  required CarburanteGiustificativiReport report,
  required int? currentYear,
  required int? currentMonth,
  required void Function(int? year, int? month) apply,
}) {
  if (report.months.isEmpty) {
    apply(null, null);
    return;
  }

  final stillValid = currentYear != null &&
      currentMonth != null &&
      report.months.any(
        (m) => m.year == currentYear && m.month == currentMonth,
      );
  if (stillValid) return;

  final now = DateTime.now();
  final hasCurrent = report.months.any(
    (m) => m.year == now.year && m.month == now.month,
  );
  if (hasCurrent) {
    apply(now.year, now.month);
    return;
  }

  final first = report.months.first;
  apply(first.year, first.month);
}
