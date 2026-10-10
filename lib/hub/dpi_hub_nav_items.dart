import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_dpi_categories_page.dart';
import '../pages/admin_dpi_report_page.dart';
import '../pages/admin_dpi_terza_categoria_page.dart';
import '../pages/admin_vestiario_categorie_page.dart';
import '../pages/admin_vestiario_fabbisogno_taglie_page.dart';
import '../pages/admin_vestiario_inventario_page.dart';
import '../pages/admin_vestiario_page.dart';
import '../pages/admin_vestiario_report_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import 'admin_hub_nav_item.dart';

/// Pulsanti hub DPI / vestiario (riordinabili e spostabili tra le pagine).
List<AdminHubNavItem> buildDpiHubNavItems() {
  const home = AppUiLayoutService.layoutDpiHub;

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'dpi_report',
      defaultLayoutKey: home,
      icon: Icons.inventory_2_outlined,
      label: 'Report DPI Dipendenti',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminDpiReportMobilePage()
          : const AdminDpiReportPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'dpi_categorie',
      defaultLayoutKey: home,
      icon: Icons.category_outlined,
      label: 'Categorie DPI',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminDpiCategoriesMobilePage()
          : const AdminDpiCategoriesPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'dpi_terza_categoria',
      defaultLayoutKey: home,
      icon: Icons.description_outlined,
      label: 'Assegnazione DPI III Categoria',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminDpiTerzaCategoriaMobilePage()
          : const AdminDpiTerzaCategoriaPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'vestiario_categorie',
      defaultLayoutKey: home,
      icon: Icons.category_outlined,
      label: 'Categorie Vestiario',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVestiarioCategorieMobilePage()
          : const AdminVestiarioCategoriePage(),
    ),
    AdminHubNavItem(
      layoutKey: 'vestiario_assegnazione',
      defaultLayoutKey: home,
      icon: Icons.checkroom_outlined,
      label: 'Assegnazione Vestiario',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVestiarioMobilePage()
          : const AdminVestiarioPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'vestiario_riepilogo',
      defaultLayoutKey: home,
      icon: Icons.summarize_outlined,
      label: 'Riepilogo Vestiario',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVestiarioReportMobilePage()
          : const AdminVestiarioReportPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'vestiario_fabbisogno',
      defaultLayoutKey: home,
      icon: Icons.straighten_outlined,
      label: 'Fabbisogno taglie',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVestiarioFabbisognoMobilePage()
          : const AdminVestiarioFabbisognoTagliePage(),
    ),
    AdminHubNavItem(
      layoutKey: 'vestiario_inventario',
      defaultLayoutKey: home,
      icon: Icons.warehouse_outlined,
      label: 'Inventario Vestiario',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVestiarioInventarioMobilePage()
          : const AdminVestiarioInventarioPage(),
    ),
  ];
}

/// Sostituisce il vecchio tile unico [dpi_uqsa] con le voci separate.
const List<String> kLegacyDpiUqsaExpansion = <String>[
  'dpi_report',
  'dpi_categorie',
  'dpi_terza_categoria',
  'vestiario_categorie',
  'vestiario_assegnazione',
  'vestiario_riepilogo',
  'vestiario_fabbisogno',
  'vestiario_inventario',
];

void expandLegacyDpiUqsaKey(Map<String, List<String>> keysByLayout) {
  const legacy = 'dpi_uqsa';
  for (final layoutKey in keysByLayout.keys.toList()) {
    final keys = keysByLayout[layoutKey]!;
    final idx = keys.indexOf(legacy);
    if (idx < 0) continue;
    keys.removeAt(idx);
    keys.insertAll(idx, kLegacyDpiUqsaExpansion);
    keysByLayout[layoutKey] = keys;
  }
}

/// Inserisce «Categorie Vestiario» negli hub DPI salvati prima dell'introduzione della voce.
void ensureVestiarioCategorieInDpiHub(Map<String, List<String>> keysByLayout) {
  const key = 'vestiario_categorie';
  const layout = AppUiLayoutService.layoutDpiHub;
  final keys = keysByLayout[layout];
  if (keys == null || keys.contains(key)) return;

  final vestiarioIdx = keys.indexWhere((k) => k.startsWith('vestiario_'));
  if (vestiarioIdx >= 0) {
    keys.insert(vestiarioIdx, key);
  } else {
    final afterDpi = keys.indexOf('dpi_terza_categoria');
    if (afterDpi >= 0) {
      keys.insert(afterDpi + 1, key);
    } else {
      keys.add(key);
    }
  }
  keysByLayout[layout] = keys;
}
