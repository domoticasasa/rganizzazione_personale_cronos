import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import 'admin_hub_nav_item.dart';
import 'app_ui_hub_registry.dart';
import 'dashboard_hub_nav_items.dart';
import 'impostazioni_hub_nav_items.dart';
import 'logistica_hub_nav_items.dart';
import 'dpi_hub_nav_items.dart';
import 'custom_hub_nav_items.dart';
import 'carburante_hub_nav_items.dart';
import 'home_dipendente_nav_items.dart';
import 'app_ui_custom_hub.dart';
import 'uqsa_hub_nav_items.dart';
import 'pos_liste_hub_nav_items.dart';

typedef ImpostazioniPuliziaCallback = void Function(BuildContext context);

/// Catalogo unificato di tutti i pulsanti spostabili tra hub.
class AdminHubCatalog {
  AdminHubCatalog({
    required this.itemsByKey,
    required this.defaultKeysByLayout,
  });

  final Map<String, AdminHubNavItem> itemsByKey;
  final Map<String, List<String>> defaultKeysByLayout;

  static AdminHubCatalog build(
    BuildContext context, {
    required int adminId,
    String? role,
    Set<String>? customAllowedPages,
    bool showUqsaTesserino = false,
    bool showUqsaTesserini = false,
    ImpostazioniPuliziaCallback? onPuliziaDati,
    HomeDipendenteNavParams? homeDipendente,
    List<AppUiCustomHub> customHubs = const <AppUiCustomHub>[],
  }) {
    final merged = <AdminHubNavItem>[
      ...buildDashboardHubNavItems(
        context,
        adminId: adminId,
        role: role,
        customAllowedPages: customAllowedPages,
      ),
      ...buildCustomHubNavItems(
        customHubs: customHubs,
        userId: adminId,
        role: role,
        homeDipendente: homeDipendente,
      ),
      ...buildCustomHubSlotNavItems(customHubs: customHubs),
      ...buildLogisticaHubNavItems(role: role),
      ...buildCarburanteHubNavItems(role: role),
      ...buildUqsaHubNavItems(
        adminUserId: adminId,
        showIlMioTesserino: showUqsaTesserino,
        showTesserini: showUqsaTesserini,
        role: role,
      ),
      ...buildPosListeHubNavItems(
        adminUserId: adminId,
        role: role,
      ),
      ...buildDpiHubNavItems(),
      ...buildImpostazioniHubNavItems(
        adminId: adminId,
        onPuliziaDati: onPuliziaDati,
      ),
      if (homeDipendente != null)
        ...buildHomeDipendenteNavItems(homeDipendente),
    ];

    final itemsByKey = <String, AdminHubNavItem>{};
    for (final item in merged) {
      itemsByKey.putIfAbsent(item.layoutKey, () => item);
    }

    final defaultKeysByLayout = <String, List<String>>{};
    for (final hub in AppUiHubRegistry.all) {
      defaultKeysByLayout[hub.layoutKey] = merged
          .where((i) => i.defaultLayoutKey == hub.layoutKey)
          .map((i) => i.layoutKey)
          .toList(growable: false);
    }
    final dashClassic = defaultKeysByLayout[AppUiLayoutService.layoutDashboardAdmin];
    if (dashClassic != null && dashClassic.isNotEmpty) {
      defaultKeysByLayout[AppUiLayoutService.layoutDashboardAdminFuturistic] =
          List<String>.from(dashClassic);
    }

    return AdminHubCatalog(
      itemsByKey: itemsByKey,
      defaultKeysByLayout: defaultKeysByLayout,
    );
  }
}
