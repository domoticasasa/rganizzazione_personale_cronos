import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'responsive.dart';

/// Informativa privacy obbligatoria all’ingresso in Rubrica.
/// I dati (telefono, e-mail, nascita) si vedono solo dopo «OK».
abstract final class RubricaPrivacyNotice {
  RubricaPrivacyNotice._();

  static const String title = 'Riservatezza dei dati';

  static const String body =
      'La Rubrica contiene dati personali dei lavoratori: nominativi, '
      'numeri di telefono, indirizzi e-mail e date di nascita.\n\n'
      'Questi dati possono essere usati solo per finalità aziendali e '
      'organizzative (contatto di servizio, coordinamento, emergenze e '
      'adempimenti legati al rapporto di lavoro).\n\n'
      'Non è consentito copiarli, inoltrarli o salvarli su dispositivi '
      'personali, né usarli per scopi privati o comunicarli a chi non è '
      'autorizzato.\n\n'
      'L’accesso è riservato ad amministratori, Direttore Tecnico e '
      'Assistente DT, nel rispetto del Regolamento (UE) 2016/679 (GDPR) '
      'e delle policy aziendali sulla privacy.\n\n'
      'Premendo «OK» confermi di aver compreso e di utilizzare i dati '
      'solo per l’attività dell’azienda.';

  /// `true` se l’utente ha confermato; `false` se ha annullato.
  static Future<bool> confirm(BuildContext? context) async {
    final ctx = appNavigatorContext ?? context;
    if (ctx == null || !ctx.mounted) return false;

    final mobile = useMobileUi(ctx);
    final ok = await showDialog<bool>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        final scroll = SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 20 : 4,
            mobile ? 8 : 0,
            mobile ? 20 : 4,
            8,
          ),
          child: Text(
            body,
            style: TextStyle(
              height: 1.45,
              fontSize: mobile ? 15 : 14,
            ),
          ),
        );

        final actions = [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: Size(mobile ? 120 : 96, mobile ? 48 : 40),
              textStyle: TextStyle(
                fontSize: mobile ? 16 : 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('OK'),
          ),
        ];

        if (mobile) {
          return PopScope(
            canPop: false,
            child: Dialog.fullscreen(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.privacy_tip_outlined,
                            size: 26,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        'Leggi e conferma per visualizzare i contatti.',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const Divider(height: 20),
                    Expanded(child: scroll),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(child: actions[0]),
                          const SizedBox(width: 12),
                          Expanded(child: actions[1]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return PopScope(
          canPop: false,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 22,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text(title)),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: scroll,
            ),
            actionsAlignment: MainAxisAlignment.end,
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: actions,
          ),
        );
      },
    );
    return ok == true;
  }
}
