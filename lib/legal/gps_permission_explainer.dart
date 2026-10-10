import 'package:flutter/material.dart';

import 'legal_documents.dart';
import 'privacy_termini_page.dart';

/// Schermata informativa mostrata PRIMA della richiesta di sistema del
/// permesso di posizione (audit legale M1; testo dal documento 07).
enum GpsPurpose { buonoPasto, viaggioMezzo }

abstract final class GpsPermissionExplainer {
  /// true = l'utente ha premuto «Continua» (si può chiedere il permesso).
  static Future<bool> show(BuildContext context, GpsPurpose purpose) async {
    final settings = await LegalDocumentsService.loadSettings();
    if (!context.mounted) return false;
    final mesi = settings.gpsRetentionMonths;
    final conservazione = mesi == 1 ? '1 mese' : '$mesi mesi';

    final String title;
    final String text;
    switch (purpose) {
      case GpsPurpose.buonoPasto:
        // Testo 07 – "Versione GESTOPRO360 (buoni pasto)".
        title = 'Posizione per il buono pasto';
        text = "Quando registri un buono pasto, l'app salva la posizione del "
            'telefono solo in quel momento, per verificare che il pasto sia '
            'presso un ristorante convenzionato. Nessun tracciamento continuo '
            'e nessuna lettura in background. Conservazione: $conservazione. '
            'Puoi revocare il permesso dalle impostazioni del telefono.';
      case GpsPurpose.viaggioMezzo:
        // Adattamento del testo 07 per apertura/chiusura viaggio con mezzo.
        title = 'Posizione per il viaggio con il mezzo';
        text = "Quando apri o chiudi un viaggio con il mezzo aziendale, l'app "
            'salva la posizione del telefono solo in quel momento, per '
            'registrare il luogo di partenza e di arrivo. Nessun tracciamento '
            'continuo e nessuna lettura in background. Conservazione: '
            '$conservazione. Puoi revocare il permesso dalle impostazioni del '
            'telefono.';
    }

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined),
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => PrivacyTerminiPage.open(ctx),
            child: const Text('Informativa privacy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non ora'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    return res == true;
  }
}
