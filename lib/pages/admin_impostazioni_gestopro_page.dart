import 'package:flutter/material.dart';

import '../hub/admin_hub_nav_item.dart';
import '../hub/impostazioni_hub_nav_items.dart';
import '../utils/futuristic_admin_nav.dart';
import '../utils/futuristic_navigation.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_nav_section.dart';
import '../widgets/futuristic/futuristic_nav_shell.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';
import '../widgets/futuristic/impostazioni_hub_content.dart';

/// Hub Impostazioni a pagina intera in GESTOPRO (sotto-nav in sidebar).
class AdminImpostazioniGestoproPage extends StatelessWidget {
  const AdminImpostazioniGestoproPage({
    super.key,
    required this.adminId,
    required this.userId,
    required this.role,
    this.username,
    this.fullName,
    this.customAllowedPages,
    this.onPuliziaDati,
  });

  final int adminId;
  final int userId;
  final String? role;
  final String? username;
  final String? fullName;
  final Set<String>? customAllowedPages;
  final ImpostazioniPuliziaCallback? onPuliziaDati;

  List<FuturisticNavSubItem> _subItems(BuildContext context) {
    final items = buildImpostazioniHubNavItems(
      adminId: adminId,
      onPuliziaDati: onPuliziaDati,
    );
    return items.map((item) {
      return FuturisticNavSubItem(
        key: item.layoutKey,
        icon: item.icon,
        label: item.label,
        onTap: () {
          final dest = item.onTap(context);
          if (dest is AdminHubActionOnly) return;
          FuturisticNavigation.pushPage(
            context,
            page: dest,
            title: item.label,
          );
        },
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = role ?? '';
    final userLabel = username ?? '';
    final nameLabel = fullName ?? '';

    return GestoproSessionScope(
      adminId: adminId,
      userId: userId,
      username: userLabel,
      fullName: nameLabel,
      role: roleLabel,
      customAllowedPages: customAllowedPages,
      activeSection: FuturisticNavSection.impostazioni,
      subItems: _subItems(context),
      child: FuturisticNavShell(
      activeSection: FuturisticNavSection.impostazioni,
      subItems: _subItems(context),
      onHome: () => FuturisticAdminNav.openHome(
        context,
        userId: userId,
        username: userLabel,
        fullName: nameLabel,
        role: roleLabel,
        customAllowedPages: customAllowedPages,
      ),
      onDashboard: () => FuturisticAdminNav.openDashboard(
        context,
        adminId: adminId,
        role: role,
        username: username,
        fullName: fullName,
        customAllowedPages: customAllowedPages,
      ),
      onNotifiche: () => FuturisticAdminNav.openNotifiche(
        context,
        userId: userId,
        adminId: adminId,
        role: role,
        username: username,
        fullName: fullName,
        customAllowedPages: customAllowedPages,
      ),
      onAlert: () => FuturisticAdminNav.openAlert(
        context,
        userId: userId,
        adminId: adminId,
        role: role,
        username: username,
        fullName: fullName,
        customAllowedPages: customAllowedPages,
      ),
      onImpostazioni: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FuturisticInlineToolbar(title: 'Impostazioni App'),
          Expanded(
            child: ImpostazioniHubContent(
              adminId: adminId,
              role: role,
              onPuliziaDati: onPuliziaDati,
              onCloseDialog: () {},
              baseMaxCellWidth: 118,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
