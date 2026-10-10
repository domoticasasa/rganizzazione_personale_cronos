import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/carburante_giustificativi_stats_service.dart';
import '../utils/gestopro_data_palette.dart';
import 'carburante_giustificativi_riepilogo_panel.dart';

/// Tabella consumo medio L/100km aggregato per modello mezzo (da km RCC).
class CarburanteConsumoModelloPanel extends StatelessWidget {
  const CarburanteConsumoModelloPanel({
    super.key,
    required this.loading,
    required this.rows,
    this.year,
    this.month,
  });

  final bool loading;
  final List<CarburanteConsumoModelloStats> rows;
  final int? year;
  final int? month;

  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');
  static final NumberFormat _l100Fmt = NumberFormat('#,##0.0', 'it_IT');
  static final NumberFormat _euroFmt = NumberFormat('#,##0.00', 'it_IT');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GestoproDataPalette.of(context);

    if (loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final monthLabel = (year != null &&
            month != null &&
            month! >= 1 &&
            month! <= 12)
        ? '${CarburanteGiustificativiRiepilogoPanel.monthNames[month! - 1]} $year'
        : 'periodo selezionato';

    return Container(
      padding: GestoproDataPalette.padCard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(palette.radius),
        color: palette.surface,
        border: Border.all(color: palette.border.withValues(alpha: 0.55)),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Consumo medio per modello',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'L/100 km RCC · litri sommati tra due letture km (anche senza km '
            'intermedi) · modelli unificati ignorando MAIUSCOLE/minuscole · '
            '$monthLabel',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTiny,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Nessun tratto valido nel mese. Servono almeno due letture km '
              'sullo stesso mezzo (delta 5–2500 km) e litri benzina/gasolio.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compactTable = constraints.maxWidth < 1180;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 64,
                    columns: compactTable
                        ? const [
                            DataColumn(label: Text('Modello')),
                            DataColumn(label: Text('Mezzi'), numeric: true),
                            DataColumn(label: Text('Km'), numeric: true),
                            DataColumn(label: Text('Litri'), numeric: true),
                            DataColumn(label: Text('L/100 km'), numeric: true),
                            DataColumn(label: Text('Min-Max'), numeric: true),
                          ]
                        : const [
                            DataColumn(label: Text('Modello')),
                            DataColumn(label: Text('Mezzi'), numeric: true),
                            DataColumn(label: Text('Tratti'), numeric: true),
                            DataColumn(label: Text('Rif.'), numeric: true),
                            DataColumn(label: Text('Km'), numeric: true),
                            DataColumn(label: Text('Litri'), numeric: true),
                            DataColumn(label: Text('Euro'), numeric: true),
                            DataColumn(label: Text('L/100 km'), numeric: true),
                            DataColumn(label: Text('€/100 km'), numeric: true),
                            DataColumn(label: Text('Min-Max'), numeric: true),
                          ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          cells: compactTable
                              ? [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 260),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.modello,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: palette.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Tratti ${r.segmenti} · Rif. ${r.rifornimenti}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: palette.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('${r.mezziCount}')),
                                  DataCell(Text(_numFmt.format(r.km))),
                                  DataCell(Text('${_numFmt.format(r.litri)} L')),
                                  DataCell(
                                    Text(
                                      _l100Fmt.format(r.litriPer100Km),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      (r.minLitriPer100Km != null &&
                                              r.maxLitriPer100Km != null)
                                          ? '${_l100Fmt.format(r.minLitriPer100Km!)}-${_l100Fmt.format(r.maxLitriPer100Km!)}'
                                          : '—',
                                    ),
                                  ),
                                ]
                              : [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 200),
                                      child: Text(
                                        r.modello,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('${r.mezziCount}')),
                                  DataCell(Text('${r.segmenti}')),
                                  DataCell(Text('${r.rifornimenti}')),
                                  DataCell(Text(_numFmt.format(r.km))),
                                  DataCell(
                                      Text('${_numFmt.format(r.litri)} L')),
                                  DataCell(Text('€ ${_euroFmt.format(r.euro)}')),
                                  DataCell(
                                    Text(
                                      _l100Fmt.format(r.litriPer100Km),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(_euroFmt.format(r.euroPer100Km))),
                                  DataCell(
                                    Text(
                                      (r.minLitriPer100Km != null &&
                                              r.maxLitriPer100Km != null)
                                          ? '${_l100Fmt.format(r.minLitriPer100Km!)}-${_l100Fmt.format(r.maxLitriPer100Km!)}'
                                          : '—',
                                    ),
                                  ),
                                ],
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
