import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../pages/admin_dpi_hub_page.dart';
import '../pages/admin_estintori_page.dart';
import '../pages/admin_formazione_dlgs_81_08_page.dart';
import '../pages/admin_formazione_rfi_page.dart';
import '../pages/admin_formazione_rfi_strutture_page.dart';
import '../pages/admin_logistica_casette_ps_page.dart';
import '../pages/admin_uqsa_sedi_sicurezza_page.dart';
import '../pages/admin_pos_liste_hub_page.dart';
import '../pages/admin_tesserini_page.dart';
import '../pages/dipendente_tesserino_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

List<AdminHubNavItem> buildUqsaHubNavItems({
  int? adminUserId,
  bool showIlMioTesserino = false,
  bool showTesserini = false,
  String? role,
}) {
  const home = AppUiLayoutService.layoutUqsaHub;

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: AppUiLayoutService.layoutListePosHub,
      defaultLayoutKey: home,
      icon: Icons.list_alt_outlined,
      label: 'POS',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminPosListeHubMobilePage(
              userId: adminUserId,
              role: role,
            )
          : AdminPosListeHubPage(
              userId: adminUserId,
              role: role,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'estintori',
      defaultLayoutKey: home,
      icon: Icons.fire_extinguisher_outlined,
      label: 'Estintori',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminEstintoriMobilePage()
          : const AdminEstintoriPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'casette_ps',
      defaultLayoutKey: home,
      icon: Icons.medical_services_outlined,
      label: 'Cassette P.S.',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaCasettePsMobilePage()
          : const AdminLogisticaCasettePsPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'uqsa_sedi_sicurezza',
      defaultLayoutKey: home,
      icon: Icons.warehouse_outlined,
      label: 'Sedi sicurezza',
      subtitle: 'BOX, MDO, mezzi e altre sedi · estintori e cassette P.S.',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminUqsaSediSicurezzaMobilePage()
          : const AdminUqsaSediSicurezzaPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'formazione_dlgs',
      defaultLayoutKey: home,
      icon: Icons.school_outlined,
      label: 'Formazione D.Lgs. 81/08',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminFormazioneDlgsMobilePage(
              role: role,
              readOnly: role == null || !canManageFormazioneDlgs81Griglia(role),
            )
          : AdminFormazionePage(
              role: role,
              readOnly: role == null || !canManageFormazioneDlgs81Griglia(role),
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'formazione_rfi',
      defaultLayoutKey: home,
      icon: Icons.account_tree_outlined,
      label: 'Formazione RFI',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminFormazioneRfiMobilePage()
          : const AdminFormazioneRfiPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'strutture_rfi',
      defaultLayoutKey: home,
      icon: Icons.location_city_outlined,
      label: 'Strutture RFI (DOIT)',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminFormazioneRfiStruttureMobilePage()
          : const AdminFormazioneRfiStrutturePage(),
    ),
    if (canAccessDpiVestiarioModule(role ?? ''))
      AdminHubNavItem(
        layoutKey: 'dpi_hub',
        defaultLayoutKey: home,
        icon: Icons.inventory_2_outlined,
        label: 'DPI e Vestiario',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminDpiHubMobilePage(userId: adminUserId, role: role)
            : AdminDpiHubPage(userId: adminUserId, role: role),
      ),
    if (showIlMioTesserino && adminUserId != null)
      AdminHubNavItem(
        layoutKey: 'il_mio_tesserino',
        defaultLayoutKey: home,
        icon: Icons.badge_outlined,
        label: 'Il mio tesserino',
        onTap: (ctx) => useMobileUi(ctx)
            ? DipendenteTesserinoMobilePage(userId: adminUserId)
            : DipendenteTesserinoPage(userId: adminUserId),
      ),
    if (showTesserini)
      AdminHubNavItem(
        layoutKey: 'tesserini',
        defaultLayoutKey: home,
        icon: Icons.groups_outlined,
        label: 'Tesserini',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminTesseriniMobilePage()
            : const AdminTesseriniPage(),
      ),
  ];
}
