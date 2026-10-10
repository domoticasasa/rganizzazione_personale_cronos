import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/carburante_giustificativi_stats_service.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/gestopro_data_palette.dart';
import '../utils/gestopro_page_chrome.dart';
import 'futuristic/gestopro_count_up.dart';

/// Grafici riepilogo carburante (barre litri per categoria + donut ripartizione).
class CarburanteGiustificativiCharts extends StatelessWidget {
  const CarburanteGiustificativiCharts({
    super.key,
    required this.stats,
  });

  final CarburanteGiustificativiStats stats;

  @override
  Widget build(BuildContext context) {
    final palette = GestoproDataPalette.of(context);
    final gestopro = isGestoproFuturisticUi(context);

    final benzinaColor = gestopro
        ? CronosFuturisticTheme.neonGreen
        : const Color(0xFF2E7D32);
    final gasolioColor = gestopro
        ? CronosFuturisticTheme.neonOrange
        : const Color(0xFFE65100);
    final hvoColor = gestopro
        ? CronosFuturisticTheme.neonPurple
        : const Color(0xFF6A1B9A);
    final adBlueColor = gestopro
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF1565C0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 820;
        final barChart = _chartCard(
          palette: palette,
          title: 'Litri per categoria',
          subtitle: 'Benzina, Gasolio, HVO e AdBlue nel mese selezionato',
          child: _LitriPerCategoriaBarChart(
            palette: palette,
            benzinaLitri: stats.perTipo.benzina.litri,
            gasolioLitri: stats.perTipo.gasolio.litri,
            hvoLitri: stats.perTipo.hvo.litri,
            adBlueLitri: stats.perTipo.adBlue.litri,
            benzinaColor: benzinaColor,
            gasolioColor: gasolioColor,
            hvoColor: hvoColor,
            adBlueColor: adBlueColor,
          ),
        );
        final donutChart = _chartCard(
          palette: palette,
          title: 'Confronto RCC / MDO',
          subtitle: 'Litri per fonte nel mese selezionato',
          child: _RccMdoDonutChart(
            palette: palette,
            gestopro: gestopro,
            rccLitri: stats.rccLitri,
            mdoLitri: stats.mdoLitri,
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              barChart,
              const SizedBox(height: 12),
              donutChart,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: barChart),
            const SizedBox(width: 12),
            Expanded(child: donutChart),
          ],
        );
      },
    );
  }

  Widget _chartCard({
    required GestoproDataPalette palette,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(palette.radius),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTiny,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LitriPerCategoriaBarChart extends StatelessWidget {
  const _LitriPerCategoriaBarChart({
    required this.palette,
    required this.benzinaLitri,
    required this.gasolioLitri,
    required this.hvoLitri,
    required this.adBlueLitri,
    required this.benzinaColor,
    required this.gasolioColor,
    required this.hvoColor,
    required this.adBlueColor,
  });

  final GestoproDataPalette palette;
  final double benzinaLitri;
  final double gasolioLitri;
  final double hvoLitri;
  final double adBlueLitri;
  final Color benzinaColor;
  final Color gasolioColor;
  final Color hvoColor;
  final Color adBlueColor;

  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');

  @override
  Widget build(BuildContext context) {
    final categories = <_CategoriaLitri>[
      _CategoriaLitri('Benzina', benzinaLitri, benzinaColor),
      _CategoriaLitri('Gasolio', gasolioLitri, gasolioColor),
      _CategoriaLitri('HVO', hvoLitri, hvoColor),
      _CategoriaLitri('AdBlue', adBlueLitri, adBlueColor),
    ];
    final maxLitri = categories
        .map((c) => c.litri)
        .fold<double>(0, (a, b) => math.max(a, b));
    final hasData = categories.any((c) => c.litri > 0);

    if (!hasData) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            'Nessun dato da visualizzare.',
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _categoriaBar(
                context: context,
                categoria: categories[i],
                maxLitri: maxLitri,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoriaBar({
    required BuildContext context,
    required _CategoriaLitri categoria,
    required double maxLitri,
  }) {
    final progress = GestoproCountUpScope.progressOf(context);
    final animatedLitri = categoria.litri * progress;
    final ratio =
        maxLitri <= 0 ? 0.0 : (animatedLitri / maxLitri).clamp(0.0, 1.0);
    final height = 140.0 * ratio + (animatedLitri > 0 ? 8.0 : 0.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: double.infinity,
          child: GestoproCountUpText(
            target: categoria.litri,
            format: (v) => '${_numFmt.format(v)} L',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTiny,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                categoria.color,
                categoria.color.withValues(alpha: 0.72),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: categoria.color.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          categoria.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: GestoproDataPalette.fsLabel,
            fontWeight: FontWeight.w600,
            color: categoria.color,
          ),
        ),
      ],
    );
  }
}

class _CategoriaLitri {
  const _CategoriaLitri(this.label, this.litri, this.color);

  final String label;
  final double litri;
  final Color color;
}

class _RccMdoDonutChart extends StatelessWidget {
  const _RccMdoDonutChart({
    required this.palette,
    required this.gestopro,
    required this.rccLitri,
    required this.mdoLitri,
  });

  final GestoproDataPalette palette;
  final bool gestopro;
  final double rccLitri;
  final double mdoLitri;

  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = GestoproCountUpScope.progressOf(context);
    final total = rccLitri + mdoLitri;
    final animatedTotal = total * progress;
    final animatedRcc = rccLitri * progress;
    final animatedMdo = mdoLitri * progress;
    final rccColor = gestopro
        ? CronosFuturisticTheme.electricBright
        : theme.colorScheme.primary;
    final mdoColor = gestopro
        ? CronosFuturisticTheme.neonPurple
        : theme.colorScheme.tertiary;

    final paintSlices = <_DonutSlice>[
      if (rccLitri > 0)
        _DonutSlice(label: 'RCC Stradali', value: animatedRcc, color: rccColor),
      if (mdoLitri > 0)
        _DonutSlice(label: 'MDO', value: animatedMdo, color: mdoColor),
    ];
    final legendItems = <({String label, double value, Color color})>[
      if (rccLitri > 0) (label: 'RCC Stradali', value: rccLitri, color: rccColor),
      if (mdoLitri > 0) (label: 'MDO', value: mdoLitri, color: mdoColor),
    ];

    if (total <= 0) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            'Nessun litro da ripartire.',
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: CustomPaint(
              painter: _DonutPainter(
                slices: paintSlices.where((s) => s.value > 0).toList(),
                total: animatedTotal <= 0 ? total : animatedTotal,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestoproCountUpText(
                      target: total,
                      format: (v) => _numFmt.format(v),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      'Litri',
                      style: TextStyle(
                        fontSize: GestoproDataPalette.fsTiny,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in legendItems) ...[
                  _legendRow(
                    context,
                    label: item.label,
                    value: item.value,
                    total: total,
                    color: item.color,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(
    BuildContext context, {
    required String label,
    required double value,
    required double total,
    required Color color,
  }) {
    final pct = total > 0 ? (value / total * 100) : 0.0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsLabel,
              color: palette.textPrimary,
            ),
          ),
        ),
        GestoproCountUpText(
          target: value,
          format: (v) => '${_numFmt.format(v)} L',
          style: TextStyle(
            fontSize: GestoproDataPalette.fsTiny,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(width: 6),
        GestoproCountUpText(
          target: pct,
          format: (v) => '${_numFmt.format(v)}%',
          style: TextStyle(
            fontSize: GestoproDataPalette.fsTiny,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _DonutSlice {
  const _DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});

  final List<_DonutSlice> slices;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const stroke = 22.0;
    var start = -math.pi / 2;

    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.slices != slices;
}
