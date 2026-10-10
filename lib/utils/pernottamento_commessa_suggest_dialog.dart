import 'package:flutter/material.dart';

/// Chiede se usare la commessa del pernottamento per la data indicata.
/// `true` = sì, `false` = no, `null` = chiusura dialog senza scelta.
Future<bool?> showPernottamentoCommessaSuggestDialog({
  required BuildContext context,
  required String dateLabel,
  required String commessaLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Prenotazione pernottamento'),
      content: Text(
        'Per il giorno $dateLabel hai una prenotazione pernottamento '
        'sulla commessa «$commessaLabel».\n\n'
        'Vuoi inserire automaticamente questa commessa?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No, inserisco io'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sì, inserisci'),
        ),
      ],
    ),
  );
}
