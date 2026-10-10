import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/admin_gestopro_hub_page.dart';
import '../services/app_branding_service.dart';
import '../services/app_theme_mode_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../theme/cronos_app_themes.dart';
import '../utils/app_logout.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/dt_view_navigation.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/responsive.dart';
import '../utils/roles.dart';
import '../utils/video_gallery_navigation.dart';
import 'app_logo.dart';
import 'app_theme_mode_toggle.dart';
import 'futuristic/nexus_clock.dart';

/// Fallback AppBar classica; colore runtime: [classicAppBarColor].
const Color kClassicAppBarColor = Color(0xFF1565C0);
const Color kClassicAppBarForeground = Colors.white;

/// Barra superiore: branding in chiaro, quasi-nera in scuro.
Color get classicAppBarColor => AppThemeModeService.instance.isDark
    ? CronosAppThemes.darkAppBar
    : AppBrandingService.instance.topBarColor;

/// Sidebar classica: branding in chiaro, scuro pieno in dark mode.
Color get classicSidebarColor => AppThemeModeService.instance.isDark
    ? CronosAppThemes.darkSidebar
    : AppBrandingService.instance.sidebarColor;

/// Accento voci attive / highlight (sempre blu branding).
Color get classicNavAccentColor => AppBrandingService.instance.topBarColor;

Color get classicSidebarFg => AppThemeModeService.instance.isDark
    ? CronosAppThemes.darkSidebarFg
    : const Color(0xFF1E3A5F);

Color get classicSidebarDivider => AppThemeModeService.instance.isDark
    ? Colors.white.withValues(alpha: 0.12)
    : const Color(0xFFB9CDEE);

/// Menu account su viewport stretto (mobile web): Logout / Vista DT / ecc.
/// La rail classica è nascosta sotto 600px, quindi senza questo restano introvabili.
class ClassicMobileAccountMenu extends StatelessWidget {
  const ClassicMobileAccountMenu({super.key});

  Future<void> _logout(BuildContext context) => performAppLogout(context);

  Future<void> _openGestopro(BuildContext context, ClassicNavSessionSnapshot s) async {
    ClassicNavSessionCache.markGestoproChrome();
    final role = normalizeRole(s.role);
    if (role == 'dt' || role == 'assistente_dt') {
      await openDtGestoproSession(
        context,
        userId: s.userId,
        username: s.username,
        fullName: s.fullName,
        sessionRole: s.role,
        sessionSecondaryRole: s.secondaryRole,
        requirePassword: false,
      );
      return;
    }
    GestoproModePrefs.sessionActive = true;
    unawaited(GestoproModePrefs.activate());
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AdminGestoproHubPage(
          userId: s.userId,
          username: s.username,
          fullName: s.fullName,
          role: s.role,
          secondaryRole: s.secondaryRole,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ClassicNavSessionCache.current;
    if (s == null) return const SizedBox.shrink();
    final showDt = canPreviewDtView(s.role);
    final showDipendente = canPreviewDipendenteView(s.role);
    final showGestopro = isAnyAdminRole(s.role) ||
        normalizeRole(s.role) == 'dt' ||
        normalizeRole(s.role) == 'assistente_dt';

    return ListenableBuilder(
      listenable: AppThemeModeService.instance,
      builder: (context, _) {
        final dark = AppThemeModeService.instance.isDark;
        final menuBg = dark
            ? CronosAppThemes.darkSurfaceHigh
            : Colors.white;
        final menuFg = dark
            ? CronosAppThemes.darkSidebarFg
            : const Color(0xFF1A2B5C);
        return PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert, color: kClassicAppBarForeground),
          color: menuBg,
          surfaceTintColor: Colors.transparent,
          onSelected: (value) {
            switch (value) {
              case 'gestopro':
                unawaited(_openGestopro(context, s));
              case 'vista_dt':
                ClassicNavSessionCache.setActiveSection(ClassicNavSection.vistaDt);
                openDtView(
                  context,
                  userId: s.userId,
                  username: s.username,
                  fullName: s.fullName,
                  sessionRole: s.role,
                  sessionSecondaryRole: s.secondaryRole,
                );
              case 'vista_dipendente':
                ClassicNavSessionCache.setActiveSection(
                  ClassicNavSection.vistaDipendente,
                );
                unawaited(
                  openDipendenteView(
                    context,
                    userId: s.userId,
                    username: s.username,
                    fullName: s.fullName,
                  ),
                );
              case 'video':
                unawaited(
                  VideoGalleryNavigation.open(context, role: s.role),
                );
              case 'theme':
                unawaited(AppThemeModeService.instance.toggle());
              case 'logout':
                unawaited(_logout(context));
            }
          },
          itemBuilder: (_) => [
            if (showGestopro)
              PopupMenuItem(
                value: 'gestopro',
                height: 44,
                child: _ClassicMenuRow(
                  icon: Icons.grid_view_rounded,
                  label: 'Gestopro',
                  color: menuFg,
                ),
              ),
            if (showDt)
              PopupMenuItem(
                value: 'vista_dt',
                height: 44,
                child: _ClassicMenuRow(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Vista DT',
                  color: menuFg,
                ),
              ),
            if (showDipendente)
              PopupMenuItem(
                value: 'vista_dipendente',
                height: 44,
                child: _ClassicMenuRow(
                  icon: Icons.switch_account_outlined,
                  label: 'Vista dipendente',
                  color: menuFg,
                ),
              ),
            PopupMenuItem(
              value: 'video',
              height: 44,
              child: _ClassicMenuRow(
                icon: Icons.video_library_outlined,
                label: 'Video istruttivi',
                color: menuFg,
              ),
            ),
            PopupMenuItem(
              value: 'theme',
              height: 44,
              child: _ClassicMenuRow(
                icon: dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: dark ? 'Tema chiaro' : 'Tema scuro',
                color: menuFg,
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              height: 44,
              child: _ClassicMenuRow(
                icon: Icons.logout_rounded,
                label: 'Logout',
                color: Color(0xFFC62828),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClassicMenuRow extends StatelessWidget {
  const _ClassicMenuRow({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Non ereditare il bianco dell'AppBar: il popup è su superficie chiara/scura.
    final fallback = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF1A2B5C);
    final c = color ?? fallback;
    return Row(
      children: [
        Icon(icon, size: 22, color: c),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

/// Titolo AppBar classica: CRONOS/GESTOPRO + contenuto pagina (+ orologio se serve).
class ClassicAppBarTitle extends StatelessWidget {
  const ClassicAppBarTitle({super.key, required this.child});

  final Widget child;

  Widget _mobileTitle(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(color: kClassicAppBarForeground),
      child: IconTheme.merge(
        data: const IconThemeData(color: kClassicAppBarForeground),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isGestoproFuturisticUi(context)) {
      return child;
    }
    if (useMobileUi(context)) return _mobileTitle(context);
    final showClock = showClassicAppBarClock(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) return _mobileTitle(context);
        return Row(
          children: [
            CronosGestoproWordmark(compact: false, lightOnDark: true),
            const SizedBox(width: 10),
            DefaultTextStyle.merge(
              style: const TextStyle(color: kClassicAppBarForeground),
              child: IconTheme.merge(
                data: const IconThemeData(color: kClassicAppBarForeground),
                child: Expanded(child: child),
              ),
            ),
            if (showClock) ...[
              const SizedBox(width: 8),
              const NexusClock(compact: true),
              const SizedBox(width: 4),
              const NexusAgendaPill(compact: true),
            ],
          ],
        );
      },
    );
  }
}

String? _extractTitleText(Widget? title) {
  if (title == null) return null;
  if (title is Text) return title.data;
  if (title is ResponsiveAppBarTitle) return null;
  if (title is WelcomeAppBarTitle) return null;
  if (title is ClassicAppBarTitle) return null;
  if (title is Expanded) return _extractTitleText(title.child);
  if (title is Flexible) return _extractTitleText(title.child);
  if (title is Padding) return _extractTitleText(title.child);
  if (title is Center) return _extractTitleText(title.child);
  if (title is Align) return _extractTitleText(title.child);
  if (title is SizedBox) return _extractTitleText(title.child);
  if (title is Row) {
    for (final c in title.children) {
      final s = _extractTitleText(c);
      if (s != null && s.trim().isNotEmpty) return s;
    }
  }
  return null;
}

bool _titleAlreadyHasClassicChrome(Widget? title) {
  if (title is WelcomeAppBarTitle) return true;
  if (title is ClassicAppBarTitle) return true;
  if (title is ResponsiveAppBarTitle && title.showBrandAndClock) return true;
  return false;
}

bool _actionsContainMobileMenu(List<Widget>? actions) {
  if (actions == null) return false;
  for (final a in actions) {
    if (a is ClassicMobileAccountMenu) return true;
  }
  return false;
}

bool _actionsContainThemeToggle(List<Widget>? actions) {
  if (actions == null) return false;
  for (final a in actions) {
    if (a is AppThemeModeToggleIconButton) return true;
  }
  return false;
}

AppBar _paintClassicAppBar(
  BuildContext context,
  AppBar a, {
  required Widget title,
}) {
  final needMobileMenu = !shouldShowClassicRail(context) &&
      ClassicNavSessionCache.current != null &&
      !isGestoproFuturisticUi(context);

  List<Widget>? actions = a.actions;
  if (needMobileMenu) {
    final next = <Widget>[...?actions];
    if (!_actionsContainThemeToggle(next)) {
      next.add(
        const AppThemeModeToggleIconButton(color: kClassicAppBarForeground),
      );
    }
    if (!_actionsContainMobileMenu(next)) {
      next.add(const ClassicMobileAccountMenu());
    }
    actions = next;
  } else if (!shouldShowClassicRail(context) &&
      !isGestoproFuturisticUi(context) &&
      !_actionsContainThemeToggle(actions)) {
    // Area dipendente / pagine senza sessione rail: tema comunque raggiungibile.
    actions = <Widget>[
      ...?actions,
      const AppThemeModeToggleIconButton(color: kClassicAppBarForeground),
    ];
  }

  return AppBar(
    key: a.key,
    leading: a.leading,
    automaticallyImplyLeading: a.automaticallyImplyLeading,
    title: title,
    actions: actions,
    flexibleSpace: a.flexibleSpace,
    bottom: a.bottom,
    elevation: a.elevation ?? 0,
    scrolledUnderElevation: a.scrolledUnderElevation ?? 0,
    notificationPredicate: a.notificationPredicate,
    shadowColor: a.shadowColor,
    surfaceTintColor: Colors.transparent,
    shape: a.shape,
    backgroundColor: classicAppBarColor,
    foregroundColor: kClassicAppBarForeground,
    iconTheme: const IconThemeData(color: kClassicAppBarForeground),
    actionsIconTheme: const IconThemeData(color: kClassicAppBarForeground),
    primary: a.primary,
    centerTitle: false,
    excludeHeaderSemantics: a.excludeHeaderSemantics,
    titleSpacing: a.titleSpacing ?? 0,
    toolbarOpacity: a.toolbarOpacity,
    bottomOpacity: a.bottomOpacity,
    toolbarHeight: a.toolbarHeight,
    leadingWidth: a.leadingWidth,
    toolbarTextStyle: a.toolbarTextStyle,
    titleTextStyle: const TextStyle(
      color: kClassicAppBarForeground,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    systemOverlayStyle: a.systemOverlayStyle ??
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
    forceMaterialTransparency: false,
    clipBehavior: a.clipBehavior,
  );
}

/// Aggiunge brand CRONOS/GESTOPRO + orologio/calendario a un'AppBar classica.
/// Forza anche il colore barra unico. Idempotente sul titolo; in Gestopro no-op.
PreferredSizeWidget wrapClassicAppBarChrome(
  BuildContext context,
  PreferredSizeWidget appBar,
) {
  // Dentro shell Gestopro o sessione attiva: niente chrome / rail classica.
  if (isGestoproFuturisticUi(context)) return appBar;
  ClassicNavSessionCache.markClassicChrome();
  if (appBar is! AppBar) return appBar;

  final a = appBar;
  if (_titleAlreadyHasClassicChrome(a.title)) {
    return _paintClassicAppBar(context, a, title: a.title!);
  }

  final extracted = _extractTitleText(a.title);
  final Widget newTitle;
  if (extracted != null && extracted.trim().isNotEmpty) {
    newTitle = ResponsiveAppBarTitle(title: extracted);
  } else if (a.title != null) {
    newTitle = ClassicAppBarTitle(child: a.title!);
  } else {
    newTitle = const ClassicAppBarTitle(child: SizedBox.shrink());
  }

  return _paintClassicAppBar(context, a, title: newTitle);
}
