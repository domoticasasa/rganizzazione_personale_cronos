import 'dart:async';

import 'package:flutter/material.dart';

import '../Mobile/aereo_mobile.dart';
import '../Mobile/prenotazione_pernottamenti_mobile.dart';
import '../Mobile/treno_mobile.dart';
import '../hub/home_admin_button_keys.dart';
import '../services/app_ui_layout_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/dt_view_navigation.dart';
import 'aereo_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_gestopro_hub_page.dart';
import 'home/home_hub_page_base.dart';
import 'prenotazione_pernottamenti_page.dart';
import 'treno_page.dart';

/// Home dedicata agli admin (Pernottamenti, Treni, Aerei, Dashboard).
class AdminHomePage extends HomeHubPage {
  const AdminHomePage({
    super.key,
    required super.username,
    required super.fullName,
    required super.role,
    required super.userId,
    super.secondaryRole,
  }) : super(
          layoutConfig: const HomeHubLayoutConfig(
            layoutKey: HomeAdminButtonKeys.layoutKey,
            defaultOrderKeys: HomeAdminButtonKeys.defaults,
            useCompactHomeGrid: true,
            isAdminHomeGrid: true,
            isDtHomeGrid: false,
            compactMaxWidth: 1100,
          ),
        );

  @override
  HomeHubPageState createState() => _AdminHomePageState();
}

class _AdminHomePageState extends HomeHubPageState {
  bool _openingGestopro = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeGestoproIfActive();
    });
  }

  Future<void> _resumeGestoproIfActive() async {
    if (!await GestoproModePrefs.isActive()) return;
    if (!mounted) return;
    ClassicNavSessionCache.markGestoproChrome();
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminGestoproHubPage(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
          role: widget.role,
          customAllowedPages: customAllowedPages,
          secondaryRole: widget.secondaryRole,
        ),
      ),
    );
  }

  @override
  bool get showDtViewButton => canPreviewDtView(widget.role);

  @override
  bool get canEditHomeLayout => AppUiLayoutService.canEditGlobalLayout(widget.role);

  @override
  bool get usesPersonalHomeLayout => false;

  Future<void> _openGestopro() async {
    if (_openingGestopro) return;
    _openingGestopro = true;
    try {
      // Flag subito: la persistenza non deve ritardare il primo tap.
      GestoproModePrefs.sessionActive = true;
      ClassicNavSessionCache.markGestoproChrome();
      final nav = Navigator.of(context);
      final page = AdminGestoproHubPage(
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
        role: widget.role,
        customAllowedPages: customAllowedPages,
        secondaryRole: widget.secondaryRole,
      );
      unawaited(GestoproModePrefs.activate());
      await nav.pushReplacement(
        MaterialPageRoute(builder: (_) => page),
      );
    } finally {
      _openingGestopro = false;
    }
  }

  @override
  bool get showUiViewModeSwitch => !widget.isLayoutPreviewMode;

  @override
  VoidCallback? get onOpenGestoproFromBar => _openGestopro;

  @override
  Widget? buildAdminHomeFooter(BuildContext context) => null;

  @override
  List<HomeHubTile> buildRoleTiles(ThemeData theme) {
    final tiles = <HomeHubTile>[
      if (canShowPage('pernottamenti', true))
        navTile(
          layoutKey: 'pernottamenti',
          icon: Icons.bed_outlined,
          label: 'Pernottamenti',
          color: theme.colorScheme.primary,
          mobilePage: PernottamentiMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: PrenotazionePernottamentiPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
      if (canShowPage('treni', true))
        navTile(
          layoutKey: 'treni',
          icon: Icons.train_outlined,
          label: 'Treni',
          color: theme.colorScheme.primary,
          mobilePage: TrenoMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: TrenoPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
      if (canShowPage('aerei', true))
        navTile(
          layoutKey: 'aerei',
          icon: Icons.flight_takeoff_outlined,
          label: 'Aerei',
          color: theme.colorScheme.primary,
          mobilePage: AereoMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: AereoPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
    ];

    if (canShowPage('admin_dashboard', isAdmin)) {
      tiles.add(
        HomeHubTile(
          layoutKey: 'admin_dashboard',
          icon: Icons.dashboard_outlined,
          label: 'Admin Dashboard',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboardPage(
                adminId: widget.userId,
                role: widget.role,
                username: widget.username,
                fullName: widget.fullName,
                customAllowedPages: customAllowedPages,
                forceClassic: true,
              ),
            ),
          ),
        ),
      );
    }

    return tiles;
  }
}
