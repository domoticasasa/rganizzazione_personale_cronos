import 'package:flutter/material.dart';

/// Ambito della rimozione di un tile hub.
enum HubTileDeleteScope {
  /// Solo da questa pagina (copia presente altrove).
  currentPageOnly,
  /// Una copia duplicata sulla stessa pagina.
  oneDuplicateOnPage,
  /// Da tutte le pagine (unica copia nell'app).
  global,
  customPage,
  customSlot,
}

/// Conferma rimozione di un tile hub in modalità riordino.
Future<bool> confirmDeleteHubTile(
  BuildContext context, {
  required String label,
  required String itemKey,
  required HubTileDeleteScope scope,
}) {
  String title;
  String body;
  switch (scope) {
    case HubTileDeleteScope.currentPageOnly:
      title = 'Rimuovere da questa pagina';
      body =
          'Rimuovere «$label» solo da questa pagina?\n\n'
          'Il pulsante resterà visibile sulle altre pagine dove è presente.';
    case HubTileDeleteScope.oneDuplicateOnPage:
      title = 'Rimuovere copia';
      body =
          'Rimuovere una copia del pulsante «$label» da questa pagina?\n\n'
          'Le altre copie restano invariate finché non premi «Salva per tutti».';
    case HubTileDeleteScope.customPage:
      title = 'Eliminare cartella';
      body =
          'Eliminare definitivamente la cartella «$label» e i suoi contenuti di layout?\n\n'
          'I pulsanti spostati dentro restano nel catalogo; potrai riassegnarli da Riordina.\n'
          'L\'operazione non si può annullare.';
    case HubTileDeleteScope.customSlot:
      title = 'Eliminare sezione';
      body =
          'Eliminare la sezione «$label» dalla pagina personalizzata?\n\n'
          'L\'operazione non si può annullare.';
    case HubTileDeleteScope.global:
      title = 'Rimuovere pulsante';
      body =
          'Rimuovere «$label» da tutte le pagine dell\'app?\n\n'
          'Il pulsante non verrà più mostrato finché non lo aggiungi di nuovo.';
  }

  return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elimina'),
            ),
          ],
        ),
      ).then((v) => v ?? false);
}

/// Icona elimina su tile in modalità riordino.
class CronosHubDeleteTileButton extends StatelessWidget {
  const CronosHubDeleteTileButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Elimina pulsante',
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(Icons.close, size: 18, color: theme.colorScheme.error),
        onPressed: onPressed,
      ),
    );
  }
}
