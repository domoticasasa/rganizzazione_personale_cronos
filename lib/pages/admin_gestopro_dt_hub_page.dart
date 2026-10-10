import 'dart:async';

import 'package:flutter/material.dart';

import '../hub/admin_hub_nav_item.dart';
import '../hub/app_ui_hub_registry.dart';
import '../hub/dt_home_hub_nav_items.dart';
import '../hub/dashboard_hub_nav_items.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../services/app_ui_layout_service.dart';
import '../services/bacheca_service.dart';
import '../utils/dt_view_navigation.dart';
import '../utils/dt_view_role.dart';
import '../utils/futuristic_admin_nav.dart';
import '../utils/gestopro_navigation.dart';
import '../widgets/cronos_futuristic_dashboard.dart';
import '../widgets/cronos_freeform_hub_canvas.dart';
import '../widgets/cronos_hub_delete_tile_button.dart';
import '../widgets/futuristic/futuristic_nav_section.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/gestopro_nav_sub_items_cache.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';
import '../widgets/hub_tile_style_editor.dart';

/// Hub Vista DT in GESTOPRO (anteprima admin o home DT reale).
class AdminGestoproDtHubPage extends StatefulWidget {
  const AdminGestoproDtHubPage({
    super.key,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.sessionRole,
    this.sessionSecondaryRole,
    this.customAllowedPages,
  });

  final int userId;
  final String username;
  final String fullName;
  final String sessionRole;
  final String? sessionSecondaryRole;
  final Set<String>? customAllowedPages;

  @override
  State<AdminGestoproDtHubPage> createState() => _AdminGestoproDtHubPageState();
}

class _AdminGestoproDtHubPageState extends State<AdminGestoproDtHubPage> {
  static const _layoutKey = AppUiLayoutService.layoutHomeDtFuturistic;

  List<AdminHubNavItem> _tiles = <AdminHubNavItem>[];
  HubLayoutOrders? _hubOrders;
  bool _loadingLayout = true;
  bool _reorderMode = false;
  List<AdminHubNavItem> _reorderDraft = <AdminHubNavItem>[];
  final Set<String> _pendingHiddenKeys = <String>{};
  Map<String, HubTileStyle> _tileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraft = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraftBaseline = <String, HubTileStyle>{};
  bool _hasBachecaUnread = false;
  bool _bachecaBlinkOn = true;
  Timer? _bachecaBlinkTimer;

  String get _effectiveRole => dtPreviewEffectiveRole(
        sessionPrimaryRole: widget.sessionRole,
        sessionSecondaryRole: widget.sessionSecondaryRole,
      );

  bool get _isAdminPreview => canPreviewDtView(widget.sessionRole);

  String get _roleLabel => _isAdminPreview
      ? 'Vista DT'
      : widget.sessionRole.replaceAll('_', ' ');

  FuturisticNavSection get _navSection =>
      _isAdminPreview ? FuturisticNavSection.vistaDt : FuturisticNavSection.home;

  bool get _canEditLayout =>
      _isAdminPreview &&
      AppUiLayoutService.canEditGlobalLayout(widget.sessionRole);

  Map<String, HubTileStyle> get _activeStyles =>
      _reorderMode ? _styleDraft : _tileStyles;

  @override
  void initState() {
    super.initState();
    _bachecaBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted || !_hasBachecaUnread) return;
      setState(() => _bachecaBlinkOn = !_bachecaBlinkOn);
    });
    unawaited(_reloadTiles());
    unawaited(_loadBachecaUnreadAlert());
  }

  @override
  void dispose() {
    _bachecaBlinkTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBachecaUnreadAlert() async {
    try {
      final has = await BachecaService.hasUnread();
      if (!mounted) return;
      setState(() => _hasBachecaUnread = has);
    } catch (_) {}
  }

  List<AdminHubNavItem> _navItems() {
    return buildDtHomeHubNavItems(
      context,
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
      role: _effectiveRole,
      secondaryRole: widget.sessionSecondaryRole,
    );
  }

  Future<void> _reloadTiles({Map<String, HubTileStyle>? priorStyles}) async {
    final navItems = _navItems();
    final defaultKeys =
        navItems.map((i) => i.layoutKey).toList(growable: false);
    final itemsByKey = <String, AdminHubNavItem>{
      for (final item in navItems) item.layoutKey: item,
    };

    final orders = await AppUiLayoutService.loadHubOrders(
      defaultKeysByLayout: <String, List<String>>{
        _layoutKey: defaultKeys,
      },
      customHubs: const [],
      role: widget.sessionRole,
      skipLabelSync: true,
    );

    Map<String, HubTileStyle> styles = priorStyles ?? _tileStyles;
    try {
      final loaded =
          await AppUiLayoutService.loadTileStylesForFuturisticLayout(_layoutKey);
      styles = priorStyles != null
          ? AppUiLayoutService.mergeLoadedTileStylesWithPrior(
              loaded: loaded,
              prior: priorStyles,
            )
          : loaded;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stili GESTOPRO Vista DT non caricati: $e. '
            'Verifica la migration app_ui_futuristic_tile_styles.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
        ),
      );
    }

    if (!mounted) return;
    final hubKeys = AppUiLayoutService.resolveDtHomeOrderKeys(
      orders.keysFor(_layoutKey),
      defaultKeys,
    );
    setState(() {
      _hubOrders = orders;
      _tiles = AppUiLayoutService.itemsForHub(
        catalog: itemsByKey,
        hubKeyOrder: hubKeys,
      );
      _tileStyles = styles;
      _loadingLayout = false;
      _reorderMode = false;
      _reorderDraft = <AdminHubNavItem>[];
      _styleDraft = <String, HubTileStyle>{};
      _styleDraftBaseline = <String, HubTileStyle>{};
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSidebar(_tiles);
    });
  }

  void _syncSidebar(List<AdminHubNavItem> tiles) {
    GestoproNavSubItemsCache.update(
      tiles
          .map(
            (item) => FuturisticNavSubItem(
              key: item.layoutKey,
              icon: item.icon,
              label: item.label,
              accentColor: item.iconColor,
              onTap: () => _openItem(item),
            ),
          )
          .toList(growable: false),
      activeSubKey: null,
    );
  }

  void _openItem(AdminHubNavItem item) {
    final page = item.onTap(context);
    openGestoproPage(
      context,
      title: item.label,
      page: DtViewRoleScope(
        effectiveRole: _effectiveRole,
        sessionPrimaryRole: widget.sessionRole,
        sessionSecondaryRole: widget.sessionSecondaryRole,
        child: page,
      ),
    ).then((_) {
      if (item.layoutKey == 'bacheca') {
        unawaited(_loadBachecaUnreadAlert());
      }
    });
  }

  List<CronosFuturisticTile> _futuristicTiles() {
    final source = _reorderMode ? _reorderDraft : _tiles;
    return source
        .map((item) {
          final style = _activeStyles[item.layoutKey];
          final sub = item.subtitle ?? '';
          final effectiveSub = style?.effectiveSubtitle(sub) ?? sub;
          final bachecaAlert =
              item.layoutKey == 'bacheca' && _hasBachecaUnread && _bachecaBlinkOn;
          return CronosFuturisticTile(
            layoutKey: item.layoutKey,
            icon: style?.effectiveIcon(item.icon) ?? item.icon,
            label: style?.effectiveLabel(item.label) ?? item.label,
            subtitle: effectiveSub.trim().isEmpty ? null : effectiveSub,
            accentColor: bachecaAlert
                ? Colors.red
                : (style?.iconColor ?? item.iconColor),
            tileStyle: style,
            onTap: () => _openItem(item),
          );
        })
        .toList(growable: false);
  }

  void _enterReorderMode() {
    final keys = _tiles.map((t) => t.layoutKey).toList(growable: false);
    final seededDraft = AppUiLayoutService.seedStyleDraftForReorder(
      keysInOrder: keys,
      tileStyles: _tileStyles,
    );
    setState(() {
      _reorderMode = true;
      _reorderDraft = List<AdminHubNavItem>.from(_tiles);
      _styleDraftBaseline = Map<String, HubTileStyle>.from(_tileStyles);
      _styleDraft = seededDraft;
    });
  }

  Future<void> _editTileStyle(AdminHubNavItem item) async {
    final current = _activeStyles[item.layoutKey];
    final result = await showHubTileStyleEditor(
      context: context,
      itemKey: item.layoutKey,
      defaultLabel: item.label,
      defaultSubtitle: item.subtitle ?? '',
      defaultIcon: item.icon,
      initial: current,
      futuristicMode: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.hasOverrides) {
        if (_reorderMode) {
          _styleDraft[item.layoutKey] = result;
        } else {
          _tileStyles[item.layoutKey] = result;
        }
      } else if (_reorderMode) {
        _styleDraft[item.layoutKey] = const HubTileStyle();
      } else {
        _tileStyles.remove(item.layoutKey);
      }
    });
    if (!_reorderMode) {
      await AppUiLayoutService.saveTileStyleForFuturisticLayout(
        layoutKey: _layoutKey,
        itemKey: item.layoutKey,
        style: result,
      );
    }
  }

  void _updateTileScale(AdminHubNavItem item, double sizeScale) {
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
          _tileStyles[item.layoutKey] = updated;
        }
      } else if (_reorderMode) {
        _styleDraft[item.layoutKey] = const HubTileStyle();
      } else {
        _tileStyles.remove(item.layoutKey);
      }
    });
  }

  void _updateTileGrid(
    AdminHubNavItem item,
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
        _tileStyles[item.layoutKey] = updated;
      }
    });
  }

  void _moveTileToLayout(String itemKey, String targetLayoutKey) {
    if (kHubNonRelocatableKeys.contains(itemKey) || _hubOrders == null) return;
    final targetLabel = AppUiHubRegistry.labelFor(targetLayoutKey);
    final moved = _reorderDraft.where((t) => t.layoutKey == itemKey).toList();
    final movedLabel = moved.isEmpty ? null : moved.first.label;
    setState(() {
      _hubOrders = AppUiLayoutService.moveItemToLayout(
        orders: _hubOrders!,
        itemKey: itemKey,
        targetLayoutKey: targetLayoutKey,
      );
      _reorderDraft.removeWhere((t) => t.layoutKey == itemKey);
      _hubOrders!.setKeysFor(
        _layoutKey,
        _reorderDraft.map((t) => t.layoutKey).toList(growable: false),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${movedLabel ?? itemKey} spostato in $targetLabel. '
          'Premi «Salva per tutti».',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteTile(AdminHubNavItem item) async {
    if (_hubOrders == null) return;
    final duplicateCount =
        _reorderDraft.where((t) => t.layoutKey == item.layoutKey).length;
    final existsElsewhere = AppUiLayoutService.itemExistsOnOtherLayouts(
      _hubOrders!,
      _layoutKey,
      item.layoutKey,
    );
    final scope = existsElsewhere
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

    if (scope == HubTileDeleteScope.oneDuplicateOnPage) {
      setState(() {
        final idx =
            _reorderDraft.indexWhere((t) => t.layoutKey == item.layoutKey);
        if (idx >= 0) _reorderDraft.removeAt(idx);
        _hubOrders = AppUiLayoutService.removeOneFromLayout(
          _hubOrders!,
          _layoutKey,
          item.layoutKey,
        );
      });
    } else if (scope == HubTileDeleteScope.currentPageOnly) {
      setState(() {
        _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
        _hubOrders = AppUiLayoutService.removeAllFromLayout(
          _hubOrders!,
          _layoutKey,
          item.layoutKey,
        );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '«${item.label}» rimosso. Premi «Salva per tutti» per confermare.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _saveReorder() async {
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
    final mergedStyles = AppUiLayoutService.applyStyleDraft(
      saved: _tileStyles,
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
    final keys =
        tilesForOrder.map((t) => t.layoutKey).toList(growable: false);
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
    _hubOrders!.setKeysFor(_layoutKey, keys);
    try {
      for (final key in _pendingHiddenKeys) {
        await AppUiLayoutService.hideItemKey(key);
      }
      _pendingHiddenKeys.clear();
      await AppUiLayoutService.saveHubOrders(
        _hubOrders!,
        customHubs: const [],
      );
      await AppUiLayoutService.saveFuturisticTileStyles(stylesToPersist);
      await AppUiLayoutService.saveTileGridPlacements(
        layoutKey: _layoutKey,
        placements: gridToPersist,
      );
      if (!mounted) return;
      await _reloadTiles(priorStyles: mergedStyles);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Layout GESTOPRO Vista DT salvato per tutti i DT.',
          ),
          duration: const Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) {
    if (_loadingLayout) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DtViewRoleScope(
      effectiveRole: _effectiveRole,
      sessionPrimaryRole: widget.sessionRole,
      sessionSecondaryRole: widget.sessionSecondaryRole,
      child: GestoproSessionScope(
        adminId: widget.userId,
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
        role: widget.sessionRole,
        customAllowedPages: widget.customAllowedPages,
        gestoproDtHome: true,
        secondaryRole: widget.sessionSecondaryRole,
        activeSection: _navSection,
        child: CronosFuturisticDashboard(
          tiles: _futuristicTiles(),
          userDisplayName: widget.fullName,
          username: widget.username,
          userId: widget.userId,
          roleLabel: _roleLabel,
          activeNavSection: _navSection,
          dashboardLayoutKey: _layoutKey,
          useLocalNavSubItemsOnly: true,
          onSwitchToClassic: _isAdminPreview
              ? () => _exitAdminDtPreview(context)
              : () => exitDtGestoproSession(
                    context,
                    userId: widget.userId,
                    username: widget.username,
                    fullName: widget.fullName,
                    role: widget.sessionRole,
                    secondaryRole: widget.sessionSecondaryRole,
                  ),
          switchToClassicTooltip: _isAdminPreview
              ? 'Esci dalla Vista DT'
              : 'Esci da GESTOPRO — torna alla home classica',
          onAdminReorder:
              _canEditLayout && !_reorderMode ? _enterReorderMode : null,
          canEditLayout: _canEditLayout,
          reorderMode: _reorderMode,
          onCancelReorder: _reorderMode
              ? () => setState(() {
                    _reorderMode = false;
                    _reorderDraft = <AdminHubNavItem>[];
                    _styleDraft = <String, HubTileStyle>{};
                    _styleDraftBaseline = <String, HubTileStyle>{};
                  })
              : null,
          onSaveReorder: _reorderMode ? _saveReorder : null,
          onReorder: _reorderMode
              ? (oldIndex, newIndex) {
                  setState(() {
                    final next = List<AdminHubNavItem>.from(_reorderDraft);
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);
                    _reorderDraft = next;
                  });
                }
              : null,
          onDeleteTile: _reorderMode && _canEditLayout
              ? (layoutKey) {
                  final item = _reorderDraft.firstWhere(
                    (t) => t.layoutKey == layoutKey,
                  );
                  unawaited(_deleteTile(item));
                }
              : null,
          onEditTileStyle: _reorderMode && _canEditLayout
              ? (layoutKey) {
                  final item = _reorderDraft.firstWhere(
                    (t) => t.layoutKey == layoutKey,
                  );
                  unawaited(_editTileStyle(item));
                }
              : null,
          onMoveToLayout: _reorderMode && _canEditLayout
              ? _moveTileToLayout
              : null,
          onResizeTile: _reorderMode && _canEditLayout
              ? (layoutKey, scale) {
                  final item = _reorderDraft.firstWhere(
                    (t) => t.layoutKey == layoutKey,
                  );
                  _updateTileScale(item, scale);
                }
              : null,
          onGridCellChanged: _reorderMode && _canEditLayout
              ? (layoutKey, col, row, colSpan, rowSpan) {
                  final item = _reorderDraft.firstWhere(
                    (t) => t.layoutKey == layoutKey,
                  );
                  _updateTileGrid(item, col, row, colSpan, rowSpan);
                }
              : null,
          onOpenHome: _isAdminPreview
              ? () => _exitAdminDtPreview(context)
              : null,
          onOpenDashboard: null,
          onOpenNotifiche: () => FuturisticAdminNav.openNotifiche(
            context,
            userId: widget.userId,
            adminId: widget.userId,
            role: widget.sessionRole,
            username: widget.username,
            fullName: widget.fullName,
            customAllowedPages: widget.customAllowedPages,
          ),
          onOpenAlert: () => FuturisticAdminNav.openAlert(
            context,
            userId: widget.userId,
            adminId: widget.userId,
            role: widget.sessionRole,
            username: widget.username,
            fullName: widget.fullName,
            customAllowedPages: widget.customAllowedPages,
          ),
          onOpenDtView: _isAdminPreview
              ? () => _exitAdminDtPreview(context)
              : null,
          onOpenImpostazioni: null,
          onOpenSupport: () => FuturisticAdminNav.openSupporto(
            context,
            userId: widget.userId,
            adminId: widget.userId,
            role: widget.sessionRole,
            username: widget.username,
            fullName: widget.fullName,
            customAllowedPages: widget.customAllowedPages,
          ),
        ),
      ),
    );
  }

  /// Torna all'hub admin GESTOPRO (o pop se possibile).
  void _exitAdminDtPreview(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    unawaited(
      FuturisticAdminNav.openHome(
        context,
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
        role: widget.sessionRole,
        customAllowedPages: widget.customAllowedPages,
      ),
    );
  }
}
