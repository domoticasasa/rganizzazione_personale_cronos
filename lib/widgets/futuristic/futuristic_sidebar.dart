import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/app_branding_service.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/app_copyright.dart';
import '../../utils/gestopro_tap_sound.dart';
import '../app_logo.dart';
import '../user_profile_avatar.dart';
import 'futuristic_nav_section.dart';
import 'futuristic_nav_sub_item.dart';
import 'gestopro_session_scope.dart';
import 'glowing_border_shell.dart';
import '../nav_tree_lines.dart';

/// Sidebar GESTOPRO con sotto-voci a cascata sotto la sezione attiva.
class FuturisticSidebar extends StatelessWidget {
  const FuturisticSidebar({
    super.key,
    this.activeSection = FuturisticNavSection.dashboard,
    this.subItems = const [],
    this.activeSubKey,
    this.profileFullName,
    this.profileUsername,
    this.profileUsersTableId,
    this.onHome,
    this.onDashboard,
    this.onNotifiche,
    this.onAlert,
    this.onImpostazioni,
    this.onSupporto,
    this.onOpenDtView,
  });

  final FuturisticNavSection activeSection;
  final List<FuturisticNavSubItem> subItems;
  final String? activeSubKey;
  final String? profileFullName;
  final String? profileUsername;
  final int? profileUsersTableId;
  final VoidCallback? onHome;
  final VoidCallback? onDashboard;
  final VoidCallback? onNotifiche;
  final VoidCallback? onAlert;
  final VoidCallback? onImpostazioni;
  final VoidCallback? onSupporto;
  final VoidCallback? onOpenDtView;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final branding = AppBrandingService.instance;
        final side = branding.sidebarColor;
        final accent = branding.chromeAccentColor;
        final glow = Color.lerp(
              accent,
              CronosFuturisticTheme.borderGlow,
              0.35,
            ) ??
            CronosFuturisticTheme.borderGlow;
        // Se sidebar è chiara (classica), scurisci per GESTOPRO.
        final sideIsLight = side.computeLuminance() > 0.45;
        final sideBase = sideIsLight
            ? Color.lerp(side, CronosFuturisticTheme.voidBg, 0.82)!
            : side;
        return GlowingBorderShell(
          color: glow,
          strokeWidth: 2,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 248,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      sideBase.withValues(alpha: 0.72),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'NAVIGAZIONE',
                        style: CronosFonts.orbitron(
                          fontSize: 8,
                          letterSpacing: 3,
                          color: accent.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.hardEdge,
                        children: [
                          if (_showNavItem(
                            FuturisticNavSection.home,
                            onHome,
                          ))
                            _buildMainBlock(
                              section: FuturisticNavSection.home,
                              icon: Icons.home_outlined,
                              label: 'Home',
                              onTap: onHome,
                            ),
                          if (_showNavItem(
                            FuturisticNavSection.dashboard,
                            onDashboard,
                          ))
                            _buildMainBlock(
                              section: FuturisticNavSection.dashboard,
                              icon: Icons.dashboard_rounded,
                              label: 'Dashboard',
                              onTap: onDashboard,
                            ),
                          if (_showNavItem(
                            FuturisticNavSection.notifiche,
                            onNotifiche,
                          ))
                            _buildMainBlock(
                              section: FuturisticNavSection.notifiche,
                              icon: Icons.notifications_outlined,
                              label: 'Notifiche',
                              onTap: onNotifiche,
                            ),
                          if (_showNavItem(
                            FuturisticNavSection.alert,
                            onAlert,
                          ))
                            _buildMainBlock(
                              section: FuturisticNavSection.alert,
                              icon: Icons.warning_amber_rounded,
                              label: 'Alert',
                              accent: CronosFuturisticTheme.neonRed,
                              onTap: onAlert,
                            ),
                          if (_showNavItem(
                            FuturisticNavSection.impostazioni,
                            onImpostazioni,
                          ))
                            _buildMainBlock(
                              section: FuturisticNavSection.impostazioni,
                              icon: Icons.settings_outlined,
                              label: 'Impostazioni',
                              onTap: onImpostazioni,
                            ),
                          if (onSupporto != null)
                            _SideItem(
                              Icons.person_outline_rounded,
                              'Profilo',
                              active:
                                  activeSection == FuturisticNavSection.supporto,
                              onTap: wrapGestoproTap(onSupporto),
                              leading: _buildProfileLeading(context),
                            ),
                          if (onOpenDtView != null ||
                              activeSection == FuturisticNavSection.vistaDt)
                            _SideItem(
                              Icons.assignment_ind_outlined,
                              activeSection == FuturisticNavSection.vistaDt &&
                                      onOpenDtView != null
                                  ? 'Torna ad Admin'
                                  : 'Vista DT',
                              active:
                                  activeSection == FuturisticNavSection.vistaDt,
                              onTap: activeSection ==
                                      FuturisticNavSection.vistaDt
                                  ? (onOpenDtView != null
                                      ? wrapGestoproTap(onOpenDtView)
                                      : () {})
                                  : wrapGestoproTap(onOpenDtView),
                            ),
                        ],
                      ),
                    ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        accent.withValues(alpha: 0.45),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: CronosWordmark(
                    height: 34,
                    textColor: Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${branding.productName} v2.5',
                  style: CronosFonts.orbitron(
                    color: accent.withValues(alpha: 0.45),
                    fontSize: 9,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                const AppCopyrightFooter(lightOnDark: true, compact: true),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  bool _showNavItem(FuturisticNavSection section, VoidCallback? onTap) =>
      onTap != null || activeSection == section;

  Widget _buildProfileLeading(BuildContext context) {
    final scope = GestoproSessionScope.maybeOf(context);
    final fullName = (profileFullName ?? scope?.fullName ?? '').trim();
    final username = (profileUsername ?? scope?.username ?? '').trim();
    final usersId = profileUsersTableId ?? scope?.userId;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.45),
        ),
      ),
      child: SessionUserAvatar(
        radius: 9,
        displayName: fullName,
        username: username,
        usersTableId: usersId,
      ),
    );
  }

  Widget _buildMainBlock({
    required FuturisticNavSection section,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? accent,
  }) {
    final active = activeSection == section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SideItem(
          icon,
          label,
          active: active,
          onTap: wrapGestoproTap(onTap),
          accent: accent,
        ),
        if (active && subItems.isNotEmpty)
          _SubNavTree(
            items: subItems,
            activeSubKey: activeSubKey,
          ),
      ],
    );
  }
}

class _SubNavTree extends StatelessWidget {
  const _SubNavTree({
    required this.items,
    this.activeSubKey,
    this.depth = 0,
  });

  final List<FuturisticNavSubItem> items;
  final String? activeSubKey;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final line = Colors.white.withValues(alpha: 0.28);
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
            _SubNavBranch(
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

class _SubNavBranch extends StatelessWidget {
  const _SubNavBranch({
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
    final active = item.key == activeSubKey;
    final expanded = _containsActive(item) && item.children.isNotEmpty;
    return NavTreeBranch(
      lineColor: lineColor,
      isLast: isLast,
      item: _SubSideItem(
        item: item,
        active: active,
        depth: depth,
        expanded: expanded,
        isLast: isLast && item.children.isEmpty,
      ),
      childTree: expanded
          ? _SubNavTree(
              items: item.children,
              activeSubKey: activeSubKey,
              depth: depth + 1,
            )
          : null,
    );
  }
}

class _SubSideItem extends StatelessWidget {
  const _SubSideItem({
    required this.item,
    required this.active,
    required this.depth,
    required this.expanded,
    required this.isLast,
  });

  final FuturisticNavSubItem item;
  final bool active;
  final int depth;
  final bool expanded;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final accent = item.accentColor ?? CronosFuturisticTheme.neonCyan;
    final fg = active ? accent : Colors.white.withValues(alpha: 0.72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: wrapGestoproTap(item.onTap),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? CronosFuturisticTheme.electricBright.withValues(alpha: 0.12)
                : null,
            border: active
                ? Border.all(
                    color: accent.withValues(alpha: 0.35),
                  )
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
                  style: CronosFonts.exo2(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
              if (item.children.isNotEmpty)
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 15,
                  color: fg.withValues(alpha: 0.75),
                ),
              if (item.badge != null && item.badge!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: CronosFuturisticTheme.electricBright
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.badge!,
                    style: CronosFonts.exo2(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
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

class _SideItem extends StatelessWidget {
  const _SideItem(
    this.icon,
    this.label, {
    this.active = false,
    this.onTap,
    this.accent,
    this.leading,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color? accent;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final idleColor = accent ?? Colors.white60;
    final c = active ? CronosFuturisticTheme.neonCyan : idleColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: active
            ? LinearGradient(
                colors: [
                  CronosFuturisticTheme.electricBlue.withValues(alpha: 0.35),
                  CronosFuturisticTheme.electricBright.withValues(alpha: 0.08),
                ],
              )
            : null,
        border: active
            ? Border.all(
                color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.35),
              )
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: CronosFuturisticTheme.electricBright.withValues(
                    alpha: 0.2,
                  ),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: ListTile(
        dense: true,
        minTileHeight: 44,
        visualDensity: VisualDensity.compact,
        enabled: onTap != null,
        onTap: onTap,
        leading: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: leading ?? Icon(icon, color: c, size: 18),
          ),
        ),
        title: Text(
          label,
          style: CronosFonts.exo2(
            color: c,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: active
            ? Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CronosFuturisticTheme.neonCyan,
                  boxShadow: [
                    BoxShadow(
                      color: CronosFuturisticTheme.neonCyan,
                      blurRadius: 8,
                    ),
                  ],
                ),
              )
            : (onTap != null
                ? Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.25),
                  )
                : null),
      ),
    );
  }
}
