import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/admin_vista_guard.dart';
import '../utils/pulizia_dati_dialog.dart';
import '../services/assenza_richieste_pending_service.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/futuristic_admin_nav.dart';
import '../utils/impostazioni_app_dialog.dart';
import '../utils/responsive.dart';
import '../utils/hub_assenze_blink_mixin.dart';

import '../hub/admin_hub_catalog.dart';
import '../hub/admin_hub_nav_item.dart';
import '../hub/app_ui_hub_registry.dart';
import '../hub/dashboard_hub_nav_items.dart';
import '../utils/custom_hub_creator.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../hub/app_ui_custom_hub.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../services/dashboard_ui_mode_prefs.dart';
import '../services/gestopro_mode_prefs.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/classic_nav_sub_items_cache.dart';
import '../widgets/cronos_futuristic_dashboard.dart';
import '../widgets/futuristic/futuristic_nav_section.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/gestopro_nav_sub_items_cache.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';
import '../widgets/cronos_3d_surface.dart';
import '../widgets/cronos_adaptive_hub_grid.dart';
import '../widgets/cronos_freeform_hub_canvas.dart';
import '../widgets/cronos_hold_to_reorder.dart';
import '../widgets/cronos_hub_cross_layout_move.dart';
import '../widgets/cronos_hub_delete_tile_button.dart';
import '../widgets/hub_tile_style_editor.dart';
import '../widgets/hub_tile_corner_resize.dart';
import '../widgets/hub_tile_auto_fit_text.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminDashboardPage extends StatefulWidget {
  final int adminId;
  final String? role;
  final String? username;
  final String? fullName;
  final Set<String>? customAllowedPages;
  /// Da home classica: non forzare GESTOPRO anche se la sessione è attiva.
  final bool forceClassic;

  const AdminDashboardPage({
    super.key,
    required this.adminId,
    this.role,
    this.username,
    this.fullName,
    this.customAllowedPages,
    this.forceClassic = false,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with HubAssenzeBlinkMixin {
  List<_DashItem> _tiles = <_DashItem>[];
  HubLayoutOrders? _hubOrders;
  bool _loadingLayout = true;
  bool _reorderMode = false;
  List<_DashItem> _reorderDraft = <_DashItem>[];
  final Set<String> _pendingHiddenKeys = <String>{};
  Map<String, HubTileStyle> _classicTileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _futuristicTileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraft = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraftBaseline = <String, HubTileStyle>{};
  DashboardUiMode _uiMode = DashboardUiMode.classic;

  String get _dashboardLayoutKey =>
      _uiMode == DashboardUiMode.futuristic
          ? AppUiLayoutService.layoutDashboardAdminFuturistic
          : AppUiLayoutService.layoutDashboardAdmin;

  Map<String, HubTileStyle> get _currentTileStyles =>
      _uiMode == DashboardUiMode.futuristic
          ? _futuristicTileStyles
          : _classicTileStyles;

  @override
  void initState() {
    super.initState();
    initHubAssenzeBlink();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadUiMode();
    if (!mounted) return;
    await _reloadTiles();
  }

  Future<void> _loadUiMode() async {
    if (widget.forceClassic) {
      if (!mounted) return;
      setState(() => _uiMode = DashboardUiMode.classic);
      return;
    }
    final gestopro = await GestoproModePrefs.isActive();
    final mode = gestopro
        ? DashboardUiMode.futuristic
        : await DashboardUiModePrefs.load();
    if (!mounted) return;
    setState(() => _uiMode = mode);
  }

  Future<void> _toggleUiMode() async {
    final next = _uiMode == DashboardUiMode.classic
        ? DashboardUiMode.futuristic
        : DashboardUiMode.classic;
    setState(() => _uiMode = next);
    await DashboardUiModePrefs.save(next);
    if (!mounted) return;
    await _reloadTiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == DashboardUiMode.futuristic
              ? 'Interfaccia futuristica attiva'
              : 'Interfaccia classica ripristinata',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<CronosFuturisticTile> _futuristicTiles(List<_DashItem> items) {
    return items
        .map(
          (item) {
            final style = _activeStyles[item.layoutKey];
            final sub = item.subtitle ?? '';
            final effectiveSub = style?.effectiveSubtitle(sub) ?? sub;
            return CronosFuturisticTile(
              layoutKey: item.layoutKey,
              icon: style?.effectiveIcon(item.icon) ?? item.icon,
              label: style?.effectiveLabel(item.label) ?? item.label,
              subtitle:
                  effectiveSub.trim().isEmpty ? null : effectiveSub,
              accentColor: style?.iconColor ?? item.iconColor,
              tileStyle: style,
              onTap: item.onTap,
            );
          },
        )
        .toList(growable: false);
  }

  String get _roleDisplayLabel {
    final role = normalizeRole(widget.role ?? '');
    if (role.isEmpty) return 'Admin';
    return role.replaceAll('_', ' ');
  }

  @override
  void dispose() {
    disposeHubAssenzeBlink();
    super.dispose();
  }

  @override
  String? get hubAssenzeBlinkRole => widget.role;

  @override
  HubLayoutOrders? get hubAssenzeLayoutOrders => _hubOrders;

  @override
  String get hubAssenzeCurrentLayoutKey =>
      AppUiLayoutService.layoutDashboardAdmin;

  _DashItem _dashItemFromNav(AdminHubNavItem item) {
    return _DashItem(
      layoutKey: item.layoutKey,
      icon: item.icon,
      label: item.label,
      subtitle: item.subtitle,
      iconColor: item.iconColor,
      onTap: () async {
        final page = item.onTap(context);
        if (page is AdminHubActionOnly) return;
        if (!mounted) return;
        await FuturisticNavigation.pushPage(
          context,
          page: page,
          title: item.label,
          activeSubKey: item.layoutKey,
          onAfter: () => refreshHubAssenzeBlink(force: true),
        );
      },
    );
  }

  _DashItem? _buildImpostazioniTile(BuildContext context) {
    final normalizedRole = normalizeRole(widget.role ?? '');
    final isGenerale = isAdminGeneraleLikeRole(normalizedRole);
    final isBuiltInRole = const {
      'admin_generale',
      'admin_vista',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_dpi',
      'admin_formazione',
      'uqsa',
      'caposquadra',
      'dt',
      'assistente_dt',
      'user',
      'dipendente',
      'admin',
    }.contains(normalizedRole);
    bool canForCustom(String pageKey) {
      if (isBuiltInRole) return true;
      return (widget.customAllowedPages ?? const <String>{}).contains(pageKey);
    }
    if (!isGenerale && !canForCustom('anteprima_vista_ruolo')) return null;
    return _DashItem(
      layoutKey: 'impostazioni_app',
      icon: Icons.tune_outlined,
      label: 'Impostazioni App',
      onTap: () {
        showImpostazioniAppDialog(
          context,
          adminId: widget.adminId,
          role: widget.role,
          onPuliziaDati: showPuliziaDatiDialog,
        );
      },
    );
  }

  void _openFuturisticDipendente() {
    openDipendenteView(
      context,
      userId: widget.adminId,
      username: widget.username ?? '',
      fullName: widget.fullName ?? widget.username ?? '',
    );
  }

  void _openFuturisticHome() {
    FuturisticAdminNav.openHome(
      context,
      userId: widget.adminId,
      username: widget.username ?? '',
      fullName: widget.fullName ?? '',
      role: widget.role ?? '',
      customAllowedPages: widget.customAllowedPages,
    );
  }

  void _openFuturisticNotifiche() {
    FuturisticAdminNav.openNotifiche(
      context,
      userId: widget.adminId,
      adminId: widget.adminId,
      role: widget.role,
      username: widget.username,
      fullName: widget.fullName,
      customAllowedPages: widget.customAllowedPages,
    );
  }

  void _openFuturisticAlert() {
    FuturisticAdminNav.openAlert(
      context,
      userId: widget.adminId,
      adminId: widget.adminId,
      role: widget.role,
      username: widget.username,
      fullName: widget.fullName,
      customAllowedPages: widget.customAllowedPages,
    );
  }

  void _openFuturisticImpostazioni() {
    FuturisticAdminNav.openImpostazioni(
      context,
      adminId: widget.adminId,
      role: widget.role,
      userId: widget.adminId,
      username: widget.username,
      fullName: widget.fullName,
      customAllowedPages: widget.customAllowedPages,
      onPuliziaDati: showPuliziaDatiDialog,
    );
  }

  void _openFuturisticSupporto() {
    FuturisticAdminNav.openSupporto(
      context,
      userId: widget.adminId,
      adminId: widget.adminId,
      role: widget.role,
      username: widget.username,
      fullName: widget.fullName,
      customAllowedPages: widget.customAllowedPages,
    );
  }

  Widget _buildGestoproFuturisticDashboard(
    List<_DashItem> displayTiles,
    bool canEditLayout,
    Future<void> Function()? onFuturisticNewPage,
  ) {
    final dashboard = CronosFuturisticDashboard(
      tiles: _futuristicTiles(displayTiles),
      userDisplayName: widget.fullName ?? widget.username ?? '',
      username: widget.username ?? '',
      userId: widget.adminId,
      roleLabel: _roleDisplayLabel,
      onSwitchToClassic: () =>
          FuturisticAdminNav.exitGestoproSession(context),
      onToggleClassicLayout: _toggleUiMode,
      onAdminNewPage: canEditLayout && !_loadingLayout && !_reorderMode
          ? onFuturisticNewPage
          : null,
      onAdminReorder: canEditLayout && !_loadingLayout && !_reorderMode
          ? _enterReorderMode
          : null,
      activeNavSection: FuturisticNavSection.dashboard,
      onOpenHome: _reorderMode ? null : _openFuturisticHome,
      onOpenDashboard: null,
      onOpenNotifiche: _reorderMode ? null : _openFuturisticNotifiche,
      onOpenAlert: _reorderMode ? null : _openFuturisticAlert,
      onOpenImpostazioni: _reorderMode ? null : _openFuturisticImpostazioni,
      onOpenSupport: _reorderMode ? null : _openFuturisticSupporto,
      onOpenDipendente: _reorderMode ? null : _openFuturisticDipendente,
      hubAssenzeBlinkKeys: hubAssenzeBlinkKeys,
      hubAssenzeBlinkOn: hubAssenzeBlinkOn,
      reorderMode: _reorderMode,
      canEditLayout: canEditLayout,
      onCancelReorder: _reorderMode
          ? () => setState(() {
                _reorderMode = false;
                _reorderDraft = <_DashItem>[];
                _styleDraft = <String, HubTileStyle>{};
                _styleDraftBaseline = <String, HubTileStyle>{};
              })
          : null,
      onSaveReorder: _reorderMode ? _saveReorder : null,
      onReorder: _reorderMode
          ? (oldIndex, newIndex) {
              setState(() {
                final next = List<_DashItem>.from(_reorderDraft);
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                _reorderDraft = next;
              });
            }
          : null,
      onDeleteTile: _reorderMode && canEditLayout
          ? (layoutKey) {
              final item = _reorderDraft.firstWhere(
                (t) => t.layoutKey == layoutKey,
              );
              _deleteTile(item);
            }
          : null,
      onEditTileStyle: _reorderMode && canEditLayout
          ? (layoutKey) {
              final item = _reorderDraft.firstWhere(
                (t) => t.layoutKey == layoutKey,
              );
              _editTileStyle(item);
            }
          : null,
      onMoveToLayout: _reorderMode && canEditLayout ? _moveTileToLayout : null,
      onResizeTile: _reorderMode && canEditLayout
          ? (layoutKey, scale) {
              final item = _reorderDraft.firstWhere(
                (t) => t.layoutKey == layoutKey,
              );
              _updateTileScale(item, scale);
            }
          : null,
      onGridCellChanged: _reorderMode && canEditLayout
          ? (layoutKey, col, row, colSpan, rowSpan) {
              final item = _reorderDraft.firstWhere(
                (t) => t.layoutKey == layoutKey,
              );
              _updateTileGrid(item, col, row, colSpan, rowSpan);
            }
          : null,
      dashboardLayoutKey: _dashboardLayoutKey,
    );
    if (!GestoproModePrefs.sessionActive) return dashboard;
    return GestoproSessionScope(
      adminId: widget.adminId,
      userId: widget.adminId,
      username: widget.username ?? '',
      fullName: widget.fullName ?? widget.username ?? '',
      role: widget.role ?? '',
      customAllowedPages: widget.customAllowedPages,
      activeSection: FuturisticNavSection.dashboard,
      child: dashboard,
    );
  }

  Future<void> _reloadTiles({Map<String, HubTileStyle>? priorStyles}) async {
    final customHubs = await AppUiLayoutService.loadCustomHubs();
    if (!mounted) return;
    final catalog = AdminHubCatalog.build(
      context,
      adminId: widget.adminId,
      role: widget.role,
      customAllowedPages: widget.customAllowedPages,
      showUqsaTesserino: isAdminGeneraleLikeRole(normalizeRole(widget.role ?? '')) ||
          (widget.customAllowedPages ?? const <String>{}).contains('tesserini'),
      showUqsaTesserini: isAdminGeneraleLikeRole(normalizeRole(widget.role ?? '')) ||
          (widget.customAllowedPages ?? const <String>{}).contains('tesserini'),
      onPuliziaDati: showPuliziaDatiDialog,
      homeDipendente: HomeDipendenteNavParams(
        userId: widget.adminId,
        username: widget.username ?? '',
        fullName: widget.fullName ?? '',
      ),
      customHubs: customHubs,
    );

    final futuristic = _uiMode == DashboardUiMode.futuristic;
    final ordersFuture = AppUiLayoutService.loadHubOrders(
      defaultKeysByLayout: catalog.defaultKeysByLayout,
      customHubs: customHubs,
      role: widget.role,
      skipLabelSync: true,
    );
    final stylesFuture = futuristic
        ? AppUiLayoutService.loadTileStylesForFuturisticLayout(
            AppUiLayoutService.layoutDashboardAdminFuturistic,
          )
        : AppUiLayoutService.loadTileStylesForLayout(
            AppUiLayoutService.layoutDashboardAdmin,
            role: widget.role,
          );

    final loaded = await Future.wait<Object>([ordersFuture, stylesFuture]);
    if (!mounted) return;

    var orders = loaded[0] as HubLayoutOrders;

    if (futuristic) {
      await AppUiLayoutService.ensureFuturisticDashboardOrderFallback(
        orders: orders,
        defaultKeysByLayout: catalog.defaultKeysByLayout,
        role: widget.role,
      );
    }

    final ordersLoaded = orders;

    Map<String, HubTileStyle> classicStyles = priorStyles != null &&
            !futuristic
        ? priorStyles
        : _classicTileStyles;
    Map<String, HubTileStyle> futuristicStyles = priorStyles != null &&
            futuristic
        ? priorStyles
        : _futuristicTileStyles;

    try {
      final styleMap = loaded[1] as Map<String, HubTileStyle>;
      if (futuristic) {
        futuristicStyles = priorStyles != null
            ? AppUiLayoutService.mergeLoadedTileStylesWithPrior(
                loaded: styleMap,
                prior: priorStyles,
              )
            : styleMap;
      } else {
        classicStyles = priorStyles != null
            ? AppUiLayoutService.mergeLoadedTileStylesWithPrior(
                loaded: styleMap,
                prior: priorStyles,
              )
            : styleMap;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            futuristic
                ? 'Stili pulsanti futuristici non caricati: $e. '
                    'Verifica la migration app_ui_futuristic_tile_styles.'
                : 'Stili pulsanti classici non caricati: $e. '
                    'Verifica la migration app_ui_tile_styles.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
        ),
      );
    }

    final catalogTiles = catalog.itemsByKey.map(
      (key, nav) => MapEntry(key, _dashItemFromNav(nav)),
    );
    var tiles = AppUiLayoutService.itemsForHub(
      catalog: catalogTiles,
      hubKeyOrder: ordersLoaded.keysFor(_dashboardLayoutKey),
    );
    if (futuristic && tiles.isEmpty) {
      final fallbackKeys =
          ordersLoaded.keysFor(_dashboardLayoutKey).isNotEmpty
              ? ordersLoaded.keysFor(_dashboardLayoutKey)
              : (catalog.defaultKeysByLayout[_dashboardLayoutKey] ??
                  catalog.defaultKeysByLayout[
                      AppUiLayoutService.layoutDashboardAdmin] ??
                  const <String>[]);
      if (fallbackKeys.isNotEmpty) {
        ordersLoaded.setKeysFor(_dashboardLayoutKey, List<String>.from(fallbackKeys));
        tiles = AppUiLayoutService.itemsForHub(
          catalog: catalogTiles,
          hubKeyOrder: fallbackKeys,
        );
      }
    }
    if (!mounted) return;
    final impostazioni = _buildImpostazioniTile(context);
    if (impostazioni != null &&
        ordersLoaded.keysFor(_dashboardLayoutKey).contains('impostazioni_app') &&
        !tiles.any((t) => t.layoutKey == 'impostazioni_app')) {
      final idx = ordersLoaded
          .keysFor(_dashboardLayoutKey)
          .indexOf('impostazioni_app');
      if (idx >= 0 && idx <= tiles.length) {
        tiles.insert(idx, impostazioni);
      } else {
        tiles.add(impostazioni);
      }
    }
    if (!mounted) return;
    setState(() {
      _hubOrders = ordersLoaded;
      _tiles = tiles;
      _classicTileStyles = classicStyles;
      _futuristicTileStyles = futuristicStyles;
      _loadingLayout = false;
      _reorderMode = false;
      _reorderDraft = <_DashItem>[];
      _styleDraft = <String, HubTileStyle>{};
      _styleDraftBaseline = <String, HubTileStyle>{};
    });
    if (!GestoproModePrefs.sessionActive ||
        _uiMode != DashboardUiMode.futuristic) {
      final u = widget.username;
      final f = widget.fullName;
      final r = widget.role;
      if (u != null && f != null && r != null) {
        ClassicNavSessionCache.update(
          userId: widget.adminId,
          username: u,
          fullName: f,
          role: r,
        );
      } else {
        ClassicNavSessionCache.markClassicChrome();
      }
      ClassicNavSessionCache.setActiveSection(ClassicNavSection.dashboard);
    }
    _syncGestoproSidebarCache(tiles);
    unawaited(refreshHubAssenzeBlink(force: true));
    unawaited(
      AppUiLayoutService.refreshHubLabelsFromTileStyles().catchError((_) {}),
    );
  }

  Map<String, HubTileStyle> get _activeStyles =>
      _reorderMode ? _styleDraft : _currentTileStyles;

  void _syncGestoproSidebarCache(List<_DashItem> tiles) {
    final items = tiles
        .map(
          (item) => FuturisticNavSubItem(
            key: item.layoutKey,
            icon: item.icon,
            label: item.label,
            accentColor: item.iconColor,
            onTap: item.onTap,
          ),
        )
        .toList(growable: false);
    GestoproNavSubItemsCache.update(items, activeSubKey: null);
    ClassicNavSubItemsCache.updateDashboard(items, activeSubKey: null);
  }

  Future<void> _editTileStyle(_DashItem item) async {
    final current = _activeStyles[item.layoutKey];
    final result = await showHubTileStyleEditor(
      context: context,
      itemKey: item.layoutKey,
      defaultLabel: item.label,
      defaultSubtitle: item.subtitle ?? '',
      defaultIcon: item.icon,
      initial: current,
      futuristicMode: _uiMode == DashboardUiMode.futuristic,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.hasOverrides) {
        if (_reorderMode) {
          _styleDraft[item.layoutKey] = result;
        } else if (_uiMode == DashboardUiMode.futuristic) {
          _futuristicTileStyles[item.layoutKey] = result;
        } else {
          _classicTileStyles[item.layoutKey] = result;
        }
      } else if (_reorderMode) {
        _styleDraft[item.layoutKey] = const HubTileStyle();
      } else if (_uiMode == DashboardUiMode.futuristic) {
        _futuristicTileStyles.remove(item.layoutKey);
      } else {
        _classicTileStyles.remove(item.layoutKey);
      }
    });
    if (!_reorderMode) {
      if (_uiMode == DashboardUiMode.futuristic) {
        await AppUiLayoutService.saveTileStyleForFuturisticLayout(
          layoutKey: AppUiLayoutService.layoutDashboardAdminFuturistic,
          itemKey: item.layoutKey,
          style: result,
        );
      } else {
        await AppUiLayoutService.saveTileStyleForLayout(
          layoutKey: AppUiLayoutService.layoutDashboardAdmin,
          itemKey: item.layoutKey,
          style: result,
        );
      }
    }
  }

  void _updateTileScale(_DashItem item, double sizeScale) {
    final base = _activeStyles[item.layoutKey] ?? const HubTileStyle();
    final spans = HubTileGridConfig.spansForScale(sizeScale);
    final updated = base.copyWith(
      sizeScale: sizeScale,
      gridColSpan: spans.$1,
      gridRowSpan: spans.$2,
    );
    setState(() {
      if (updated.hasOverrides) {
        if (_reorderMode) {
          _styleDraft[item.layoutKey] = updated;
        } else {
          _currentTileStyles[item.layoutKey] = updated;
        }
      } else if (_reorderMode) {
        _styleDraft[item.layoutKey] = const HubTileStyle();
      } else {
        _currentTileStyles.remove(item.layoutKey);
      }
    });
  }

  void _updateTileGrid(
    _DashItem item,
    int col,
    int row,
    int colSpan,
    int rowSpan,
  ) {
    final base = _activeStyles[item.layoutKey] ?? const HubTileStyle();
    final updated = base.copyWith(
      gridCol: col,
      gridRow: row,
      gridColSpan: colSpan,
      gridRowSpan: rowSpan,
    );
    setState(() {
      if (_reorderMode) {
        _styleDraft[item.layoutKey] = updated;
      } else {
        _currentTileStyles[item.layoutKey] = updated;
      }
    });
  }

  void _moveTileToLayout(String itemKey, String targetLayoutKey) {
    if (kHubNonRelocatableKeys.contains(itemKey) || _hubOrders == null) return;
    final targetLabel = AppUiHubRegistry.labelFor(targetLayoutKey);
    final movedMatches =
        _reorderDraft.where((t) => t.layoutKey == itemKey).toList();
    final movedLabel = movedMatches.isEmpty ? null : movedMatches.first.label;
    setState(() {
      _hubOrders = AppUiLayoutService.moveItemToLayout(
        orders: _hubOrders!,
        itemKey: itemKey,
        targetLayoutKey: targetLayoutKey,
      );
      _reorderDraft.removeWhere((t) => t.layoutKey == itemKey);
      _hubOrders!.setKeysFor(
        _dashboardLayoutKey,
        _reorderDraft.map((t) => t.layoutKey).toList(growable: false),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${movedLabel ?? itemKey} spostato in $targetLabel. '
          'Premi «Salva per tutti» per confermare.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _enterReorderMode() {
    final keys = _tiles.map((t) => t.layoutKey).toList(growable: false);
    final seededDraft = AppUiLayoutService.seedStyleDraftForReorder(
      keysInOrder: keys,
      tileStyles: _currentTileStyles,
    );
    setState(() {
      _reorderMode = true;
      _reorderDraft = List<_DashItem>.from(_tiles);
      _styleDraftBaseline = Map<String, HubTileStyle>.from(_currentTileStyles);
      _styleDraft = seededDraft;
    });
  }

  Future<void> _deleteTile(_DashItem item) async {
    if (_hubOrders == null) return;
    final dash = _dashboardLayoutKey;
    final duplicateCount =
        _reorderDraft.where((t) => t.layoutKey == item.layoutKey).length;
    final existsElsewhere = AppUiLayoutService.itemExistsOnOtherLayouts(
      _hubOrders!,
      dash,
      item.layoutKey,
    );
    final scope = AppUiCustomHub.isLauncherKey(item.layoutKey)
        ? HubTileDeleteScope.customPage
        : AppUiCustomHub.isCustomSlotKey(item.layoutKey)
            ? HubTileDeleteScope.customSlot
            : existsElsewhere
                ? HubTileDeleteScope.currentPageOnly
                : duplicateCount > 1
                    ? HubTileDeleteScope.oneDuplicateOnPage
                    : HubTileDeleteScope.global;
    final confirmed = await confirmDeleteHubTile(
      context,
      label: item.label,
      itemKey: item.layoutKey,
      scope: scope,
    );
    if (!confirmed || !mounted) return;

    try {
      if (scope == HubTileDeleteScope.oneDuplicateOnPage) {
        setState(() {
          final idx =
              _reorderDraft.indexWhere((t) => t.layoutKey == item.layoutKey);
          if (idx >= 0) _reorderDraft.removeAt(idx);
          _hubOrders = AppUiLayoutService.removeOneFromLayout(
            _hubOrders!,
            dash,
            item.layoutKey,
          );
        });
      } else if (scope == HubTileDeleteScope.currentPageOnly) {
        setState(() {
          _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
          _hubOrders = AppUiLayoutService.removeAllFromLayout(
            _hubOrders!,
            dash,
            item.layoutKey,
          );
        });
      } else if (scope == HubTileDeleteScope.customPage) {
        final layoutKey = item.layoutKey.replaceFirst('open_', '');
        await AppUiLayoutService.deleteCustomHub(layoutKey);
        if (!mounted) return;
        setState(() {
          _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
          _hubOrders =
              AppUiLayoutService.removeItemEverywhere(_hubOrders!, item.layoutKey);
        });
      } else if (scope == HubTileDeleteScope.customSlot) {
        await AppUiLayoutService.deleteCustomHubSlot(item.layoutKey);
        if (!mounted) return;
        setState(() {
          _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
          _hubOrders =
              AppUiLayoutService.removeItemEverywhere(_hubOrders!, item.layoutKey);
        });
      } else {
        _pendingHiddenKeys.add(item.layoutKey);
        setState(() {
          _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
          _hubOrders =
              AppUiLayoutService.removeItemEverywhere(_hubOrders!, item.layoutKey);
        });
      }
      if (!mounted) return;
      final snack = switch (scope) {
        HubTileDeleteScope.oneDuplicateOnPage =>
          'Copia di «${item.label}» rimossa. Premi «Salva per tutti».',
        HubTileDeleteScope.currentPageOnly =>
          '«${item.label}» rimosso da questa pagina. Premi «Salva per tutti».',
        _ => '«${item.label}» rimosso. Premi «Salva per tutti» per confermare.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snack),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore eliminazione: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveReorder() async {
    if (!await ensureCanPersist(context, widget.role)) return;
    if (_hubOrders == null) return;
    final clearedStyleKeys = _styleDraftBaseline.keys
        .where((k) => !_styleDraft.containsKey(k))
        .toSet();
    final clearedGridKeys = _styleDraftBaseline.entries
        .where((e) => e.value.hasGridPlacement)
        .where((e) => !(_styleDraft[e.key]?.hasGridPlacement ?? false))
        .map((e) => e.key)
        .toSet();
    final stylesToPersist = AppUiLayoutService.stylesToPersist(
      draft: _styleDraft,
      clearedKeys: clearedStyleKeys,
    );
    final layoutKey = _dashboardLayoutKey;
    final isFuturistic = _uiMode == DashboardUiMode.futuristic;
    final mergedStyles = AppUiLayoutService.applyStyleDraft(
      saved: _currentTileStyles,
      draft: _styleDraft,
      removedKeys: clearedStyleKeys,
    );
    var tilesForOrder = _reorderDraft;
    if (mergedStyles.values.any((s) => s.hasCustomPosition)) {
      tilesForOrder = hubSortItemsByPosition(
        tilesForOrder,
        mergedStyles,
        (t) => t.layoutKey,
      );
    }
    final keys = tilesForOrder
        .map((t) => t.layoutKey)
        .toList(growable: false);
    final gridFromDraft = AppUiLayoutService.gridPlacementsFromDraft(
      draft: _styleDraft,
      clearedKeys: {...clearedStyleKeys, ...clearedGridKeys},
    );
    final gridToPersist = AppUiLayoutService.mergeGridPlacementsForPersist(
      keysInOrder: keys,
      styles: mergedStyles,
      fromDraft: gridFromDraft,
      clearedKeys: {...clearedStyleKeys, ...clearedGridKeys},
    );
    _hubOrders!.setKeysFor(layoutKey, keys);
    try {
      for (final key in _pendingHiddenKeys) {
        await AppUiLayoutService.hideItemKey(key);
      }
      _pendingHiddenKeys.clear();
      final customHubs =
          await AppUiLayoutService.loadCustomHubsWithSyncedLabels();
      await AppUiLayoutService.saveHubOrders(
        _hubOrders!,
        customHubs: customHubs,
      );
      if (isFuturistic) {
        await AppUiLayoutService.saveFuturisticTileStyles(stylesToPersist);
      } else {
        await AppUiLayoutService.saveTileStyles(stylesToPersist);
      }
      await AppUiLayoutService.saveTileGridPlacements(
        layoutKey: layoutKey,
        placements: gridToPersist,
      );
      if (!mounted) return;
      final stylesWithGrid = Map<String, HubTileStyle>.from(mergedStyles);
      for (final entry in gridToPersist.entries) {
        final base = stylesWithGrid[entry.key] ?? const HubTileStyle();
        stylesWithGrid[entry.key] = base.copyWith(
          gridCol: entry.value.gridCol,
          gridRow: entry.value.gridRow,
          gridColSpan: entry.value.gridColSpan,
          gridRowSpan: entry.value.gridRowSpan,
          sizeScale: entry.value.sizeScale,
        );
      }
      setState(() {
        if (isFuturistic) {
          _futuristicTileStyles = stylesWithGrid;
        } else {
          _classicTileStyles = stylesWithGrid;
        }
        _tiles = tilesForOrder;
        _reorderMode = false;
        _reorderDraft = <_DashItem>[];
        _styleDraft = <String, HubTileStyle>{};
        _styleDraftBaseline = <String, HubTileStyle>{};
      });
      await _reloadTiles(priorStyles: stylesWithGrid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFuturistic
                ? 'Layout futurista salvato per tutti gli utenti.'
                : 'Ordine, posizioni e colori dashboard salvati per tutti gli utenti.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Errore salvataggio: ${AppUiLayoutService.formatPersistError(e)}',
          ),
          duration: const Duration(seconds: 6),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildDesktopDashGrid({
    required List<_DashItem> displayTiles,
    required bool canEditLayout,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cross = w >= 1200
            ? 6
            : (w >= 900 ? 4 : (w >= 600 ? 3 : 2));
        final useFreeform = hubShouldUseFreeformLayout(
          isMobileLayout: false,
          width: w,
          reorderMode: _reorderMode,
          canEditLayout: canEditLayout,
          layoutKeys: displayTiles.map((t) => t.layoutKey),
          activeStyles: _activeStyles,
        );

        Widget buildDashTile(int index) => _DashTile(
              key: ValueKey<String>(displayTiles[index].layoutKey),
              item: displayTiles[index],
              tileStyle: _activeStyles[displayTiles[index].layoutKey],
              reorderMode: _reorderMode,
              fillCell: true,
              canEditLayout: canEditLayout,
              onHoldReorder: _enterReorderMode,
              onMoveToLayout: _moveTileToLayout,
              onDeleteTile: _deleteTile,
              onEditTileStyle: canEditLayout ? _editTileStyle : null,
              onResizeTileStyle: canEditLayout ? _updateTileScale : null,
              hubAssenzeBlinkKeys: hubAssenzeBlinkKeys,
              hubAssenzeBlinkOn: hubAssenzeBlinkOn,
            );

        if (useFreeform) {
          return CronosFreeformHubCanvas(
            itemCount: displayTiles.length,
            crossAxisCount: cross,
            childAspectRatio: HubTileGridConfig.cellAspectRatio,
            maxCanvasHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null,
            reorderMode: _reorderMode,
            layoutKeyForIndex: (index) => displayTiles[index].layoutKey,
            styleForKey: (key) => _activeStyles[key],
            scaleForIndex: (index) =>
                _activeStyles[displayTiles[index].layoutKey]?.sizeScale ?? 1.0,
            onGridCellChanged: canEditLayout
                ? (key, col, row, colSpan, rowSpan) {
                    final tile = displayTiles.firstWhere(
                      (t) => t.layoutKey == key,
                    );
                    _updateTileGrid(tile, col, row, colSpan, rowSpan);
                  }
                : null,
            itemBuilder: (context, index) => buildDashTile(index),
          );
        }

        return CronosAdaptiveHubGrid(
          crossAxisCount: cross,
          childAspectRatio: HubTileGridConfig.cellAspectRatio,
          itemCount: displayTiles.length,
          reorderMode: _reorderMode,
          onReorder: _reorderMode
              ? (oldIndex, newIndex) {
                  setState(() {
                    final next = List<_DashItem>.from(_reorderDraft);
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);
                    _reorderDraft = next;
                  });
                }
              : null,
          scaleForIndex: (index) =>
              _activeStyles[displayTiles[index].layoutKey]?.sizeScale ?? 1.0,
          itemBuilder: (context, index) => buildDashTile(index),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout = useMobileUi(context);
    final normalizedRole = normalizeRole(widget.role ?? '');
    final canEditLayout = AppUiLayoutService.canEditGlobalLayout(normalizedRole);

    final tiles = _reorderMode ? _reorderDraft : _tiles;
    final displayTiles = _loadingLayout ? <_DashItem>[] : tiles;

    final futuristic = _uiMode == DashboardUiMode.futuristic;

    Future<void> onFuturisticNewPage() async {
      await promptCreateCustomHubPage(
        context,
        userId: widget.adminId,
        role: widget.role,
        originLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
        asSubfolder: true,
      );
      if (mounted) await _reloadTiles();
    }

    return Scaffold(
      backgroundColor: futuristic ? const Color(0xFF04080F) : null,
      appBar: futuristic
          ? null
          : wrapClassicAppBarChrome(context, AppBar(
        title: isMobileLayout
            ? Row(
                children: [
                  AppLogo(size: isTabletDevice(context) ? 36 : 28),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Admin — Dashboard',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogo(size: 44),
                  SizedBox(width: 8),
                  Text('Admin — Dashboard'),
                ],
              ),
        actions: [
          if (canEditLayout && !_reorderMode && !_loadingLayout)
            IconButton(
              tooltip: 'Nuova cartella',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () async {
                await promptCreateCustomHubPage(
                  context,
                  userId: widget.adminId,
                  role: widget.role,
                  originLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
                  asSubfolder: true,
                );
                if (mounted) await _reloadTiles();
              },
            ),
          if (canEditLayout && !_reorderMode && !_loadingLayout)
            IconButton(
              tooltip: 'Riordina pulsanti (3 sec. su un tile)',
              icon: const Icon(Icons.reorder),
              onPressed: _enterReorderMode,
            ),
          if (_reorderMode) ...[
            TextButton(
              onPressed: () => setState(() {
                _reorderMode = false;
                _reorderDraft = <_DashItem>[];
                _styleDraft = <String, HubTileStyle>{};
                _styleDraftBaseline = <String, HubTileStyle>{};
              }),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: _saveReorder,
              child: const Text('Salva per tutti'),
            ),
          ],
        ],
      )),
      body: _loadingLayout
          ? const Center(child: CircularProgressIndicator())
          : futuristic
              ? _buildGestoproFuturisticDashboard(
                  displayTiles,
                  canEditLayout,
                  onFuturisticNewPage,
                )
              : Column(
              children: [
                if (_reorderMode)
                  Material(
                    color: Colors.amber.shade100,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Griglia ${HubTileGridConfig.sizeLabel}: trascina ≡ sulla cella. '
                        'Tile grandi = più celle. '
                        'Angoli ridimensiona; ✕ elimina; ⇄ o ⋮ cambia pagina; palette colori/nome. '
                        'Poi «Salva per tutti».',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                if (_reorderMode && canEditLayout)
                  CronosHubCrossLayoutDropBar(
                    currentLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
                    onAcceptItemKey: _moveTileToLayout,
                  ),
                Expanded(
                  child: isMobileLayout
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const PageTopLogo(size: 72),
                                Expanded(
                                  child: _AdminDashboardMobileBody(
                                    tiles: displayTiles,
                                    reorderMode: _reorderMode,
                                    canEditLayout: canEditLayout,
                                    tileStyles: _activeStyles,
                                    onHoldReorder: _enterReorderMode,
                                    onMoveToLayout: _moveTileToLayout,
                                    onDeleteTile: _deleteTile,
                                    onEditTileStyle:
                                        canEditLayout ? _editTileStyle : null,
                                    hubAssenzeBlinkKeys: hubAssenzeBlinkKeys,
                                    hubAssenzeBlinkOn: hubAssenzeBlinkOn,
                                    onReorder: (oldIndex, newIndex) {
                                      setState(() {
                                        final next =
                                            List<_DashItem>.from(_reorderDraft);
                                        if (newIndex > oldIndex) newIndex--;
                                        final item = next.removeAt(oldIndex);
                                        next.insert(newIndex, item);
                                        _reorderDraft = next;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            )
                          : PageWithTopLogo(
                              showLogo: true,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final useFreeform =
                                      hubShouldUseFreeformLayout(
                                    isMobileLayout: false,
                                    width: constraints.maxWidth,
                                    reorderMode: _reorderMode,
                                    canEditLayout: canEditLayout,
                                    layoutKeys:
                                        displayTiles.map((t) => t.layoutKey),
                                    activeStyles: _activeStyles,
                                  );
                                  if (useFreeform) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        4,
                                        8,
                                        8,
                                      ),
                                      child: _buildDesktopDashGrid(
                                        displayTiles: displayTiles,
                                        canEditLayout: canEditLayout,
                                      ),
                                    );
                                  }
                                  return SingleChildScrollView(
                                    padding: cronosPagePadding(context),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                        maxWidth: cronosContentMaxWidth(context),
                                      ),
                                      child: _buildDesktopDashGrid(
                                        displayTiles: displayTiles,
                                        canEditLayout: canEditLayout,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
    );
  }
}

class _DashItem {
  final String layoutKey;
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  _DashItem({
    required this.layoutKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
  });
}

class _AdminDashboardMobileBody extends StatelessWidget {
  final List<_DashItem> tiles;
  final bool reorderMode;
  final bool canEditLayout;
  final Map<String, HubTileStyle> tileStyles;
  final VoidCallback onHoldReorder;
  final void Function(String itemKey, String targetLayoutKey) onMoveToLayout;
  final void Function(_DashItem item) onDeleteTile;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(_DashItem item)? onEditTileStyle;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;

  const _AdminDashboardMobileBody({
    required this.tiles,
    required this.reorderMode,
    required this.canEditLayout,
    required this.tileStyles,
    required this.onHoldReorder,
    required this.onMoveToLayout,
    required this.onDeleteTile,
    required this.onReorder,
    this.onEditTileStyle,
    this.hubAssenzeBlinkKeys = const <String>{},
    this.hubAssenzeBlinkOn = true,
  });

  Widget _buildTile(BuildContext context, _DashItem item, {bool dragging = false}) {
    final theme = Theme.of(context);
    final style = tileStyles[item.layoutKey];
    final metrics = HubTileStyleMetrics.fromStyle(style: style, fillCell: false);
    final label = style?.effectiveLabel(item.label) ?? item.label;
    final iconColor = AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: item.layoutKey,
      blinkKeys: hubAssenzeBlinkKeys,
      blinkOn: hubAssenzeBlinkOn,
      fallback: style?.iconColor ?? item.iconColor ?? theme.colorScheme.primary,
    );
    final textColor = style?.textColor ?? theme.colorScheme.onSurface;
    final canMove = reorderMode &&
        canEditLayout &&
        !kHubNonRelocatableKeys.contains(item.layoutKey);
    final canDelete = reorderMode && canEditLayout;
    final canStyle = reorderMode && canEditLayout && onEditTileStyle != null;
    final card = Cronos3dSurface(
      color: style?.backgroundColor,
      onTap: reorderMode ? null : item.onTap,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14 * (style?.sizeScale ?? 1.0),
          vertical: 8 * (style?.sizeScale ?? 1.0),
        ),
        leading: Icon(
          reorderMode ? Icons.drag_indicator : item.icon,
          color: iconColor,
          size: 24 * (style?.sizeScale ?? 1.0),
        ),
        title: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: metrics.titleSize,
            color: textColor,
          ),
        ),
        trailing: (canMove || canDelete || canStyle)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canStyle)
                    CronosHubTileStyleButton(
                      onPressed: () => onEditTileStyle!(item),
                    ),
                  if (canDelete)
                    CronosHubDeleteTileButton(
                      onPressed: () => onDeleteTile(item),
                    ),
                  if (canMove) ...[
                    CronosHubCrossLayoutDragHandle(
                      itemKey: item.layoutKey,
                      label: label,
                    ),
                    CronosHubMoveToLayoutButton(
                      currentLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
                      itemKey: item.layoutKey,
                      onMoveTo: (target) =>
                          onMoveToLayout(item.layoutKey, target),
                    ),
                  ],
                ],
              )
            : (reorderMode ? null : const Icon(Icons.chevron_right)),
        onTap: reorderMode ? null : item.onTap,
      ),
    );
    return CronosJiggleMode(active: reorderMode, child: card);
  }

  @override
  Widget build(BuildContext context) {
    if (reorderMode) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        buildDefaultDragHandles: false,
        itemCount: tiles.length,
        // ignore: deprecated_member_use
        onReorder: onReorder,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final item = tiles[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>(item.layoutKey),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildTile(context, item, dragging: false),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: tiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = tiles[index];
        final tile = _buildTile(context, item);
        if (!canEditLayout) return tile;
        return CronosHoldToReorderDetector(
          enabled: true,
          onHoldComplete: onHoldReorder,
          child: tile,
        );
      },
    );
  }
}

class _DashTile extends StatelessWidget {
  final _DashItem item;
  final HubTileStyle? tileStyle;
  final bool reorderMode;
  final bool fillCell;
  final bool canEditLayout;
  final VoidCallback onHoldReorder;
  final void Function(String itemKey, String targetLayoutKey)? onMoveToLayout;
  final void Function(_DashItem item)? onDeleteTile;
  final void Function(_DashItem item)? onEditTileStyle;
  final void Function(_DashItem item, double sizeScale)? onResizeTileStyle;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;

  const _DashTile({
    super.key,
    required this.item,
    this.tileStyle,
    this.reorderMode = false,
    this.fillCell = false,
    required this.canEditLayout,
    required this.onHoldReorder,
    this.onMoveToLayout,
    this.onDeleteTile,
    this.onEditTileStyle,
    this.onResizeTileStyle,
    this.hubAssenzeBlinkKeys = const <String>{},
    this.hubAssenzeBlinkOn = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (fillCell) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cellScale = HubTileStyleMetrics.cellScaleFromConstraints(
            constraints,
          );
          return _buildTileBody(context, theme, cellScale: cellScale);
        },
      );
    }
    return _buildTileBody(context, theme);
  }

  Widget _buildTileBody(
    BuildContext context,
    ThemeData theme, {
    double cellScale = 1.0,
  }) {
    final metrics = HubTileStyleMetrics.fromStyle(
      style: tileStyle,
      fillCell: fillCell,
      cellScale: cellScale,
    );
    final label = tileStyle?.effectiveLabel(item.label) ?? item.label;
    final iconColor = AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: item.layoutKey,
      blinkKeys: hubAssenzeBlinkKeys,
      blinkOn: hubAssenzeBlinkOn,
      fallback:
          tileStyle?.iconColor ?? item.iconColor ?? theme.colorScheme.primary,
    );
    final textColor = tileStyle?.textColor ?? theme.colorScheme.onSurface;
    final inFreeformLayout = HubGridDragScope.maybeOf(context) != null;
    final canMove = reorderMode &&
        canEditLayout &&
        onMoveToLayout != null &&
        !kHubNonRelocatableKeys.contains(item.layoutKey);
    final canDelete = reorderMode && canEditLayout && onDeleteTile != null;
    final canStyle =
        reorderMode && canEditLayout && onEditTileStyle != null;
    // Nella griglia fine il ridimensionamento è per celle (maniglie del tile),
    // non con la scala proporzionale: indipendente per larghezza e altezza.
    final canResize = reorderMode &&
        canEditLayout &&
        fillCell &&
        !inFreeformLayout &&
        onResizeTileStyle != null;
    final scale = tileStyle?.sizeScale ?? 1.0;
    final displayIcon = reorderMode
        ? Icons.drag_indicator
        : (tileStyle?.effectiveIcon(item.icon) ?? item.icon);
    final card = Cronos3dSurface(
      color: tileStyle?.backgroundColor,
      child: InkWell(
        onTap: reorderMode ? null : item.onTap,
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.paddingH,
            vertical: metrics.paddingV,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: fillCell ? MainAxisSize.max : MainAxisSize.min,
            children: [
              wrapFreeformDragIcon(
                context: context,
                icon: Icon(
                  displayIcon,
                  size: metrics.iconSize,
                  color: iconColor,
                ),
              ),
              SizedBox(height: metrics.gapIconTitle),
              if (fillCell)
                Expanded(
                  child: Center(
                    child: HubTileAutoFitText(
                      text: label,
                      maxLines: 3,
                      minFontSize: 6,
                      maxFontSize: metrics.titleSize.clamp(8.0, 44.0),
                      style: metrics
                          .resolveTitleStyle(
                            (theme.textTheme.titleMedium ??
                                    const TextStyle())
                                .copyWith(height: 1.15),
                            textColor,
                          )
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: metrics.resolveTitleStyle(
                    theme.textTheme.titleMedium ?? const TextStyle(),
                    textColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    Widget body = HubTileScaledShell(
      fillCell: fillCell,
      child: card,
    );
    Widget sized = fillCell ? SizedBox.expand(child: body) : body;
    if (canResize) {
      sized = HubTileCornerResizeOverlay(
        enabled: true,
        sizeScale: scale,
        onScaleChanged: (v) => onResizeTileStyle!(item, v),
        child: sized,
      );
    }
    if (canMove || canDelete || canStyle) {
      final styleBtn = canStyle
          ? CronosHubTileStyleButton(
              onPressed: () => onEditTileStyle!(item),
            )
          : null;
      final moveBtn = canMove
          ? Material(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: CronosHubMoveToLayoutButton(
                currentLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
                itemKey: item.layoutKey,
                onMoveTo: (target) => onMoveToLayout!(item.layoutKey, target),
              ),
            )
          : null;
      final crossBtn = canMove
          ? CronosHubCrossLayoutDragHandle(
              itemKey: item.layoutKey,
              label: label,
            )
          : null;
      final deleteBtn = canDelete
          ? CronosHubDeleteTileButton(
              onPressed: () => onDeleteTile!(item),
            )
          : null;

      if (inFreeformLayout && fillCell) {
        sized = HubTileFreeformChromeLayout(
          tileBody: sized,
          topLeft: styleBtn,
          topRight: moveBtn,
          bottomLeft: crossBtn,
          bottomRight: deleteBtn,
        );
      } else {
        sized = Stack(
          clipBehavior: Clip.none,
          children: [
            sized,
            if (styleBtn != null)
              Positioned(
                top: HubTileControlInsets.top,
                left: HubTileControlInsets.side,
                child: styleBtn,
              ),
            if (moveBtn != null) ...[
              Positioned(
                top: HubTileControlInsets.top,
                right: HubTileControlInsets.side,
                child: moveBtn,
              ),
              Positioned(
                bottom: HubTileControlInsets.bottom,
                left: HubTileControlInsets.corner,
                child: crossBtn!,
              ),
            ],
            if (deleteBtn != null)
              Positioned(
                bottom: HubTileControlInsets.bottom,
                right: HubTileControlInsets.corner,
                child: deleteBtn,
              ),
          ],
        );
      }
    }
    final result = CronosJiggleMode(active: reorderMode, child: sized);
    if (reorderMode || !canEditLayout) return result;
    return CronosHoldToReorderDetector(
      enabled: true,
      onHoldComplete: onHoldReorder,
      child: result,
    );
  }
}
