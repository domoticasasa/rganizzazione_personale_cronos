import 'package:flutter/material.dart';

import '../services/data_cleanup_service.dart';
import 'admin_vista_guard.dart';

/// Dialog condiviso per la pulizia dati storici (Impostazioni / dashboard).
void showPuliziaDatiDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Pulizia Dati'),
        content: const Text(
          'Seleziona il tipo di pulizia.\n'
          '• Pernottamenti: prenotazioni con data di uscita più vecchia di 10 giorni.\n'
          '• Treni / Aereo: viaggi con data (o ritorno) più vecchia di 10 giorni.\n'
          '• Notifiche: elimina quelle oltre 10 giorni (created_at, fuso Italia).',
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.bed_outlined),
            label: const Text('Pernottamenti'),
            onPressed: () => _runDataCleanup(
              context: context,
              dialogContext: ctx,
              rpcName: 'cleanup_pernottamenti',
              label: 'pernottamenti',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.flight_outlined),
            label: const Text('Aereo'),
            onPressed: () => _runDataCleanup(
              context: context,
              dialogContext: ctx,
              rpcName: 'cleanup_aereo',
              label: 'aerei',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.train_outlined),
            label: const Text('Treni'),
            onPressed: () => _runDataCleanup(
              context: context,
              dialogContext: ctx,
              rpcName: 'cleanup_treni',
              label: 'treni',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Notifiche'),
            onPressed: () => _runDataCleanup(
              context: context,
              dialogContext: ctx,
              rpcName: 'cleanup_notifications',
              label: 'notifiche',
            ),
          ),
        ],
      );
    },
  );
}

Future<void> _runDataCleanup({
  required BuildContext context,
  required BuildContext dialogContext,
  required String rpcName,
  required String label,
}) async {
  if (!await ensureCanPersist(context)) return;
  if (!dialogContext.mounted) return;
  showDialog<void>(
    context: dialogContext,
    barrierDismissible: false,
    builder: (waitCtx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Eliminazione su Supabase…')),
        ],
      ),
    ),
  );
  try {
    final deleted = await DataCleanupService.runRpc(rpcName);
    var snackText = deleted > 0
        ? 'Pulizia $label: elaborate $deleted righe su Supabase.'
        : 'Pulizia $label: nessuna riga da elaborare (soglia 10 giorni).';
    if (rpcName == 'cleanup_notifications') {
      final remaining = await DataCleanupService.countNotifications();
      snackText = deleted > 0
          ? 'Notifiche: eliminate $deleted righe (>10 gg). Ne restano $remaining.'
          : 'Notifiche: 0 da eliminare. Su Supabase ce ne sono $remaining '
              '(ultimi ${DataCleanupService.notificationRetentionDays} giorni).';
    }
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext); // progress
      Navigator.pop(dialogContext); // pulizia dialog
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        duration: Duration(seconds: rpcName == 'cleanup_notifications' ? 6 : 4),
      ),
    );
  } catch (e) {
    if (e is AdminVistaReadOnlyException) {
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext); // progress
      }
      return;
    }
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext); // progress
      Navigator.pop(dialogContext); // pulizia dialog
    }
    if (!context.mounted) return;
    final msg = e.toString();
    final hint = msg.contains('cleanup_') || msg.contains('PGRST202')
        ? '\nApplica le migration Supabase (cleanup_notifications).'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Errore pulizia $label: $e$hint'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
