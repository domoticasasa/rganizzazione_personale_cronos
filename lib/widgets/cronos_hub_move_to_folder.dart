import 'package:flutter/material.dart';

import '../hub/app_ui_custom_hub.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/gestopro_page_chrome.dart';
import 'premium_glass_hub.dart';

/// Sceglie una cartella (hub custom) in cui spostare un pulsante.
Future<String?> pickHubFolderTarget({
  required BuildContext context,
  required List<AppUiCustomHub> folders,
  required String currentLayoutKey,
  String? movingItemKey,
}) async {
  final targets = folders.where((h) {
    if (h.layoutKey == currentLayoutKey) return false;
    if (movingItemKey != null && movingItemKey == h.launcherKey) {
      return false;
    }
    return h.label.trim().isNotEmpty;
  }).toList(growable: false);

  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Crea prima una cartella, poi sposta i pulsanti dentro.',
        ),
      ),
    );
    return null;
  }

  if (isGestoproFuturisticUi(context)) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Sposta in cartella',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              for (final folder in targets)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.label),
                  onTap: () => Navigator.pop(ctx, folder.layoutKey),
                ),
            ],
          ),
        );
      },
    );
  }

  return showPremiumGlassBottomSheet<String>(
    context: context,
    title: 'Sposta in cartella',
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final folder in targets)
          PremiumGlassHubTile(
            layoutKey: folder.launcherKey,
            title: folder.label,
            subtitle: 'Apri e sposta qui',
            icon: Icons.folder_outlined,
            onTap: () => Navigator.pop(context, folder.layoutKey),
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          ),
      ],
    ),
  );
}

/// Pulsante compatto: sposta il tile in una sotto-cartella.
class CronosHubMoveToFolderButton extends StatelessWidget {
  const CronosHubMoveToFolderButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final gestopro = isGestoproFuturisticUi(context);
    return Material(
      color: gestopro
          ? CronosFuturisticTheme.panelBg.withValues(alpha: 0.92)
          : Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Sposta in cartella',
        icon: Icon(
          Icons.drive_file_move_outline,
          size: 18,
          color: gestopro ? CronosFuturisticTheme.neonCyan : null,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
