import 'package:flutter/material.dart';

import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/futuristic_admin_nav.dart';
import '../../utils/dipendente_view_navigation.dart';
import '../../utils/dt_view_navigation.dart';
import '../../utils/video_gallery_navigation.dart';
import 'futuristic_footer.dart';
import 'futuristic_nav_section.dart';
import 'futuristic_nav_sub_item.dart';
import 'futuristic_nav_sub_items_scope.dart';
import 'futuristic_shell_scope.dart';
import 'futuristic_sidebar.dart';
import 'futuristic_topbar.dart';
import 'gestopro_click_sound_scope.dart';
import 'gestopro_nav_sub_items_cache.dart';
import 'gestopro_session_cache.dart';
import 'gestopro_session_scope.dart';
import 'particles_background.dart';
import '../../services/classic_nav_session_cache.dart';

/// Layout GESTOPRO con sidebar, top bar (orologio) e footer come la Home.
class FuturisticNavShell extends StatefulWidget {
  const FuturisticNavShell({
    super.key,
    required this.activeSection,
    required this.child,
    this.subItems = const [],
    this.activeSubKey,
    this.onHome,
    this.onDashboard,
    this.onNotifiche,
    this.onAlert,
    this.onImpostazioni,
    this.onSupporto,
  });

  final FuturisticNavSection activeSection;
  final Widget child;
  final List<FuturisticNavSubItem> subItems;
  final String? activeSubKey;
  final VoidCallback? onHome;
  final VoidCallback? onDashboard;
  final VoidCallback? onNotifiche;
  final VoidCallback? onAlert;
  final VoidCallback? onImpostazioni;
  final VoidCallback? onSupporto;

  @override
  State<FuturisticNavShell> createState() => _FuturisticNavShellState();
}

class _FuturisticNavShellState extends State<FuturisticNavShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<FuturisticNavSubItem> _dynamicSubItems = const [];
  String? _dynamicActiveSubKey;

  void _registerSubItems(
    List<FuturisticNavSubItem> items, {
    String? activeSubKey,
  }) {
    if (!mounted) return;
    final sameItems = _sameSubItems(_dynamicSubItems, items);
    if (sameItems && _dynamicActiveSubKey == activeSubKey) return;
    GestoproNavSubItemsCache.update(
      items,
      activeSubKey: activeSubKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stillSame = _sameSubItems(_dynamicSubItems, items) &&
          _dynamicActiveSubKey == activeSubKey;
      if (stillSame) return;
      setState(() {
        _dynamicSubItems = List<FuturisticNavSubItem>.from(items);
        _dynamicActiveSubKey = activeSubKey;
      });
    });
  }

  bool _sameSubItems(
    List<FuturisticNavSubItem> a,
    List<FuturisticNavSubItem> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key ||
          a[i].icon != b[i].icon ||
          a[i].label != b[i].label ||
          a[i].badge != b[i].badge ||
          !_sameSubItems(a[i].children, b[i].children)) {
        return false;
      }
    }
    return true;
  }

  List<FuturisticNavSubItem> get _effectiveSubItems =>
      _dynamicSubItems.isNotEmpty ? _dynamicSubItems : widget.subItems;

  String? get _effectiveActiveSubKey =>
      _dynamicSubItems.isNotEmpty ? _dynamicActiveSubKey : widget.activeSubKey;

  @override
  void initState() {
    super.initState();
    if (widget.subItems.isNotEmpty) {
      GestoproNavSubItemsCache.update(
        widget.subItems,
        activeSubKey: widget.activeSubKey,
      );
    }
  }

  @override
  void didUpdateWidget(covariant FuturisticNavShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subItems != oldWidget.subItems ||
        widget.activeSubKey != oldWidget.activeSubKey) {
      if (widget.subItems.isNotEmpty) {
        _dynamicSubItems = const [];
        _dynamicActiveSubKey = null;
      }
    }
  }

  Widget _buildSidebar(GestoproSessionSnapshot? session) {
    return FuturisticSidebar(
      activeSection: widget.activeSection,
      subItems: _effectiveSubItems,
      activeSubKey: _effectiveActiveSubKey,
      profileFullName: session?.fullName,
      profileUsername: session?.username,
      profileUsersTableId: session?.userId,
      onHome: widget.onHome,
      onDashboard: widget.onDashboard,
      onNotifiche: widget.onNotifiche,
      onAlert: widget.onAlert,
      onImpostazioni: widget.onImpostazioni,
      onSupporto: widget.onSupporto,
      onOpenDtView: session != null && canPreviewDtView(session.role)
          ? () => openDtView(
                context,
                userId: session.userId,
                username: session.username,
                fullName: session.fullName,
                sessionRole: session.role,
              )
          : null,
    );
  }

  Widget? _buildTopBar(GestoproSessionSnapshot? session, {required bool wide}) {
    if (session == null) return null;

    final topBar = FuturisticTopBar(
      userName: session.fullName,
      username: session.username,
      role: session.role.replaceAll('_', ' '),
      usersTableId: session.userId,
      onNotifiche: widget.onNotifiche,
      onVideo: () => VideoGalleryNavigation.open(
            context,
            role: session.role,
          ),
      onOpenDipendente: canPreviewDipendenteView(session.role)
          ? () => openDipendenteView(
                context,
                userId: session.userId,
                username: session.username,
                fullName: session.fullName,
              )
          : null,
      onOpenDtView: canPreviewDtView(session.role)
          ? () => openDtView(
                context,
                userId: session.userId,
                username: session.username,
                fullName: session.fullName,
                sessionRole: session.role,
              )
          : null,
      onSwitchToClassic: () => FuturisticAdminNav.exitGestoproSession(context),
    );

    if (wide) return topBar;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Menu navigazione',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(
            Icons.menu_rounded,
            color: CronosFuturisticTheme.neonCyan,
          ),
        ),
        Expanded(child: topBar),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ClassicNavSessionCache.markGestoproChrome();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final inherited = GestoproSessionScope.maybeOf(context);
    final session = inherited != null
        ? GestoproSessionSnapshot.fromScope(inherited)
        : GestoproSessionCache.current;
    final sidebar = _buildSidebar(session);
    final topBar = _buildTopBar(session, wide: wide);

    return Theme(
      data: CronosFuturisticTheme.themeData(Theme.of(context).textTheme),
      child: GestoproClickSoundScope(
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: CronosFuturisticTheme.voidBg,
          drawer: wide
              ? null
              : Drawer(
                  backgroundColor: CronosFuturisticTheme.voidBg,
                  child: SafeArea(child: sidebar),
                ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ParticlesBackground(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) sidebar,
                  Expanded(
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?topBar,
                          Expanded(
                            child: FuturisticNavSubItemsScope(
                              register: _registerSubItems,
                              child: FuturisticThemedContent(
                                child: widget.child,
                              ),
                            ),
                          ),
                          const FuturisticFooter(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
