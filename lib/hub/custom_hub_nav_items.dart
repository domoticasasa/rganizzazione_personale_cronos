import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_carburante_hub_page.dart';
import '../pages/admin_custom_hub_page.dart';
import '../pages/admin_custom_hub_slot_page.dart';
import '../hub/custom_hub_structure_type.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import 'admin_hub_nav_item.dart';
import 'app_ui_custom_hub.dart';
import 'custom_hub_structure_templates.dart';

List<AdminHubNavItem> buildCustomHubNavItems({
  required List<AppUiCustomHub> customHubs,
  int? userId,
  String? role,
  HomeDipendenteNavParams? homeDipendente,
}) {
  const dash = AppUiLayoutService.layoutDashboardAdmin;

  return customHubs
      .map(
        (h) {
          final isCarburantePage =
              h.label.trim().toLowerCase() == 'carburante';
          return AdminHubNavItem(
            layoutKey: h.launcherKey,
            defaultLayoutKey: dash,
            icon: isCarburantePage
                ? Icons.oil_barrel_outlined
                : Icons.folder_outlined,
            label: h.label,
            onTap: (ctx) {
              if (isCarburantePage) {
                return useMobileUi(ctx)
                    ? AdminCarburanteHubMobilePage(
                        userId: userId,
                        role: role,
                      )
                    : AdminCarburanteHubPage(
                        userId: userId,
                        role: role,
                      );
              }
              return useMobileUi(ctx)
                  ? AdminCustomHubMobilePage(
                      layoutKey: h.layoutKey,
                      title: h.label,
                      userId: userId,
                      role: role,
                      homeDipendente: homeDipendente,
                    )
                  : AdminCustomHubPage(
                      layoutKey: h.layoutKey,
                      title: h.label,
                      userId: userId,
                      role: role,
                      homeDipendente: homeDipendente,
                    );
            },
          );
        },
      )
      .toList(growable: false);
}

/// Pulsanti/sezioni vuote all'interno di ogni pagina custom.
List<AdminHubNavItem> buildCustomHubSlotNavItems({
  required List<AppUiCustomHub> customHubs,
}) {
  final out = <AdminHubNavItem>[];
  for (final hub in customHubs) {
    if (hub.structureType == CustomHubStructureType.prenotazioni) continue;
    final accent = CustomHubStructureTemplates.usesAlertAccent(hub.structureType);
    for (final slot in hub.slots) {
      out.add(
        AdminHubNavItem(
          layoutKey: slot.key,
          defaultLayoutKey: hub.layoutKey,
          icon: hub.structureType.icon,
          label: slot.label,
          iconColor: accent ? Colors.red.shade700 : null,
          onTap: (ctx) => AdminCustomHubSlotPage(
            sectionLabel: slot.label,
            pageTitle: hub.label,
          ),
        ),
      );
    }
  }
  return out;
}
