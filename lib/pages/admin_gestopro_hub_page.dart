import 'package:flutter/material.dart';



import '../Mobile/aereo_mobile.dart';

import '../Mobile/prenotazione_pernottamenti_mobile.dart';

import '../Mobile/treno_mobile.dart';

import '../utils/dt_view_navigation.dart';
import '../utils/futuristic_admin_nav.dart';

import '../utils/gestopro_navigation.dart';

import '../utils/responsive.dart';

import '../widgets/cronos_futuristic_dashboard.dart';

import '../widgets/futuristic/futuristic_nav_section.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';

import 'aereo_page.dart';

import 'prenotazione_pernottamenti_page.dart';

import 'treno_page.dart';



/// Hub admin GESTOPRO — interfaccia futuristica completa.

class AdminGestoproHubPage extends StatelessWidget {

  const AdminGestoproHubPage({

    super.key,

    required this.userId,

    required this.username,

    required this.fullName,

    required this.role,

    this.customAllowedPages,

    this.secondaryRole,

  });



  final int userId;

  final String username;

  final String fullName;

  final String role;

  final Set<String>? customAllowedPages;

  final String? secondaryRole;



  List<CronosFuturisticTile> _tiles(BuildContext context) {

    final isMobile = useMobileUi(context);

    return [

      CronosFuturisticTile(

        layoutKey: 'pernottamenti',

        icon: Icons.bed_outlined,

        label: 'Pernottamenti',

        onTap: () => openGestoproPage(

          context,

          title: 'Pernottamenti',

          page: isMobile

              ? PernottamentiMobilePage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                )

              : PrenotazionePernottamentiPage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                ),

        ),

      ),

      CronosFuturisticTile(

        layoutKey: 'treni',

        icon: Icons.train_outlined,

        label: 'Treni',

        onTap: () => openGestoproPage(

          context,

          title: 'Treni',

          page: isMobile

              ? TrenoMobilePage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                )

              : TrenoPage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                ),

        ),

      ),

      CronosFuturisticTile(

        layoutKey: 'aerei',

        icon: Icons.flight_takeoff_outlined,

        label: 'Aerei',

        onTap: () => openGestoproPage(

          context,

          title: 'Aerei',

          page: isMobile

              ? AereoMobilePage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                )

              : AereoPage(

                  username: username,

                  userId: userId,

                  role: role,

                  fullName: fullName,

                ),

        ),

      ),

      CronosFuturisticTile(

        layoutKey: 'admin_dashboard',

        icon: Icons.dashboard_customize_outlined,

        label: 'Command Center',

        subtitle: 'Tutti i moduli admin',

        onTap: () => FuturisticAdminNav.openDashboard(

          context,

          adminId: userId,

          role: role,

          username: username,

          fullName: fullName,

          customAllowedPages: customAllowedPages,

        ),

      ),

    ];

  }


  @override

  Widget build(BuildContext context) {

    return GestoproSessionScope(

      adminId: userId,

      userId: userId,

      username: username,

      fullName: fullName,

      role: role,

      customAllowedPages: customAllowedPages,

      activeSection: FuturisticNavSection.home,

      child: CronosFuturisticDashboard(

      tiles: _tiles(context),

      userDisplayName: fullName,

      username: username,

      userId: userId,

      roleLabel: role.replaceAll('_', ' '),

      activeNavSection: FuturisticNavSection.home,

      onSwitchToClassic: () => FuturisticAdminNav.exitGestoproSession(context),

      onOpenHome: null,

      onOpenDashboard: () => FuturisticAdminNav.openDashboard(

        context,

        adminId: userId,

        role: role,

        username: username,

        fullName: fullName,

        customAllowedPages: customAllowedPages,

      ),

      onOpenNotifiche: () => FuturisticAdminNav.openNotifiche(

        context,

        userId: userId,

        adminId: userId,

        role: role,

        username: username,

        fullName: fullName,

        customAllowedPages: customAllowedPages,

      ),

      onOpenAlert: () => FuturisticAdminNav.openAlert(

        context,

        userId: userId,

        adminId: userId,

        role: role,

        username: username,

        fullName: fullName,

        customAllowedPages: customAllowedPages,

      ),

      onOpenImpostazioni: () => FuturisticAdminNav.openImpostazioni(

        context,

        adminId: userId,

        role: role,

        userId: userId,

        username: username,

        fullName: fullName,

        customAllowedPages: customAllowedPages,

      ),
      onOpenSupport: () => FuturisticAdminNav.openSupporto(
        context,
        userId: userId,
        adminId: userId,
        role: role,
        username: username,
        fullName: fullName,
        customAllowedPages: customAllowedPages,
      ),

      onOpenDtView: canPreviewDtView(role)

          ? () => openDtView(

                context,

                userId: userId,

                username: username,

                fullName: fullName,

                sessionRole: role,

                sessionSecondaryRole: secondaryRole,

              )

          : null,

      ),

    );

  }

}


