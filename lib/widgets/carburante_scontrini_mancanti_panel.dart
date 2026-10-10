import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/qt_carburante_dipendente_mancanti_service.dart';

/// Riepilogo date scontrini QT da giustificare (vista dipendente).
class CarburanteScontriniMancantiPanel extends StatelessWidget {
  const CarburanteScontriniMancantiPanel({
    super.key,
    required this.loading,
    required this.anno,
    required this.mese,
    required this.giorni,
    this.monthLabel,
  });

  final bool loading;
  final int anno;
  final int mese;
  final List<QtScontrinoMancanteGiorno> giorni;
  final String? monthLabel;

  static final _df = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meseTxt = monthLabel ?? '$mese/$anno';

    if (loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Verifica scontrini da giustificare ($meseTxt)…',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (giorni.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nessuno scontrino mancante per $meseTxt '
                    '(o fattura QT non ancora importata dalla logistica).',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.receipt_long_outlined, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scontrini da giustificare — $meseTxt',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Date presenti in fattura QT sulla tua scheda ma senza '
                'giustificativo RCC. Inserisci il rifornimento per ciascuna data.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in giorni)
                    Chip(
                      avatar: Icon(
                        Icons.event,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      label: Text(
                        g.transazioni > 1
                            ? '${_df.format(g.data)} (${g.transazioni})'
                            : _df.format(g.data),
                      ),
                      backgroundColor: scheme.errorContainer.withValues(alpha: 0.55),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
