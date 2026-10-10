import 'package:flutter/material.dart';

import '../pages/admin_dashboard_page.dart';
import '../pages/admin_gestopro_hub_page.dart';
import '../pages/admin_home_page.dart';
import '../Mobile/admin_scadenze_alert_mobile_page.dart';
import '../pages/admin_scadenze_alert_page.dart';
import '../pages/notifications_page.dart';
import '../pages/admin_impostazioni_gestopro_page.dart';
import '../pages/my_profile_page.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/responsive.dart';
import '../widgets/futuristic/futuristic_nav_section.dart';
import '../widgets/futuristic/futuristic_nav_shell.dart';
import '../widgets/futuristic/futuristic_page_shell.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';
import '../widgets/futuristic/gestopro_nav_sub_items_cache.dart';
import '../widgets/futuristic/gestopro_session_cache.dart';
import '../utils/dt_view_navigation.dart';
import '../utils/impostazioni_app_dialog.dart';

/// Navigazione condivisa sidebar GESTOPRO (admin).
abstract final class FuturisticAdminNav {
  FuturisticAdminNav._();

  static FuturisticNavSection _resolveTargetSection({
    required FuturisticNavSection current,
    FuturisticNavSection? explicit,
    required Widget child,
  }) {
    if (explicit != null) return explicit;
    final typeName = child.runtimeType.toString().toLowerCase();
    final isImpostazioniPage = typeName.contains('impostazioni');
    if (isImpostazioniPage) return FuturisticNavSection.impostazioni;

    // Se apro una pagina modulo da Notifiche/Alert/Impostazioni/Supporto,
    // la sidebar deve tornare su Dashboard (evita evidenziazione bloccata).
    if (current == FuturisticNavSection.notifiche ||
        current == FuturisticNavSection.alert ||
        current == FuturisticNavSection.impostazioni ||
        current == FuturisticNavSection.supporto) {
      return FuturisticNavSection.dashboard;
    }
    return current;
  }

  static Future<void> exitGestoproSession(BuildContext context) async {
    final session = GestoproSessionCache.resolve(context);
    await GestoproModePrefs.deactivate();
    ClassicNavSessionCache.markClassicChrome(forceNotify: true);
    if (!context.mounted) return;
    if (session != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AdminHomePage(
            userId: session.userId,
            username: session.username,
            fullName: session.fullName,
            role: session.role,
          ),
        ),
        (_) => false,
      );
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static bool _isAtGestoproRoot(FuturisticNavSection section) =>
      section == FuturisticNavSection.home ||
      section == FuturisticNavSection.vistaDt;

  static ({bool gestoproDtHome, String? secondaryRole}) _inheritDtFlags(
    BuildContext context,
  ) {
    final parent = GestoproSessionScope.maybeOf(context);
    final cache = GestoproSessionCache.resolve(context);
    return (
      gestoproDtHome: parent?.gestoproDtHome ?? cache?.gestoproDtHome ?? false,
      secondaryRole: parent?.secondaryRole ?? cache?.secondaryRole,
    );
  }

  static void _navigateGestoproHome(
    BuildContext context, {
    required int userId,
    required String username,
    required String fullName,
    required String role,
    Set<String>? customAllowedPages,
    required bool gestoproDtHome,
    String? secondaryRole,
  }) {
    // Admin in anteprima Vista DT: Home deve tornare all'hub admin, non restare su DT.
    if (gestoproDtHome && !canPreviewDtView(role)) {
      openDtGestoproHome(
        context,
        userId: userId,
        username: username,
        fullName: fullName,
        sessionRole: role,
        sessionSecondaryRole: secondaryRole,
        customAllowedPages: customAllowedPages,
      );
      return;
    }
    openHome(
      context,
      userId: userId,
      username: username,
      fullName: fullName,
      role: role,
      customAllowedPages: customAllowedPages,
    );
  }

  static Future<void> openHome(
    BuildContext context, {
    required int userId,
    required String username,
    required String fullName,
    required String role,
    Set<String>? customAllowedPages,
  }) async {
    final gestopro = await GestoproModePrefs.isActive();
    if (!context.mounted) return;
    final page = gestopro
        ? AdminGestoproHubPage(
            userId: userId,
            username: username,
            fullName: fullName,
            role: role,
            customAllowedPages: customAllowedPages,
          )
        : AdminHomePage(
            userId: userId,
            username: username,
            fullName: fullName,
            role: role,
          );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (_) => false,
    );
  }

  static void openDashboard(
    BuildContext context, {
    required int adminId,
    required String? role,
    required String? username,
    required String? fullName,
    Set<String>? customAllowedPages,
  }) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(
          adminId: adminId,
          role: role,
          username: username,
          fullName: fullName,
          customAllowedPages: customAllowedPages,
        ),
      ),
      (_) => false,
    );
  }

  static void openNotifiche(
    BuildContext context, {
    required int userId,
    required int adminId,
    required String? role,
    required String? username,
    required String? fullName,
    Set<String>? customAllowedPages,
  }) {
    final dtFlags = _inheritDtFlags(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => GestoproSessionScope(
          adminId: adminId,
          userId: userId,
          username: username ?? '',
          fullName: fullName ?? '',
          role: role ?? '',
          customAllowedPages: customAllowedPages,
          gestoproDtHome: dtFlags.gestoproDtHome,
          secondaryRole: dtFlags.secondaryRole,
          activeSection: FuturisticNavSection.notifiche,
          child: FuturisticNavShell(
            activeSection: FuturisticNavSection.notifiche,
            onHome: () => _navigateGestoproHome(
              ctx,
              userId: userId,
              username: username ?? '',
              fullName: fullName ?? '',
              role: role ?? '',
              customAllowedPages: customAllowedPages,
              gestoproDtHome: dtFlags.gestoproDtHome,
              secondaryRole: dtFlags.secondaryRole,
            ),
            onDashboard: () => openDashboard(
              ctx,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onNotifiche: null,
            onAlert: () => openAlert(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onImpostazioni: () => openImpostazioni(
              ctx,
              adminId: adminId,
              role: role,
              userId: userId,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onSupporto: () => openSupporto(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            child: NotificationsPage(userId: userId),
          ),
        ),
      ),
    );
  }

  static void openAlert(
    BuildContext context, {
    required int userId,
    required int adminId,
    required String? role,
    required String? username,
    required String? fullName,
    Set<String>? customAllowedPages,
  }) {
    final dtFlags = _inheritDtFlags(context);
    final alertPage = useMobileUi(context)
        ? const AdminScadenzeAlertMobilePage()
        : const AdminScadenzeAlertPage(hideTopLogo: true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => GestoproSessionScope(
          adminId: adminId,
          userId: userId,
          username: username ?? '',
          fullName: fullName ?? '',
          role: role ?? '',
          customAllowedPages: customAllowedPages,
          gestoproDtHome: dtFlags.gestoproDtHome,
          secondaryRole: dtFlags.secondaryRole,
          activeSection: FuturisticNavSection.alert,
          child: FuturisticNavShell(
            activeSection: FuturisticNavSection.alert,
            onHome: () => _navigateGestoproHome(
              ctx,
              userId: userId,
              username: username ?? '',
              fullName: fullName ?? '',
              role: role ?? '',
              customAllowedPages: customAllowedPages,
              gestoproDtHome: dtFlags.gestoproDtHome,
              secondaryRole: dtFlags.secondaryRole,
            ),
            onDashboard: () => openDashboard(
              ctx,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onNotifiche: () => openNotifiche(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onAlert: null,
            onImpostazioni: () => openImpostazioni(
              ctx,
              adminId: adminId,
              role: role,
              userId: userId,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onSupporto: () => openSupporto(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            child: alertPage,
          ),
        ),
      ),
    );
  }

  static void openImpostazioni(
    BuildContext context, {
    required int adminId,
    required String? role,
    required int userId,
    required String? username,
    required String? fullName,
    Set<String>? customAllowedPages,
    void Function(BuildContext ctx)? onPuliziaDati,
  }) {
    if (GestoproModePrefs.sessionActive) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => AdminImpostazioniGestoproPage(
            adminId: adminId,
            userId: userId,
            role: role,
            username: username,
            fullName: fullName,
            customAllowedPages: customAllowedPages,
            onPuliziaDati: onPuliziaDati,
          ),
        ),
      );
      return;
    }

    showImpostazioniAppDialog(
      context,
      adminId: adminId,
      role: role,
      onPuliziaDati: onPuliziaDati,
    );
  }

  static void openSupporto(
    BuildContext context, {
    required int userId,
    required int adminId,
    required String? role,
    required String? username,
    required String? fullName,
    Set<String>? customAllowedPages,
  }) {
    final dtFlags = _inheritDtFlags(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => GestoproSessionScope(
          adminId: adminId,
          userId: userId,
          username: username ?? '',
          fullName: fullName ?? '',
          role: role ?? '',
          customAllowedPages: customAllowedPages,
          gestoproDtHome: dtFlags.gestoproDtHome,
          secondaryRole: dtFlags.secondaryRole,
          activeSection: FuturisticNavSection.supporto,
          child: FuturisticNavShell(
            activeSection: FuturisticNavSection.supporto,
            onHome: () => _navigateGestoproHome(
              ctx,
              userId: userId,
              username: username ?? '',
              fullName: fullName ?? '',
              role: role ?? '',
              customAllowedPages: customAllowedPages,
              gestoproDtHome: dtFlags.gestoproDtHome,
              secondaryRole: dtFlags.secondaryRole,
            ),
            onDashboard: () => openDashboard(
              ctx,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onNotifiche: () => openNotifiche(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onAlert: () => openAlert(
              ctx,
              userId: userId,
              adminId: adminId,
              role: role,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onImpostazioni: () => openImpostazioni(
              ctx,
              adminId: adminId,
              role: role,
              userId: userId,
              username: username,
              fullName: fullName,
              customAllowedPages: customAllowedPages,
            ),
            onSupporto: null,
            child: const MyProfilePage(),
          ),
        ),
      ),
    );
  }

  /// Shell GESTOPRO con sidebar per pagine aperte dalla navigazione interna.
  static Widget wrapGestoproNavDestination({
    required BuildContext context,
    required Widget child,
    FuturisticNavSection? activeSection,
    List<FuturisticNavSubItem>? subItems,
    String? activeSubKey,
    String? fallbackTitle,
  }) {
    final snapshot = GestoproSessionCache.resolve(context);
    if (snapshot == null) {
      return FuturisticPageShell(
        title: fallbackTitle,
        child: child,
      );
    }

    final resolvedSection = _resolveTargetSection(
      current: snapshot.activeSection,
      explicit: activeSection,
      child: child,
    );
    final resolvedSubItems = subItems ??
        (GestoproNavSubItemsCache.items.isNotEmpty
            ? GestoproNavSubItemsCache.items
            : (snapshot.subItems.isNotEmpty
                ? snapshot.subItems
                : const <FuturisticNavSubItem>[]));
    final resolvedActiveSubKey = activeSubKey ??
        snapshot.activeSubKey ??
        GestoproNavSubItemsCache.activeKey;
    if (activeSubKey != null) {
      final itemsToCache = GestoproNavSubItemsCache.items.isNotEmpty
          ? GestoproNavSubItemsCache.items
          : resolvedSubItems;
      final key = activeSubKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GestoproNavSubItemsCache.update(
          itemsToCache,
          activeSubKey: key,
        );
      });
    }
    final scoped = snapshot.copyWith(
      activeSection: resolvedSection,
      subItems: resolvedSubItems,
      activeSubKey: resolvedActiveSubKey,
    );

    return scoped.wrap(
      activeSection: scoped.activeSection,
      subItems: scoped.subItems,
      activeSubKey: scoped.activeSubKey,
      child: FuturisticNavShell(
        activeSection: scoped.activeSection,
        subItems: scoped.subItems,
        activeSubKey: scoped.activeSubKey,
        onHome: _isAtGestoproRoot(scoped.activeSection)
            ? null
            : () => _navigateGestoproHome(
                  context,
                  userId: scoped.userId,
                  username: scoped.username,
                  fullName: scoped.fullName,
                  role: scoped.role,
                  customAllowedPages: scoped.customAllowedPages,
                  gestoproDtHome: scoped.gestoproDtHome ?? false,
                  secondaryRole: scoped.secondaryRole,
                ),
        onDashboard: scoped.activeSection == FuturisticNavSection.dashboard
            ? null
            : () => openDashboard(
                  context,
                  adminId: scoped.adminId,
                  role: scoped.role,
                  username: scoped.username,
                  fullName: scoped.fullName,
                  customAllowedPages: scoped.customAllowedPages,
                ),
        onNotifiche: scoped.activeSection == FuturisticNavSection.notifiche
            ? null
            : () => openNotifiche(
                  context,
                  userId: scoped.userId,
                  adminId: scoped.adminId,
                  role: scoped.role,
                  username: scoped.username,
                  fullName: scoped.fullName,
                  customAllowedPages: scoped.customAllowedPages,
                ),
        onAlert: scoped.activeSection == FuturisticNavSection.alert
            ? null
            : () => openAlert(
                  context,
                  userId: scoped.userId,
                  adminId: scoped.adminId,
                  role: scoped.role,
                  username: scoped.username,
                  fullName: scoped.fullName,
                  customAllowedPages: scoped.customAllowedPages,
                ),
        onImpostazioni:
            scoped.activeSection == FuturisticNavSection.impostazioni
                ? null
                : () => openImpostazioni(
                      context,
                      adminId: scoped.adminId,
                      role: scoped.role,
                      userId: scoped.userId,
                      username: scoped.username,
                      fullName: scoped.fullName,
                      customAllowedPages: scoped.customAllowedPages,
                    ),
        onSupporto: scoped.activeSection == FuturisticNavSection.supporto
            ? null
            : () => openSupporto(
                  context,
                  userId: scoped.userId,
                  adminId: scoped.adminId,
                  role: scoped.role,
                  username: scoped.username,
                  fullName: scoped.fullName,
                  customAllowedPages: scoped.customAllowedPages,
                ),
        child: child,
      ),
    );
  }
}
