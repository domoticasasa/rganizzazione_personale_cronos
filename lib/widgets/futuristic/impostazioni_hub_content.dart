import 'package:flutter/material.dart';

import '../../hub/admin_hub_nav_item.dart';
import '../../hub/hub_tile_grid.dart';
import '../../hub/impostazioni_hub_nav_items.dart';
import '../../pages/admin_reorderable_hub_page.dart';
import '../../services/app_ui_layout_service.dart';
import '../../utils/futuristic_navigation.dart';

/// Contenuto hub Impostazioni (GESTOPRO e dialog classico).
class ImpostazioniHubContent extends StatelessWidget {
  const ImpostazioniHubContent({
    super.key,
    required this.adminId,
    required this.role,
    this.onPuliziaDati,
    required this.onCloseDialog,
    this.baseMaxCellWidth = 102,
    this.desktopAspectRatio = HubTileGridConfig.cellAspectRatio,
    this.mobileAspectRatio = 1.45,
  });

  final int adminId;
  final String? role;
  final ImpostazioniPuliziaCallback? onPuliziaDati;
  final VoidCallback onCloseDialog;
  final double baseMaxCellWidth;
  final double desktopAspectRatio;
  final double mobileAspectRatio;

  @override
  Widget build(BuildContext context) {
    final items = buildImpostazioniHubNavItems(
      adminId: adminId,
      onPuliziaDati: onPuliziaDati,
    );
    final tapOverrides = <String, void Function(BuildContext)>{
      for (final item in items)
        item.layoutKey: (tileContext) {
          final dest = item.onTap(tileContext);
          if (dest is AdminHubActionOnly) return;
          onCloseDialog();
          FuturisticNavigation.pushPage(
            tileContext,
            page: dest,
            title: item.label,
            activeSubKey: item.layoutKey,
          );
        },
    };

    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutImpostazioniHub,
      title: 'Impostazioni App',
      userId: adminId,
      role: role,
      onPuliziaDati: onPuliziaDati,
      maxCellWidth: baseMaxCellWidth,
      desktopAspectRatio: desktopAspectRatio,
      mobileAspectRatio: mobileAspectRatio,
      embedded: true,
      tapOverrides: tapOverrides,
      showCreatePageButton: false,
      savedSnackMessage: 'Ordine Impostazioni salvato per tutti gli utenti.',
    );
  }
}
