import 'package:flutter/material.dart';

/// Conferma admin: il precedente assegnatario è stato avvisato dei giustificativi.
Future<bool> confirmPreviousAssigneeGiustificativi({
  required BuildContext context,
  required String previousAssigneeName,
  required String assetLabel,
}) async {
  final prev = previousAssigneeName.trim();
  if (prev.isEmpty) return true;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Cambio assegnatario'),
      content: Text(
        'Stai modificando l\'assegnatario di $assetLabel.\n\n'
        'Hai chiesto a $prev di inserire i giustificativi carburante '
        'ancora pendenti sulla scheda/mezzo?\n\n'
        'Conferma solo se il dipendente uscente ha già inserito o '
        'è stato avvisato.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sì, salva'),
        ),
      ],
    ),
  );
  return result == true;
}
