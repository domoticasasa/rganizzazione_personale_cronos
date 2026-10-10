import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/logistica_attrezzature_chooser.dart';
import '../utils/logistica_mdo_ferroviari_chooser.dart';
import '../utils/logistica_mezzi_stradali_chooser.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';
import '../pages/admin_logistica_box_page.dart';
import '../pages/admin_logistica_mdo_proprieta_page.dart';
import '../pages/admin_logistica_noleggio_page.dart';
import '../pages/admin_logistica_sim_page.dart';

List<AdminHubNavItem> buildLogisticaHubNavItems({String? role}) {
  const home = AppUiLayoutService.layoutLogisticaHub;
  final r = normalizeRole(role ?? '');
  // DT e assistente DT: sola lettura sulle attrezzature.
  final attrezzatureReadOnly = r == 'dt' || r == 'assistente_dt';
  // Trasferimenti MDO: solo admin (non vista) e logistica modificano.
  final mdoPerCommessaReadOnly =
      r == 'dt' || r == 'assistente_dt' || isAdminVistaRole(role ?? '');
  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'mezzi_stradali',
      defaultLayoutKey: home,
      icon: Icons.local_shipping_outlined,
      label: 'Mezzi Stradali',
      subtitle: 'Assegnazioni, Multicard MDO PDF, Telepass, viaggi…',
      onTap: (ctx) {
        showLogisticaMezziStradaliChooser(ctx);
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'attrezzature',
      defaultLayoutKey: home,
      icon: Icons.handyman_outlined,
      label: 'Attrezzature',
      subtitle: 'Lista e PDF assegnazione',
      onTap: (ctx) {
        showLogisticaAttrezzatureChooser(
          ctx,
          attrezzatureReadOnly: attrezzatureReadOnly,
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'box',
      defaultLayoutKey: home,
      icon: Icons.inventory_2_outlined,
      label: 'BOX',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaBoxMobilePage()
          : const AdminLogisticaBoxPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'mdo_ferroviari',
      defaultLayoutKey: home,
      icon: Icons.train_outlined,
      label: 'MDO Ferroviari',
      subtitle: 'Lista, documenti, per commessa e check',
      onTap: (ctx) {
        showLogisticaMdoFerroviariChooser(
          ctx,
          mdoPerCommessaReadOnly: mdoPerCommessaReadOnly,
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'mdo_proprieta',
      defaultLayoutKey: home,
      icon: Icons.construction_outlined,
      label: 'MDO Proprietà',
      subtitle: 'Mezzi e accessori di proprietà',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaMdoProprietaMobilePage()
          : const AdminLogisticaMdoProprietaPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'noleggio',
      defaultLayoutKey: home,
      icon: Icons.car_rental_outlined,
      label: 'Noleggio',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaNoleggioMobilePage()
          : const AdminLogisticaNoleggioPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'sim_telefoni',
      defaultLayoutKey: home,
      icon: Icons.sim_card_outlined,
      label: 'SIM',
      subtitle: 'Linee telefoniche e assegnazioni PDF',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaSimMobilePage()
          : const AdminLogisticaSimPage(),
    ),
  ];
}
