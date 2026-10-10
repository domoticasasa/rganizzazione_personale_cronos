import 'dart:async';

import 'package:flutter/material.dart';

import '../Mobile/admin_scadenze_alert_mobile_page.dart';
import '../pages/admin_dashboard_page.dart';
import '../pages/admin_home_page.dart';
import '../pages/admin_scadenze_alert_page.dart';
import '../pages/dt_home_page.dart';
import '../pages/my_profile_page.dart';
import '../pages/notifications_page.dart';
import '../services/app_branding_service.dart';
import '../services/app_theme_mode_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/classic_nav_sub_items_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/app_logout.dart';
import '../utils/app_navigator.dart';
import '../utils/app_copyright.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/dt_view_navigation.dart';
import '../utils/impostazioni_app_dialog.dart';
import '../utils/responsive.dart';
import '../utils/roles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'classic_app_bar_chrome.dart';
import 'nav_tree_lines.dart';
import 'futuristic/futuristic_nav_sub_item.dart';
import 'futuristic/nexus_clock.dart';
import 'linked_scrollbar.dart';
import 'user_profile_avatar.dart';

export '../services/classic_nav_session_cache.dart'
    show ClassicNavSection, shouldShowClassicRail;

/// Evita di disegnare due rail una dentro l'altra.
class ClassicRailScope extends InheritedWidget {
  const ClassicRailScope({super.key, required super.child});

  static bool activeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ClassicRailScope>() != null;

  @override
  bool updateShouldNotify(covariant ClassicRailScope oldWidget) => false;
}

const double kClassicRailMiniWidth = 56;

double classicRailWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < CronosBreakpoints.tablet) return 200;
  if (w < CronosBreakpoints.desktop) return 220;
  return 248;
}

/// Rail sinistra: stesse funzioni/sotto-voci di Gestopro, stile classico.
/// [expanded] false = mini-barra icone; true = pannello completo.
class ClassicNavRail extends StatelessWidget {
  const ClassicNavRail({
    super.key,
    required this.session,
    this.activeSection = ClassicNavSection.home,
    this.subItems = const <FuturisticNavSubItem>[],
    this.activeSubKey,
    this.expanded = true,
  });

  final ClassicNavSessionSnapshot session;
  final ClassicNavSection activeSection;
  final List<FuturisticNavSubItem> subItems;
  final String? activeSubKey;
  final bool expanded;

  bool _isDtLike(String role) {
    final r = normalizeRole(role);
    return r == 'dt' || r == 'assistente_dt';
  }

  NavigatorState? get _nav =>
      appNavigatorKey.currentState ??
      (appNavigatorContext != null
          ? Navigator.maybeOf(appNavigatorContext!)
          : null);

  Future<void> _openHome(BuildContext context) async {
    final s = session;
    final nav = _nav ?? Navigator.maybeOf(context);
    if (nav == null) return;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.home);
    // Admin (anche dopo anteprima Vista DT): sempre home admin.
    final home = canPreviewDtView(s.role) || isAnyAdminRole(s.role)
        ? AdminHomePage(
            username: s.username,
            fullName: s.fullName,
            role: s.role,
            userId: s.userId,
            secondaryRole: s.secondaryRole,
          )
        : _isDtLike(s.role)
            ? DtHomePage(
                username: s.username,
                fullName: s.fullName,
                role: s.role,
                userId: s.userId,
                secondaryRole: s.secondaryRole,
              )
            : AdminHomePage(
                username: s.username,
                fullName: s.fullName,
                role: s.role,
                userId: s.userId,
                secondaryRole: s.secondaryRole,
              );
    await nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => home),
      (_) => false,
    );
  }

  void _openDashboard(BuildContext context) {
    final s = session;
    final nav = _nav ?? Navigator.maybeOf(context);
    if (nav == null) return;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.dashboard);
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(
          adminId: s.userId,
          role: s.role,
          username: s.username,
          fullName: s.fullName,
          forceClassic: true,
        ),
      ),
      (_) => false,
    );
  }

  void _openNotifiche(BuildContext context) {
    final nav = _nav ?? Navigator.maybeOf(context);
    if (nav == null) return;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.notifiche);
    nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsPage(userId: session.userId),
      ),
    );
  }

  void _openAlert(BuildContext context) {
    final nav = _nav ?? Navigator.maybeOf(context);
    if (nav == null) return;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.alert);
    final page = useMobileUi(context)
        ? const AdminScadenzeAlertMobilePage()
        : const AdminScadenzeAlertPage(hideTopLogo: true);
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  void _openImpostazioni(BuildContext context) {
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.impostazioni);
    final dialogCtx = appNavigatorContext ?? context;
    showImpostazioniAppDialog(
      dialogCtx,
      adminId: session.userId,
      role: session.role,
    );
  }

  void _openProfilo(BuildContext context) {
    final nav = _nav ?? Navigator.maybeOf(context);
    if (nav == null) return;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.profilo);
    nav.push(
      MaterialPageRoute(builder: (_) => const MyProfilePage()),
    );
  }

  void _openVistaDt(BuildContext context) {
    final s = session;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.vistaDt);
    final openCtx = appNavigatorContext ?? context;
    openDtView(
      openCtx,
      userId: s.userId,
      username: s.username,
      fullName: s.fullName,
      sessionRole: s.role,
      sessionSecondaryRole: s.secondaryRole,
    );
  }

  void _openVistaDipendente(BuildContext context) {
    final s = session;
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.vistaDipendente);
    final openCtx = appNavigatorContext ?? context;
    openDipendenteView(
      openCtx,
      userId: s.userId,
      username: s.username,
      fullName: s.fullName,
    );
  }

  Future<void> _logout(BuildContext context) => performAppLogout(context);

  Widget _iconOnly({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required bool active,
    Color? accent,
    Widget? leading,
  }) {
    final fg = classicSidebarFg;
    final nav = classicNavAccentColor;
    final color = accent ?? (active ? nav : fg);
    // Niente Tooltip qui: la rail vive nel MaterialApp.builder (fuori Overlay
    // del Navigator). Semantics copre l'accessibilità senza Overlay.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Semantics(
        label: tooltip,
        button: true,
        child: Material(
          color: active
              ? nav.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 42,
              child: Center(
                child: leading ?? Icon(icon, color: color, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainBlock({
    required ClassicNavSection section,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool dense,
    Color? accent,
    Widget? leading,
    bool selectable = true,
    bool enableSubItems = true,
  }) {
    final active = selectable && activeSection == section;
    final fg = classicSidebarFg;
    final nav = classicNavAccentColor;
    final color = accent ?? (active ? nav : fg);

    if (!expanded) {
      return _iconOnly(
        icon: icon,
        tooltip: label,
        onTap: onTap,
        active: active,
        accent: accent,
        leading: leading,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: 2),
          child: Material(
            color: active
                ? nav.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 8 : 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      leading ??
                          Icon(icon, color: color, size: dense ? 20 : 22),
                      SizedBox(width: dense ? 8 : 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w600,
                            fontSize: dense ? 13 : 14,
                          ),
                        ),
                      ),
                      Icon(
                        active && enableSubItems && subItems.isNotEmpty
                            ? Icons.expand_more
                            : Icons.chevron_right,
                        size: 18,
                        color: color.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (active && enableSubItems && subItems.isNotEmpty)
          _ClassicSubNavTree(
            items: subItems,
            activeSubKey: activeSubKey,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppBrandingService.instance,
        AppThemeModeService.instance,
      ]),
      builder: (context, _) {
        final fullWidth = classicRailWidth(context);
        final width = expanded ? fullWidth : kClassicRailMiniWidth;
        final dense = fullWidth < 220;
        final s = session;
        final isAdmin = isAnyAdminRole(s.role);
        final showDt = canPreviewDtView(s.role);
        final showDipendente = canPreviewDipendenteView(s.role);
        final bar = classicAppBarColor;
        final side = classicSidebarColor;
        final dark = AppThemeModeService.instance.isDark;
        final divider = classicSidebarDivider;

        return Material(
          elevation: 0,
          color: side,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fascia continua con l'AppBar (niente bordo destro qui).
                ColoredBox(
                  color: bar,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: Align(
                        alignment: expanded
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: expanded ? (dense ? 10 : 16) : 0,
                          ),
                          child: expanded
                              ? const Text(
                                  'NAVIGAZIONE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                )
                              : const Icon(
                                  Icons.menu_open_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: bar, width: 1),
                      ),
                    ),
                    child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Expanded(
                      child: _ClassicNavScroll(
                        children: [
                          _mainBlock(
                            section: ClassicNavSection.home,
                            icon: Icons.home_outlined,
                            label: 'Home',
                            dense: dense,
                            onTap: () => _openHome(context),
                          ),
                          if (isAdmin)
                            _mainBlock(
                              section: ClassicNavSection.dashboard,
                              icon: Icons.dashboard_rounded,
                              label: 'Dashboard',
                              dense: dense,
                              onTap: () => _openDashboard(context),
                            ),
                          _mainBlock(
                            section: ClassicNavSection.notifiche,
                            icon: Icons.notifications_outlined,
                            label: 'Notifiche',
                            dense: dense,
                            onTap: () => _openNotifiche(context),
                          ),
                          if (isAdmin)
                            _mainBlock(
                              section: ClassicNavSection.alert,
                              icon: Icons.warning_amber_rounded,
                              label: 'Alert',
                              dense: dense,
                              accent: const Color(0xFFC62828),
                              onTap: () => _openAlert(context),
                            ),
                          if (isAdmin)
                            _mainBlock(
                              section: ClassicNavSection.impostazioni,
                              icon: Icons.settings_outlined,
                              label: 'Impostazioni',
                              dense: dense,
                              onTap: () => _openImpostazioni(context),
                            ),
                          _mainBlock(
                            section: ClassicNavSection.profilo,
                            icon: Icons.person_outline_rounded,
                            label: 'Profilo',
                            dense: dense,
                            leading: SessionUserAvatar(
                              radius: expanded ? 9 : 11,
                              displayName: s.fullName,
                              username: s.username,
                              usersTableId: s.userId,
                            ),
                            onTap: () => _openProfilo(context),
                          ),
                          if (showDipendente)
                            _mainBlock(
                              section: ClassicNavSection.vistaDipendente,
                              icon: Icons.switch_account_outlined,
                              label: activeSection ==
                                      ClassicNavSection.vistaDipendente
                                  ? 'Torna ad Admin'
                                  : 'Vista dipendente',
                              dense: dense,
                              enableSubItems: false,
                              onTap: () {
                                if (activeSection ==
                                    ClassicNavSection.vistaDipendente) {
                                  ClassicNavSessionCache.setActiveSection(
                                    ClassicNavSection.home,
                                  );
                                  final nav = _nav ?? Navigator.maybeOf(context);
                                  if (nav != null && nav.canPop()) {
                                    nav.pop();
                                    return;
                                  }
                                  unawaited(_openHome(context));
                                  return;
                                }
                                _openVistaDipendente(context);
                              },
                            ),
                          if (showDt)
                            _mainBlock(
                              section: ClassicNavSection.vistaDt,
                              icon: Icons.assignment_ind_outlined,
                              label: activeSection == ClassicNavSection.vistaDt
                                  ? 'Torna ad Admin'
                                  : 'Vista DT',
                              dense: dense,
                              enableSubItems: false,
                              onTap: () {
                                if (activeSection == ClassicNavSection.vistaDt) {
                                  ClassicNavSessionCache.setActiveSection(
                                    ClassicNavSection.home,
                                  );
                                  final nav =
                                      _nav ?? Navigator.maybeOf(context);
                                  if (nav != null && nav.canPop()) {
                                    nav.pop();
                                    return;
                                  }
                                  unawaited(_openHome(context));
                                  return;
                                }
                                _openVistaDt(context);
                              },
                            ),
                          ListenableBuilder(
                            listenable: AppThemeModeService.instance,
                            builder: (context, _) {
                              final darkMode =
                                  AppThemeModeService.instance.isDark;
                              return _mainBlock(
                                section: ClassicNavSection.profilo,
                                icon: darkMode
                                    ? Icons.light_mode_outlined
                                    : Icons.dark_mode_outlined,
                                label: darkMode ? 'Tema chiaro' : 'Tema scuro',
                                dense: dense,
                                selectable: false,
                                enableSubItems: false,
                                onTap: () {
                                  unawaited(
                                    AppThemeModeService.instance.toggle(),
                                  );
                                },
                              );
                            },
                          ),
                          _mainBlock(
                            section: ClassicNavSection.logout,
                            icon: Icons.logout_rounded,
                            label: 'Logout',
                            dense: dense,
                            accent: const Color(0xFFC62828),
                            enableSubItems: false,
                            onTap: () => _logout(context),
                          ),
                          if (expanded) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: dense ? 12 : 20,
                                vertical: 8,
                              ),
                              child: Divider(height: 1, color: divider),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(6, 0, 6, 4),
                              child: NexusClock(compact: true),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                              child: AppCopyrightFooter(
                                compact: true,
                                lightOnDark: dark,
                              ),
                            ),
                          ] else ...[
                            Divider(height: 1, color: divider),
                            const Padding(
                              padding:
                                  EdgeInsets.fromLTRB(4, 6, 4, 4),
                              child: NexusClock(
                                compact: true,
                                verticalCompact: true,
                              ),
                            ),
                            Builder(
                              builder: (btnCtx) => _iconOnly(
                                icon: Icons.copyright_outlined,
                                tooltip: 'Copyright',
                                active: false,
                                onTap: () =>
                                    AppCopyright.showNotice(btnCtx),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class _ClassicNavScroll extends StatefulWidget {
  const _ClassicNavScroll({required this.children});

  final List<Widget> children;

  @override
  State<_ClassicNavScroll> createState() => _ClassicNavScrollState();
}

class _ClassicNavScrollState extends State<_ClassicNavScroll> {
  final ScrollController _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinkedScrollbar(
      controller: _ctrl,
      child: ListView(
        controller: _ctrl,
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        clipBehavior: Clip.hardEdge,
        children: widget.children,
      ),
    );
  }
}

class _ClassicSubNavTree extends StatelessWidget {
  const _ClassicSubNavTree({
    required this.items,
    this.activeSubKey,
    this.depth = 0,
  });

  final List<FuturisticNavSubItem> items;
  final String? activeSubKey;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final line = classicSidebarFg.withValues(alpha: 0.32);
    return Padding(
      padding: EdgeInsets.only(
        left: depth == 0 ? 14 : 0,
        right: 8,
        bottom: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            _ClassicSubNavBranch(
              item: items[i],
              activeSubKey: activeSubKey,
              depth: depth,
              isLast: i == items.length - 1,
              lineColor: line,
            ),
        ],
      ),
    );
  }
}

class _ClassicSubNavBranch extends StatelessWidget {
  const _ClassicSubNavBranch({
    required this.item,
    required this.activeSubKey,
    required this.depth,
    required this.isLast,
    required this.lineColor,
  });

  final FuturisticNavSubItem item;
  final String? activeSubKey;
  final int depth;
  final bool isLast;
  final Color lineColor;

  bool _containsActive(FuturisticNavSubItem node) {
    if (node.key == activeSubKey) return true;
    for (final child in node.children) {
      if (_containsActive(child)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ClassicNavSubItemsCache.manuallyExpanded,
      builder: (context, _) {
        final active = item.key == activeSubKey;
        final hasChildren = item.children.isNotEmpty;
        final expanded = hasChildren &&
            (_containsActive(item) ||
                ClassicNavSubItemsCache.isManuallyExpanded(item.key));
        return NavTreeBranch(
          lineColor: lineColor,
          isLast: isLast,
          item: _ClassicSubSideItem(
            item: item,
            active: active,
            depth: depth,
            expanded: expanded,
            isLast: isLast && !expanded,
            onToggleExpand: hasChildren
                ? () => ClassicNavSubItemsCache.toggleExpanded(item.key)
                : null,
          ),
          childTree: expanded
              ? _ClassicSubNavTree(
                  items: item.children,
                  activeSubKey: activeSubKey,
                  depth: depth + 1,
                )
              : null,
        );
      },
    );
  }
}

class _ClassicSubSideItem extends StatelessWidget {
  const _ClassicSubSideItem({
    required this.item,
    required this.active,
    required this.depth,
    required this.expanded,
    required this.isLast,
    this.onToggleExpand,
  });

  final FuturisticNavSubItem item;
  final bool active;
  final int depth;
  final bool expanded;
  final bool isLast;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final baseFg = classicSidebarFg;
    final accent = item.accentColor ?? classicNavAccentColor;
    final fg = active ? accent : baseFg.withValues(alpha: 0.85);
    final hasChildren = item.children.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (hasChildren && onToggleExpand != null) {
            onToggleExpand!();
          }
          item.onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active ? accent.withValues(alpha: 0.12) : null,
            border: active
                ? Border.all(color: accent.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 15, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              if (hasChildren)
                InkWell(
                  onTap: onToggleExpand,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              if (item.badge != null && item.badge!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.badge!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shell globale: sidebar classica a scomparsa (mini-barra → apre all'hover).
class ClassicSidebarShell extends StatefulWidget {
  const ClassicSidebarShell({super.key, required this.child});

  final Widget child;

  @override
  State<ClassicSidebarShell> createState() => _ClassicSidebarShellState();
}

class _ClassicSidebarShellState extends State<ClassicSidebarShell> {
  bool _expanded = false;
  Timer? _expandTimer;
  Timer? _collapseTimer;

  static const _expandDelay = Duration(milliseconds: 750);
  static const _collapseDelay = Duration(milliseconds: 320);

  @override
  void dispose() {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _onEnter() {
    _collapseTimer?.cancel();
    if (_expanded) return;
    _expandTimer?.cancel();
    _expandTimer = Timer(_expandDelay, () {
      if (!mounted) return;
      setState(() => _expanded = true);
    });
  }

  void _onExit() {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    if (!_expanded) return;
    _collapseTimer = Timer(_collapseDelay, () {
      if (!mounted) return;
      setState(() => _expanded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ClassicNavSessionCache.notifier,
        ClassicNavSessionCache.classicChromeActive,
        ClassicNavSessionCache.activeSection,
        ClassicNavSubItemsCache.revision,
        ClassicNavSubItemsCache.manuallyExpanded,
        GestoproModePrefs.sessionActiveListenable,
      ]),
      builder: (context, _) {
        final snap = ClassicNavSessionCache.current;
        final hasAuth =
            Supabase.instance.client.auth.currentSession != null;
        final show = hasAuth &&
            !GestoproModePrefs.sessionActive &&
            ClassicNavSessionCache.classicChromeActive.value &&
            snap != null &&
            shouldShowClassicRail(context) &&
            !ClassicRailScope.activeOf(context);
        if (!show) return widget.child;

        final section = ClassicNavSessionCache.activeSection.value;
        final List<FuturisticNavSubItem> subItems;
        switch (section) {
          case ClassicNavSection.home:
            subItems = ClassicNavSubItemsCache.homeItems;
          case ClassicNavSection.dashboard:
            subItems = ClassicNavSubItemsCache.dashboardItems;
          default:
            subItems = const [];
        }

        final fullW = classicRailWidth(context);
        final targetW = _expanded ? fullW : kClassicRailMiniWidth;
        // Larghezza contenuto fissa (full/mini): durante l'animazione il parent
        // clippa, così i Row del layout espanso non overflowano a destra.
        final contentW = _expanded ? fullW : kClassicRailMiniWidth;

        return ClassicRailScope(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MouseRegion(
                onEnter: (_) => _onEnter(),
                onExit: (_) => _onExit(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: targetW,
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final h = box.maxHeight;
                        return OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: contentW,
                          maxWidth: contentW,
                          minHeight: h,
                          maxHeight: h,
                          child: SizedBox(
                            width: contentW,
                            height: h,
                            child: ClassicNavRail(
                              session: snap,
                              activeSection: section,
                              subItems: subItems,
                              activeSubKey: ClassicNavSubItemsCache.activeKey,
                              expanded: _expanded,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),
        );
      },
    );
  }
}
