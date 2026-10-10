import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_pos_dipendenti_page.dart';
import '../pages/admin_pos_mdo_ferroviari_page.dart';
import '../pages/admin_pos_mezzi_stradali_page.dart';
import '../pages/admin_pos_mdo_proprieta_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

List<AdminHubNavItem> buildPosListeHubNavItems({
  int? adminUserId,
  String? role,
  bool compactLabels = false,
}) {
  const home = AppUiLayoutService.layoutListePosHub;
  final posReadOnly =
      role != null && !canManagePosDipendentiLista(role);
  final mdoFerroviariReadOnly =
      role != null && !canManagePosMdoFerroviariLista(role);
  final mezziReadOnly =
      role != null && !canManagePosMezziStradaliLista(role);
  final mdoProprietaReadOnly =
      role != null && !canManagePosMdoProprietaLista(role);

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'pos_dipendenti_lista',
      defaultLayoutKey: home,
      icon: Icons.engineering_outlined,
      label: compactLabels ? 'Lista POS' : 'Lista dipendenti POS',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminPosDipendentiMobilePage(
              userId: adminUserId,
              role: role,
              readOnly: posReadOnly,
            )
          : AdminPosDipendentiPage(
              userId: adminUserId,
              role: role,
              readOnly: posReadOnly,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'pos_mdo_ferroviari_lista',
      defaultLayoutKey: home,
      icon: Icons.train_outlined,
      label: compactLabels ? 'MdO POS' : 'Elenco MdO Ferroviari',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminPosMdoFerroviariMobilePage(
              userId: adminUserId,
              role: role,
              readOnly: mdoFerroviariReadOnly,
            )
          : AdminPosMdoFerroviariPage(
              userId: adminUserId,
              role: role,
              readOnly: mdoFerroviariReadOnly,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'pos_mdo_proprieta_lista',
      defaultLayoutKey: home,
      icon: Icons.construction_outlined,
      label: compactLabels ? 'MdO POS' : 'Elenco MdO',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminPosMdoProprietaMobilePage(
              userId: adminUserId,
              role: role,
              readOnly: mdoProprietaReadOnly,
            )
          : AdminPosMdoProprietaPage(
              userId: adminUserId,
              role: role,
              readOnly: mdoProprietaReadOnly,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'pos_mezzi_stradali_lista',
      defaultLayoutKey: home,
      icon: Icons.local_shipping_outlined,
      label: compactLabels ? 'Mezzi POS' : 'Elenco Mezzi Stradali',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminPosMezziStradaliMobilePage(
              userId: adminUserId,
              role: role,
              readOnly: mezziReadOnly,
            )
          : AdminPosMezziStradaliPage(
              userId: adminUserId,
              role: role,
              readOnly: mezziReadOnly,
            ),
    ),
  ];
}
