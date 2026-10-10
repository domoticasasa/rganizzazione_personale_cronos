import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../pages/dipendente_rifornimenti_mancanti_page.dart';
import '../utils/roles.dart';
import 'qt_carburante_dipendente_mancanti_service.dart';
import '../utils/personale_profile_resolver.dart';

/// Popup giustificazioni carburante mancanti (mese precedente) all'apertura app.
abstract final class DipendenteQtMancantiPrompt {
  static bool _askedThisLaunch = false;

  static void resetSession() {
    _askedThisLaunch = false;
  }

  static Future<void> maybeAsk(BuildContext? context) async {
    if (context == null || !context.mounted) return;
    if (_askedThisLaunch) return;
    _askedThisLaunch = true;

    try {
      final bundle = await resolveMyProfileBundle(
        select: 'id, id_uuid, user_id, full_name',
      );
      if (!context.mounted) return;
      final role = normalizeRole((bundle.users?['role'] ?? '').toString());
      if (!const {'dipendente', 'dipendenti', 'user'}.contains(role)) return;

      final res =
          await QtCarburanteDipendenteMancantiService.loadMancantiMesePrecedente();
      if (!context.mounted) return;
      if (!res.hasImport || res.isEmpty) return;

      final action = await showDialog<_QtMancantiAction>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _DipendenteQtMancantiDialog(result: res),
      );
      if (!context.mounted) return;
      if (action != _QtMancantiAction.giustifica) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DipendenteRifornimentiMancantiPage(
            anno: res.anno,
            mese: res.mese,
          ),
        ),
      );
    } catch (_) {
      // Silenzioso: non bloccare l'home se la verifica fallisce.
    }
  }
}

enum _QtMancantiAction { posticipa, giustifica }

class _DipendenteQtMancantiDialog extends StatelessWidget {
  const _DipendenteQtMancantiDialog({required this.result});

  final QtMancantiMeseResult result;

  static final _df = DateFormat('dd/MM/yyyy');
  static final _euro = NumberFormat.currency(locale: 'it_IT', symbol: '€');

  @override
  Widget build(BuildContext context) {
    final meseTxt = QtCarburanteDipendenteMancantiService.monthLabelIt(
      result.mese,
      result.anno,
    );
    final preview = result.dettagli.take(8).toList(growable: false);
    final extra = result.totale - preview.length;

    return AlertDialog(
      title: const Text('Rifornimenti da giustificare'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hai ${result.totale} rifornimenti da giustificare '
                'per $meseTxt (fattura QT).\n'
                'Inserisci i giustificativi sul registro RCC.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final d in preview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_df.format(d.data)} · ${d.prodotto}\n'
                          'Carta ${d.numeroCarta} · '
                          '${d.volume.toStringAsFixed(1)} L · '
                          '${_euro.format(d.importo)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (extra > 0)
                Text(
                  '… e altre $extra',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _QtMancantiAction.posticipa),
          child: const Text('Posticipa'),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.pop(context, _QtMancantiAction.giustifica),
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Giustifica'),
        ),
      ],
    );
  }
}
