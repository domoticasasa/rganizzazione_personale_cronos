import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../hub/admin_hub_catalog.dart';
import '../hub/admin_hub_nav_item.dart';
import '../hub/carburante_hub_nav_items.dart';
import '../hub/app_ui_hub_registry.dart';
import '../hub/dashboard_hub_nav_items.dart';
import '../hub/pos_liste_hub_nav_items.dart';
import '../utils/custom_hub_creator.dart';
import '../utils/hub_assenze_blink_mixin.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../services/app_ui_layout_service.dart';
import '../services/assenza_richieste_pending_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/classic_nav_sub_items_cache.dart';
import '../services/notification_bell.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/dt_view_role.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/gestopro_sidebar_nav_tree.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import '../utils/video_gallery_navigation.dart';
import '../widgets/app_logo.dart';
import '../hub/app_ui_custom_hub.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../widgets/cronos_3d_surface.dart';
import '../widgets/cronos_adaptive_hub_grid.dart';
import '../widgets/cronos_freeform_hub_canvas.dart';
import '../widgets/cronos_hold_to_reorder.dart';
import '../widgets/cronos_hub_cross_layout_move.dart';
import '../widgets/cronos_hub_delete_tile_button.dart';
import '../widgets/hub_tile_auto_fit_text.dart';
import '../widgets/hub_tile_style_editor.dart';
import '../widgets/premium_glass_hub.dart';
import '../services/gestopro_mode_prefs.dart';
import '../services/gestopro_click_sound_service.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../widgets/futuristic/neon_card.dart';
import '../widgets/futuristic/futuristic_hub_chip.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/futuristic_nav_sub_items_scope.dart';
import '../widgets/futuristic/gestopro_nav_sub_items_cache.dart';
import '../widgets/futuristic/gestopro_session_cache.dart';
import '../widgets/hub_tile_corner_resize.dart';
import '../widgets/mobile_open_container.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Hub admin con riordino locale e spostamento verso altri hub.
class AdminReorderableHubPage extends StatefulWidget {
  const AdminReorderableHubPage({
    super.key,
    required this.layoutKey,
    required this.title,
    this.userId,
    this.role,
    this.customAllowedPages,
    this.showUqsaTesserino = false,
    this.showUqsaTesserini = false,
    this.onPuliziaDati,
    this.maxCellWidth = 168,
    this.desktopAspectRatio = HubTileGridConfig.cellAspectRatio,
    this.mobileAspectRatio = 2.4,
    this.savedSnackMessage,
    this.embedded = false,
    this.homeDipendente,
    this.tapOverrides,
    this.showCreatePageButton = true,
    this.onRenameSections,
    this.gridScale = 1.0,
  });

  final String layoutKey;
  final String title;
  final int? userId;
  final String? role;
  final Set<String>? customAllowedPages;
  final bool showUqsaTesserino;
  final bool showUqsaTesserini;
  final ImpostazioniPuliziaCallback? onPuliziaDati;
  final double maxCellWidth;
  final double desktopAspectRatio;
  final double mobileAspectRatio;
  final String? savedSnackMessage;
  final bool embedded;
  final HomeDipendenteNavParams? homeDipendente;
  final Map<String, void Function(BuildContext context)>? tapOverrides;
  final bool showCreatePageButton;
  final VoidCallback? onRenameSections;
  final double gridScale;

  @override
  State<AdminReorderableHubPage> createState() => _AdminReorderableHubPageState();
}

class _AdminReorderableHubPageState extends State<AdminReorderableHubPage>
    with HubAssenzeBlinkMixin {
  List<AdminHubNavItem> _tiles = <AdminHubNavItem>[];
  HubLayoutOrders? _hubOrders;
  bool _loadingLayout = true;
  bool _reorderMode = false;
  List<AdminHubNavItem> _reorderDraft = <AdminHubNavItem>[];
  final Set<String> _pendingHiddenKeys = <String>{};
  Map<String, HubTileStyle> _tileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraft = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraftBaseline = <String, HubTileStyle>{};

  bool get _isCarburanteHub =>
      widget.layoutKey == AppUiLayoutService.layoutCarburanteHub ||
      widget.layoutKey == AppUiLayoutService.legacyCarburanteHubLayoutKey;

  String get _effectiveHubLayoutKey => _isCarburanteHub
      ? AppUiLayoutService.layoutCarburanteHub
      : widget.layoutKey;

  @override
  void initState() {
    super.initState();
    initHubAssenzeBlink();
    if (_isCarburanteHub) {
      final cachedOrder = AppUiLayoutService.cachedCarburanteHubOrderKeys();
      if (cachedOrder != null && cachedOrder.isNotEmpty) {
        final catalog = <String, AdminHubNavItem>{
          for (final item in buildCarburanteHubNavItems(role: widget.role)) item.layoutKey: item,
        };
        final preview = _filterHubTilesByRole(
          AppUiLayoutService.itemsForHub(
            catalog: catalog,
            hubKeyOrder: cachedOrder,
          ),
          widget.role,
        );
        if (preview.isNotEmpty) {
          _tiles = preview;
          _loadingLayout = false;
        }
      }
    }
    _reloadTiles();
  }

  @override
  void dispose() {
    disposeHubAssenzeBlink();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSidebarSubNav());
  }

  void _syncSidebarSubNav() {
    if (widget.embedded) return;
    if (_loadingLayout) return;

    final tiles = _reorderMode ? _reorderDraft : _tiles;
    final currentItems = tiles
        .map(
          (item) => FuturisticNavSubItem(
            key: item.layoutKey,
            icon: item.icon,
            label: item.label,
            accentColor: item.iconColor,
            onTap: () {
              if (GestoproModePrefs.sessionActive) {
                unawaited(GestoproClickSoundService.play());
              }
              _openHubItem(context, item);
            },
          ),
        )
        .toList(growable: false);

    final gestopro = isGestoproFuturisticUi(context);
    final scope = FuturisticNavSubItemsScope.maybeOf(context);
    if (gestopro && scope == null) return;

    final snapshot = GestoproSessionCache.resolve(context);
    final parentKey = snapshot?.activeSubKey ??
        hubLauncherKeyForLayout(widget.layoutKey) ??
        ClassicNavSubItemsCache.activeKey;

    var root = gestopro
        ? GestoproNavSubItemsCache.items
        : ClassicNavSubItemsCache.dashboardItems;
    if (root.isEmpty) {
      root = GestoproNavSubItemsCache.items;
    }
    if (root.isEmpty) {
      root = snapshot?.subItems ?? const <FuturisticNavSubItem>[];
    }

    late final List<FuturisticNavSubItem> resolvedItems;
    late final String? resolvedActiveKey;

    if (parentKey != null &&
        root.isNotEmpty &&
        containsNavKeyRecursive(root, parentKey)) {
      resolvedItems =
          attachNavChildrenRecursive(root, parentKey, currentItems);
      resolvedActiveKey = parentKey;
    } else if (parentKey != null &&
        root.isNotEmpty &&
        widget.layoutKey != AppUiLayoutService.layoutDashboardAdmin &&
        widget.layoutKey != AppUiLayoutService.layoutDashboardAdminFuturistic) {
      final launcher = hubLauncherKeyForLayout(widget.layoutKey);
      if (launcher != null && containsNavKeyRecursive(root, launcher)) {
        resolvedItems =
            attachNavChildrenRecursive(root, launcher, currentItems);
        resolvedActiveKey = launcher;
      } else {
        resolvedItems = root;
        resolvedActiveKey = parentKey;
      }
    } else if (parentKey != null && root.isEmpty) {
      resolvedItems = currentItems;
      resolvedActiveKey = parentKey;
    } else {
      resolvedItems = currentItems;
      resolvedActiveKey = null;
    }

    if (gestopro && scope != null) {
      scope.register(resolvedItems, activeSubKey: resolvedActiveKey);
      GestoproNavSubItemsCache.update(
        resolvedItems,
        activeSubKey: resolvedActiveKey,
      );
    } else if (!GestoproModePrefs.sessionActive) {
      ClassicNavSessionCache.markClassicChrome();
      ClassicNavSessionCache.setActiveSection(ClassicNavSection.dashboard);
      ClassicNavSubItemsCache.updateDashboard(
        resolvedItems,
        activeSubKey: resolvedActiveKey,
      );
      GestoproNavSubItemsCache.update(
        resolvedItems,
        activeSubKey: resolvedActiveKey,
      );
    }
  }

  void _openHubItem(BuildContext context, AdminHubNavItem item) {
    final override = widget.tapOverrides?[item.layoutKey];
    if (override != null) {
      override(context);
      return;
    }
    final dest = item.onTap(context);
    if (dest is AdminHubActionOnly) return;
    FuturisticNavigation.pushPage(
      context,
      page: dest,
      title: item.label,
      activeSubKey: item.layoutKey,
      onAfter: () => refreshHubAssenzeBlink(force: true),
    );
  }

  List<Widget> _chromelessToolbarActions(
    BuildContext context,
    bool canEditLayout,
  ) {
    return [
      if (canEditLayout &&
          widget.onRenameSections != null &&
          !_reorderMode &&
          !_loadingLayout)
        IconButton(
          tooltip: 'Rinomina sezioni',
          icon: const Icon(Icons.edit_outlined),
          onPressed: widget.onRenameSections,
        ),
      if (canEditLayout &&
          widget.showCreatePageButton &&
          !_reorderMode &&
          !_loadingLayout)
        IconButton(
          tooltip: 'Nuova cartella',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () async {
            await promptCreateCustomHubPage(
              context,
              userId: widget.userId,
              role: widget.role,
              originLayoutKey: widget.layoutKey,
              asSubfolder: true,
              homeDipendente: widget.homeDipendente,
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
      if (widget.userId != null)
        NotificationBell(
          userId: widget.userId!,
          iconColor: CronosFuturisticTheme.neonCyan,
        ),
      IconButton(
        tooltip: 'Video',
        icon: const Icon(Icons.video_library_outlined),
        onPressed: () => VideoGalleryNavigation.open(
          context,
          role: widget.role,
        ),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _buildGestoproReorderToolbar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Trascina i moduli per riordinarli. '
              'Angoli = ridimensiona. Tile grandi = più celle. '
              'Palette = colori e nome. ✕ elimina. ⇄ sposta pagina. '
              'Poi «Salva per tutti».',
              style: CronosFonts.exo2(
                fontSize: 12,
                height: 1.25,
                color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => setState(() {
              _reorderMode = false;
              _reorderDraft = <AdminHubNavItem>[];
              _styleDraft = <String, HubTileStyle>{};
              _styleDraftBaseline = <String, HubTileStyle>{};
            }),
            child: Text(
              'Annulla',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CronosFuturisticTheme.neonCyan,
              foregroundColor: const Color(0xFF041018),
            ),
            onPressed: _saveReorder,
            child: const Text('Salva per tutti'),
          ),
        ],
      ),
    );
  }

  @override
  String? get hubAssenzeBlinkRole => widget.role;

  @override
  HubLayoutOrders? get hubAssenzeLayoutOrders => _hubOrders;

  @override
  String get hubAssenzeCurrentLayoutKey => widget.layoutKey;

  List<AdminHubNavItem> _filterHubTilesByRole(
    List<AdminHubNavItem> tiles,
    String? role,
  ) {
    final r = normalizeRole(role ?? '');
    final onUqsa = widget.layoutKey == AppUiLayoutService.layoutUqsaHub;
    return tiles
        .where((t) {
          // Liste POS solo dentro il hub POS; su UQSA resta il tile POS.
          if (t.layoutKey == 'liste_pos_hub') {
            return canAccessListePosHub(r);
          }
          if (t.layoutKey == 'pos_dipendenti_lista') {
            if (onUqsa) return false;
            return canAccessPosDipendentiLista(r);
          }
          if (t.layoutKey == 'pos_mdo_ferroviari_lista') {
            if (onUqsa) return false;
            return canAccessPosMdoFerroviariLista(r);
          }
          if (t.layoutKey == 'pos_mezzi_stradali_lista') {
            if (onUqsa) return false;
            return canAccessPosMezziStradaliLista(r);
          }
          if (t.layoutKey == 'pos_mdo_proprieta_lista') {
            if (onUqsa) return false;
            return canAccessPosMdoProprietaLista(r);
          }
          if (t.layoutKey == 'qt_fatturazione_verifica') {
            return canAccessQtCarburanteVerifica(r);
          }
          if (isDpiVestiarioLayoutKey(t.layoutKey)) {
            return canAccessDpiVestiarioModule(r);
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _reloadTiles({Map<String, HubTileStyle>? priorStyles}) async {
    try {
      await _reloadTilesImpl(priorStyles: priorStyles);
    } catch (e) {
      if (!mounted) return;
      if (_isCarburanteHub) {
        final fallback = _filterHubTilesByRole(
          buildCarburanteHubNavItems(role: widget.role),
          widget.role,
        );
        setState(() {
          _tiles = fallback;
          _loadingLayout = false;
        });
        unawaited(
          AppUiLayoutService.ensureCarburanteHubLayoutPersisted(
            keys: AppUiLayoutService.carburanteHubDefaultKeys(),
            role: widget.role,
          ),
        );
      } else {
        setState(() => _loadingLayout = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Layout hub non caricato: $e'),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _reloadTilesImpl({Map<String, HubTileStyle>? priorStyles}) async {
    final customHubs =
        await AppUiLayoutService.loadCustomHubsWithSyncedLabels();
    if (!mounted) return;
    final catalog = AdminHubCatalog.build(
      context,
      adminId: widget.userId ?? 0,
      role: widget.role,
      customAllowedPages: widget.customAllowedPages,
      showUqsaTesserino: widget.showUqsaTesserino,
      showUqsaTesserini: widget.showUqsaTesserini,
      onPuliziaDati: widget.onPuliziaDati,
      homeDipendente: widget.homeDipendente ??
          (widget.userId != null
              ? HomeDipendenteNavParams(
                  userId: widget.userId!,
                  username: '',
                  fullName: '',
                )
              : null),
      customHubs: customHubs,
    );
    final layoutRole = DtViewRoleScope.layoutPersistenceRole(context, widget.role);
    final orders = await AppUiLayoutService.loadHubOrders(
      defaultKeysByLayout: catalog.defaultKeysByLayout,
      customHubs: customHubs,
      role: layoutRole.isEmpty ? null : layoutRole,
    );
    final hubLayoutKey = _effectiveHubLayoutKey;
    Map<String, HubTileStyle> tileStyles = priorStyles ?? _tileStyles;
    try {
      final loaded = await AppUiLayoutService.loadTileStylesForLayout(
        hubLayoutKey,
      );
      tileStyles = priorStyles != null
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
            'Stili pulsanti non caricati da Supabase: $e. '
            'Verifica la migration app_ui_tile_styles.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (!mounted) return;
    final itemsByKey = widget.layoutKey == AppUiLayoutService.layoutListePosHub
        ? <String, AdminHubNavItem>{
            for (final i in buildPosListeHubNavItems(
              adminUserId: widget.userId,
              role: widget.role,
              compactLabels: true,
            ))
              i.layoutKey: i,
          }
        : catalog.itemsByKey;
    var catalogForHub = itemsByKey;
    if (_isCarburanteHub) {
      catalogForHub = Map<String, AdminHubNavItem>.from(itemsByKey);
      for (final item in buildCarburanteHubNavItems(role: widget.role)) {
        catalogForHub.putIfAbsent(item.layoutKey, () => item);
      }
    }
    var hubKeyOrder = orders.keysFor(hubLayoutKey);
    if (widget.layoutKey == AppUiLayoutService.layoutLogisticaHub) {
      hubKeyOrder = AppUiLayoutService.resolveLogisticaHubOrderKeys(
        hubKeyOrder,
        catalog.defaultKeysByLayout[widget.layoutKey] ?? const <String>[],
      );
    } else if (widget.layoutKey == AppUiLayoutService.layoutUqsaHub) {
      hubKeyOrder = AppUiLayoutService.ensureUqsaHubOrderKeys(hubKeyOrder);
      orders.setKeysFor(hubLayoutKey, hubKeyOrder);
    } else if (_isCarburanteHub) {
      hubKeyOrder = AppUiLayoutService.resolveCarburanteHubOrderKeys(
        hubKeyOrder,
        catalog.defaultKeysByLayout[hubLayoutKey] ?? const <String>[],
      );
      if (hubKeyOrder.isEmpty) {
        hubKeyOrder = AppUiLayoutService.carburanteHubDefaultKeys();
      }
      hubKeyOrder = AppUiLayoutService.ensureCarburanteHubOrderKeys(hubKeyOrder);
      orders.setKeysFor(hubLayoutKey, hubKeyOrder);
    } else if (widget.layoutKey == AppUiLayoutService.layoutListePosHub) {
      hubKeyOrder = AppUiLayoutService.resolveListePosHubOrderKeys(
        hubKeyOrder,
        catalog.defaultKeysByLayout[hubLayoutKey] ?? const <String>[],
      );
      if (hubKeyOrder.isEmpty) {
        hubKeyOrder = AppUiLayoutService.posListeHubDefaultKeys();
      }
      hubKeyOrder = AppUiLayoutService.ensureListePosHubOrderKeys(hubKeyOrder);
      orders.setKeysFor(hubLayoutKey, hubKeyOrder);
    }
    var resolvedTiles = _filterHubTilesByRole(
      AppUiLayoutService.itemsForHub(
        catalog: catalogForHub,
        hubKeyOrder: hubKeyOrder,
      ),
      widget.role,
    );
    if (_isCarburanteHub && resolvedTiles.isEmpty) {
      hubKeyOrder = AppUiLayoutService.carburanteHubDefaultKeys();
      resolvedTiles = _filterHubTilesByRole(
        buildCarburanteHubNavItems(role: widget.role),
        widget.role,
      );
      orders.setKeysFor(hubLayoutKey, hubKeyOrder);
    }
    if (widget.layoutKey == AppUiLayoutService.layoutListePosHub &&
        resolvedTiles.isEmpty) {
      hubKeyOrder = AppUiLayoutService.posListeHubDefaultKeys();
      resolvedTiles = _filterHubTilesByRole(
        buildPosListeHubNavItems(
          adminUserId: widget.userId,
          role: widget.role,
          compactLabels: true,
        ),
        widget.role,
      );
      orders.setKeysFor(hubLayoutKey, hubKeyOrder);
    }
    setState(() {
      _hubOrders = orders;
      _tiles = resolvedTiles.isNotEmpty
          ? resolvedTiles
          : (_isCarburanteHub
              ? _filterHubTilesByRole(
                  buildCarburanteHubNavItems(role: widget.role),
                  widget.role,
                )
              : (widget.layoutKey == AppUiLayoutService.layoutListePosHub
                  ? _filterHubTilesByRole(
                      buildPosListeHubNavItems(
                        adminUserId: widget.userId,
                        role: widget.role,
                        compactLabels: true,
                      ),
                      widget.role,
                    )
                  : resolvedTiles));
      _tileStyles = tileStyles;
      _loadingLayout = false;
      _reorderMode = false;
      _reorderDraft = <AdminHubNavItem>[];
      _styleDraft = <String, HubTileStyle>{};
      _styleDraftBaseline = <String, HubTileStyle>{};
    });
    if (_isCarburanteHub && _tiles.isNotEmpty) {
      unawaited(
        AppUiLayoutService.ensureCarburanteHubLayoutPersisted(
          keys: hubKeyOrder,
          role: layoutRole.isEmpty ? widget.role : layoutRole,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSidebarSubNav());
    await refreshHubAssenzeBlink(force: true);
  }

  Map<String, HubTileStyle> get _activeStyles =>
      _reorderMode ? _styleDraft : _tileStyles;

  Future<void> _editTileStyle(AdminHubNavItem item) async {
    final current = _activeStyles[item.layoutKey];
    final result = await showHubTileStyleEditor(
      context: context,
      itemKey: item.layoutKey,
      defaultLabel: item.label,
      defaultSubtitle: item.subtitle ?? '',
      defaultIcon: item.icon,
      initial: current,
      futuristicMode: GestoproModePrefs.sessionActive ||
          Theme.of(context).brightness == Brightness.dark,
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
      await AppUiLayoutService.saveTileStyleForLayout(
        layoutKey: widget.layoutKey,
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

  void _updateDropTargetScale(String targetLayoutKey, double sizeScale) {
    final base = _activeStyles[targetLayoutKey] ?? const HubTileStyle();
    final updated = base.copyWith(sizeScale: sizeScale);
    setState(() {
      if (updated.hasOverrides) {
        if (_reorderMode) {
          _styleDraft[targetLayoutKey] = updated;
        } else {
          _tileStyles[targetLayoutKey] = updated;
        }
      } else if (_reorderMode) {
        _styleDraft[targetLayoutKey] = const HubTileStyle();
      } else {
        _tileStyles.remove(targetLayoutKey);
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

  Future<void> _moveTileToLayout(String itemKey, String targetLayoutKey) async {
    if (kHubNonRelocatableKeys.contains(itemKey) || _hubOrders == null) return;
    if (AppUiCustomHub.isCustomLayoutKey(targetLayoutKey) ||
        AppUiCustomHub.isCustomLayoutKey(widget.layoutKey)) {
      AppUiHubRegistry.bindCustomHubs(
        await AppUiLayoutService.loadCustomHubs(),
      );
    }
    if (!mounted) return;
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
        widget.layoutKey,
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

  Future<void> _deleteTile(AdminHubNavItem item) async {
    if (_hubOrders == null) return;
    final duplicateCount =
        _reorderDraft.where((t) => t.layoutKey == item.layoutKey).length;
    final existsElsewhere = AppUiLayoutService.itemExistsOnOtherLayouts(
      _hubOrders!,
      widget.layoutKey,
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
            widget.layoutKey,
            item.layoutKey,
          );
        });
      } else if (scope == HubTileDeleteScope.currentPageOnly) {
        setState(() {
          _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
          _hubOrders = AppUiLayoutService.removeAllFromLayout(
            _hubOrders!,
            widget.layoutKey,
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
    _hubOrders!.setKeysFor(widget.layoutKey, keys);
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
      await AppUiLayoutService.saveTileStyles(stylesToPersist);
      await AppUiLayoutService.saveTileGridPlacements(
        layoutKey: widget.layoutKey,
        placements: gridToPersist,
      );
      if (!mounted) return;
      final snackMessage = widget.savedSnackMessage ??
          'Layout, posizioni e colori salvati (${_hubOrders!.keysFor(widget.layoutKey).length} pulsanti su questa pagina).';
      await _reloadTiles(priorStyles: mergedStyles);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackMessage),
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

  int _crossAxisCount(double w, bool isMobileLayout) {
    final cellW = widget.maxCellWidth * widget.gridScale;
    if (widget.embedded) {
      return hubEmbeddedCrossAxisCount(width: w, maxCellWidth: cellW);
    }
    return hubResponsiveCrossAxisCount(
      width: w,
      maxCellWidth: cellW,
      isMobileLayout: isMobileLayout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final useListHub = _useHubListLayout(context);
    final normalizedRole = normalizeRole(widget.role ?? '');
    final canEditLayout = AppUiLayoutService.canEditGlobalLayout(normalizedRole);
    final tiles = _reorderMode ? _reorderDraft : _tiles;
    final displayTiles = _loadingLayout ? <AdminHubNavItem>[] : tiles;
    final aspect =
        useListHub ? widget.mobileAspectRatio : widget.desktopAspectRatio;
    final chromeless = isGestoproFuturisticUi(context);

    Widget buildHubColumn({required bool boundedHeight}) {
      return Column(
        mainAxisSize: boundedHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dual brand su ogni hub (Home / Logistica / UQSA / …), anche embedded.
          if (!chromeless)
            Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                widget.embedded ? 4 : 0,
                8,
                0,
              ),
              child: PageTopLogo(size: widget.embedded ? 72 : 96),
            ),
          if (widget.embedded && canEditLayout)
            _EmbeddedReorderToolbar(
              reorderMode: _reorderMode,
              loading: _loadingLayout,
              onEnterReorder: _enterReorderMode,
              onCancel: () => setState(() {
                _reorderMode = false;
                _reorderDraft = <AdminHubNavItem>[];
                _styleDraft = <String, HubTileStyle>{};
                _styleDraftBaseline = <String, HubTileStyle>{};
              }),
              onSave: _saveReorder,
            ),
          if (_reorderMode && !chromeless)
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
              currentLayoutKey: widget.layoutKey,
              onAcceptItemKey: _moveTileToLayout,
              styleForLayoutKey: (layoutKey) =>
                  _activeStyles[layoutKey]?.sizeScale,
              onScaleLayoutTarget: _updateDropTargetScale,
            ),
          if (widget.embedded)
            boundedHeight
                ? Expanded(
                    child: _buildHubGrid(
                      isMobileLayout: chromeless ? false : true,
                      displayTiles: displayTiles,
                      canEditLayout: canEditLayout,
                      aspect: aspect,
                    ),
                  )
                : _buildHubGrid(
                    isMobileLayout: chromeless ? false : true,
                    displayTiles: displayTiles,
                    canEditLayout: canEditLayout,
                    aspect: aspect,
                  )
          else
            Expanded(
              child: chromeless
                  ? _buildHubGrid(
                      isMobileLayout: useListHub,
                      displayTiles: displayTiles,
                      canEditLayout: canEditLayout,
                      aspect: aspect,
                    )
                  : PageWithTopLogo(
                      // Logo già in cima a buildHubColumn (evita doppione).
                      showLogo: false,
                      child: useListHub
                          ? _buildHubGrid(
                              isMobileLayout: true,
                              displayTiles: displayTiles,
                              canEditLayout: canEditLayout,
                              aspect: aspect,
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final useFreeform =
                                    hubShouldUseFreeformLayout(
                                  isMobileLayout: false,
                                  width: constraints.maxWidth,
                                  reorderMode: _reorderMode,
                                  canEditLayout: canEditLayout,
                                  layoutKeys: displayTiles
                                      .map((t) => t.layoutKey),
                                  activeStyles: _activeStyles,
                                );
                                if (useFreeform) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: 1180,
                                          maxHeight: constraints.maxHeight,
                                        ),
                                        child: _buildHubGrid(
                                          isMobileLayout: false,
                                          displayTiles: displayTiles,
                                          canEditLayout: canEditLayout,
                                          aspect: aspect,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1180,
                                      ),
                                      child: _buildHubGrid(
                                        isMobileLayout: false,
                                        displayTiles: displayTiles,
                                        canEditLayout: canEditLayout,
                                        aspect: aspect,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
        ],
      );
    }

    final hubBody = _loadingLayout
        ? const Center(child: CircularProgressIndicator())
        : widget.embedded
            ? LayoutBuilder(
                builder: (context, constraints) => buildHubColumn(
                  boundedHeight: constraints.maxHeight.isFinite,
                ),
              )
            : buildHubColumn(boundedHeight: true);

    if (widget.embedded || chromeless) {
      if (chromeless && !widget.embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FuturisticInlineToolbar(
              title: widget.title,
              actions: _chromelessToolbarActions(context, canEditLayout),
            ),
            if (_reorderMode) _buildGestoproReorderToolbar(),
            Expanded(child: hubBody),
          ],
        );
      }
      return hubBody;
    }

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(title: widget.title),
        actions: [
          if (canEditLayout &&
              widget.onRenameSections != null &&
              !_reorderMode &&
              !_loadingLayout)
            IconButton(
              tooltip: 'Rinomina sezioni',
              icon: const Icon(Icons.edit_outlined),
              onPressed: widget.onRenameSections,
            ),
          if (canEditLayout &&
              widget.showCreatePageButton &&
              !_reorderMode &&
              !_loadingLayout)
            IconButton(
              tooltip: 'Nuova cartella',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () async {
                await promptCreateCustomHubPage(
                  context,
                  userId: widget.userId,
                  role: widget.role,
                  originLayoutKey: widget.layoutKey,
                  asSubfolder: true,
                  homeDipendente: widget.homeDipendente,
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
                _reorderDraft = <AdminHubNavItem>[];
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
          if (widget.userId != null)
            NotificationBell(
              userId: widget.userId!,
              iconColor: Theme.of(context).colorScheme.onPrimary,
            ),
          IconButton(
            tooltip: 'Video',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: () => VideoGalleryNavigation.open(
              context,
              role: widget.role,
            ),
          ),
          const SizedBox(width: 8),
        ],
      )),
      body: hubBody,
    );
  }

  // Lista compatta (come home) solo su mobile/tablet; griglia su desktop.
  bool _useHubListLayout(BuildContext context) {
    if (isGestoproFuturisticUi(context) && !useMobileUi(context)) {
      return false;
    }
    return useMobileUi(context) || useCompactPageLayout(context);
  }

  Widget _buildHubGrid({
    required bool isMobileLayout,
    required List<AdminHubNavItem> displayTiles,
    required bool canEditLayout,
    required double aspect,
  }) {
    final chromeless = isGestoproFuturisticUi(context);
    if (displayTiles.isEmpty) {
      return _EmptyHubPageHint(
        canEditLayout: canEditLayout,
        embedded: widget.embedded,
      );
    }

    final useMobileList = _useHubListLayout(context);

    if (useMobileList) {
      return _HubMobileList(
        tiles: displayTiles,
        reorderMode: _reorderMode,
        canEditLayout: canEditLayout,
        currentLayoutKey: widget.layoutKey,
        tileStyles: _activeStyles,
        onHoldReorder: _enterReorderMode,
        onMoveToLayout: _moveTileToLayout,
        onDeleteTile: _deleteTile,
        onEditTileStyle: canEditLayout ? _editTileStyle : null,
        tapOverrides: widget.tapOverrides,
        shrinkWrap: widget.embedded,
        hubAssenzeBlinkKeys: hubAssenzeBlinkKeys,
        hubAssenzeBlinkOn: hubAssenzeBlinkOn,
        onAfterNav: () => refreshHubAssenzeBlink(force: true),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            final next = List<AdminHubNavItem>.from(_reorderDraft);
            if (newIndex > oldIndex) newIndex--;
            final item = next.removeAt(oldIndex);
            next.insert(newIndex, item);
            _reorderDraft = next;
          });
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = _crossAxisCount(
          constraints.maxWidth,
          isMobileLayout || (widget.embedded && constraints.maxWidth < 720),
        );
        // In popup/dialog (scroll) non usare canvas freeform né griglia espansa.
        final boundedHeight = constraints.maxHeight.isFinite;
        final useFreeform =
            (!widget.embedded || (chromeless && boundedHeight)) &&
            hubShouldUseFreeformLayout(
              isMobileLayout: isMobileLayout,
              width: constraints.maxWidth,
              reorderMode: _reorderMode,
              canEditLayout: canEditLayout,
              layoutKeys: displayTiles.map((t) => t.layoutKey),
              activeStyles: _activeStyles,
            );

        Widget buildHubTile(int index) => _HubTile(
              key: ValueKey<String>(displayTiles[index].layoutKey),
              item: displayTiles[index],
              embedded: widget.embedded || chromeless,
              tileStyle: _activeStyles[displayTiles[index].layoutKey],
              reorderMode: _reorderMode,
              fillCell: true,
              canEditLayout: canEditLayout,
              currentLayoutKey: widget.layoutKey,
              onHoldReorder: _enterReorderMode,
              onMoveToLayout: _moveTileToLayout,
              onDeleteTile: _deleteTile,
              onEditTileStyle: canEditLayout ? _editTileStyle : null,
              onResizeTileStyle: canEditLayout ? _updateTileScale : null,
              tapOverrides: widget.tapOverrides,
              hubAssenzeBlinkKeys: hubAssenzeBlinkKeys,
              hubAssenzeBlinkOn: hubAssenzeBlinkOn,
              onAfterNav: () => refreshHubAssenzeBlink(force: true),
            );

        final useUniformGrid = !useFreeform &&
            (isMobileLayout || (widget.embedded && !_reorderMode));

        if (useUniformGrid) {
          final shrinkEmbedded = widget.embedded && !boundedHeight;
          return Padding(
            padding: EdgeInsets.all(widget.embedded ? 8 : 12),
            child: GridView.builder(
              shrinkWrap: shrinkEmbedded,
              physics: shrinkEmbedded
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: aspect,
              ),
              itemCount: displayTiles.length,
              itemBuilder: (context, index) => buildHubTile(index),
            ),
          );
        }

        final grid = useFreeform
            ? CronosFreeformHubCanvas(
                itemCount: displayTiles.length,
                crossAxisCount: cross,
                childAspectRatio: aspect,
                maxCanvasHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : null,
                reorderMode: _reorderMode,
                layoutKeyForIndex: (index) => displayTiles[index].layoutKey,
                styleForKey: (key) => _activeStyles[key],
                scaleForIndex: (index) =>
                    _activeStyles[displayTiles[index].layoutKey]?.sizeScale ??
                    1.0,
                onGridCellChanged: canEditLayout
                    ? (key, col, row, colSpan, rowSpan) {
                        final tile = displayTiles.firstWhere(
                          (t) => t.layoutKey == key,
                        );
                        _updateTileGrid(tile, col, row, colSpan, rowSpan);
                      }
                    : null,
                itemBuilder: (context, index) => buildHubTile(index),
              )
            : CronosAdaptiveHubGrid(
                crossAxisCount: cross,
                childAspectRatio: aspect,
                itemCount: displayTiles.length,
                reorderMode: _reorderMode,
                onReorder: _reorderMode
                    ? (oldIndex, newIndex) {
                        setState(() {
                          final next =
                              List<AdminHubNavItem>.from(_reorderDraft);
                          final item = next.removeAt(oldIndex);
                          next.insert(newIndex, item);
                          _reorderDraft = next;
                        });
                      }
                    : null,
                scaleForIndex: (index) =>
                    _activeStyles[displayTiles[index].layoutKey]?.sizeScale ??
                    1.0,
                itemBuilder: (context, index) => buildHubTile(index),
              );

        final gridPadding = EdgeInsets.all(widget.embedded ? 4 : 8);
        return Padding(
          padding: gridPadding,
          child: grid,
        );
      },
    );
  }
}

class _EmbeddedReorderToolbar extends StatelessWidget {
  const _EmbeddedReorderToolbar({
    required this.reorderMode,
    required this.loading,
    required this.onEnterReorder,
    required this.onCancel,
    required this.onSave,
  });

  final bool reorderMode;
  final bool loading;
  final VoidCallback onEnterReorder;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    const accent = Color(0xFF1565C0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (!reorderMode)
            FilledButton.tonalIcon(
              onPressed: onEnterReorder,
              icon: const Icon(Icons.reorder_rounded, size: 18),
              label: const Text('Riordina pulsanti'),
              style: FilledButton.styleFrom(
                foregroundColor: accent,
                backgroundColor: accent.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          if (reorderMode) ...[
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Annulla'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Salva per tutti'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HubMobileList extends StatelessWidget {
  const _HubMobileList({
    required this.tiles,
    required this.reorderMode,
    required this.canEditLayout,
    required this.currentLayoutKey,
    required this.tileStyles,
    required this.onHoldReorder,
    required this.onMoveToLayout,
    required this.onDeleteTile,
    required this.onReorder,
    this.onEditTileStyle,
    this.tapOverrides,
    this.shrinkWrap = false,
    this.hubAssenzeBlinkKeys = const <String>{},
    this.hubAssenzeBlinkOn = true,
    this.onAfterNav,
  });

  final List<AdminHubNavItem> tiles;
  final bool reorderMode;
  final bool canEditLayout;
  final String currentLayoutKey;
  final Map<String, HubTileStyle> tileStyles;
  final VoidCallback onHoldReorder;
  final void Function(String itemKey, String targetLayoutKey) onMoveToLayout;
  final void Function(AdminHubNavItem item) onDeleteTile;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(AdminHubNavItem item)? onEditTileStyle;
  final Map<String, void Function(BuildContext context)>? tapOverrides;
  final bool shrinkWrap;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;
  final VoidCallback? onAfterNav;

  static Color _readableAccentColor({
    required Color? preferred,
    required Color background,
    required Color fallback,
  }) {
    if (preferred == null) return fallback;
    if ((background.computeLuminance() - preferred.computeLuminance()).abs() <
        0.18) {
      return fallback;
    }
    return preferred;
  }

  void _open(BuildContext context, AdminHubNavItem item) {
    final override = tapOverrides?[item.layoutKey];
    if (override != null) {
      override(context);
      return;
    }
    final dest = item.onTap(context);
    if (dest is AdminHubActionOnly) return;
    FuturisticNavigation.pushPage(
      context,
      page: dest,
      title: item.label,
      activeSubKey: item.layoutKey,
      onAfter: onAfterNav,
    );
  }

  Widget _buildMobileRow(BuildContext context, AdminHubNavItem item) {
    final theme = Theme.of(context);
    final style = tileStyles[item.layoutKey];
    final rawLabel = style?.effectiveLabel(item.label) ?? item.label;
    final label = rawLabel.trim().isEmpty ? item.label : rawLabel.trim();
    final subtitle = (style ?? const HubTileStyle())
        .effectiveSubtitle(item.subtitle ?? '');
    final bg = style?.backgroundColor ?? theme.colorScheme.surface;
    final iconColor = AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: item.layoutKey,
      blinkKeys: hubAssenzeBlinkKeys,
      blinkOn: hubAssenzeBlinkOn,
      fallback: style?.iconColor ??
          _readableAccentColor(
            preferred: item.iconColor,
            background: bg,
            fallback: theme.colorScheme.primary,
          ),
    );
    final textColor = style?.textColor ??
        _readableAccentColor(
          preferred: null,
          background: bg,
          fallback: theme.colorScheme.onSurface,
        );
    const radius = BorderRadius.all(Radius.circular(18));
    final hasTapOverride = tapOverrides?.containsKey(item.layoutKey) ?? false;
    final useOpenContainer = !reorderMode &&
        useMobileUi(context) &&
        !GestoproModePrefs.sessionActive &&
        !hasTapOverride &&
        !kHubActionOnlyKeys.contains(item.layoutKey);
    final canMove = reorderMode &&
        canEditLayout &&
        !kHubNonRelocatableKeys.contains(item.layoutKey);
    final canDelete = reorderMode && canEditLayout;
    final canStyle = reorderMode && canEditLayout && onEditTileStyle != null;
    final displayIcon = reorderMode
        ? Icons.drag_indicator
        : (style?.effectiveIcon(item.icon) ?? item.icon);

    Widget listContent({VoidCallback? onTap}) {
      final chromeless = isGestoproFuturisticUi(context);
      if (chromeless) {
        final card = NeonCard(
          title: label,
          subtitle: subtitle.trim().isEmpty ? null : subtitle,
          icon: displayIcon,
          color: iconColor,
          tileStyle: style,
          onTap: reorderMode ? null : onTap,
        );
        if (!reorderMode) return card;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            card,
            _GestoproHubReorderOverlay(
              item: item,
              currentLayoutKey: currentLayoutKey,
              canMove: canMove,
              canDelete: canDelete,
              canStyle: canStyle,
              onMoveToLayout: onMoveToLayout,
              onDeleteTile: onDeleteTile,
              onEditTileStyle: onEditTileStyle,
            ),
          ],
        );
      }

      final glassTile = PremiumGlassHubTile(
        layoutKey: item.layoutKey,
        title: label,
        subtitle: subtitle.trim().isEmpty ? null : subtitle,
        icon: displayIcon,
        onTap: reorderMode ? null : onTap,
        backgroundColor: style?.backgroundColor,
        iconColor: iconColor,
        textColor: textColor,
        margin: EdgeInsets.zero,
        borderRadius: 18,
      );
      if (!(canMove || canDelete || canStyle)) {
        return glassTile;
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          glassTile,
          Positioned(
            top: 6,
            right: 6,
            child: Row(
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
                    currentLayoutKey: currentLayoutKey,
                    itemKey: item.layoutKey,
                    onMoveTo: (target) =>
                        onMoveToLayout(item.layoutKey, target),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    Widget row;
    if (useOpenContainer) {
      row = MobileOpenContainer(
        closedColor: bg,
        closedBorderRadius: radius,
        closedBuilder: (_, open) => listContent(onTap: open),
        destination: Builder(
          builder: (ctx) {
            final dest = item.onTap(ctx);
            if (dest is AdminHubActionOnly) return const SizedBox.shrink();
            return dest;
          },
        ),
      );
    } else {
      row = listContent(onTap: () => _open(context, item));
    }

    if (reorderMode) {
      return CronosJiggleMode(active: true, child: row);
    }
    if (canEditLayout) {
      return CronosHoldToReorderDetector(
        enabled: true,
        onHoldComplete: onHoldReorder,
        child: row,
      );
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final listPhysics =
        shrinkWrap ? const NeverScrollableScrollPhysics() : null;
    if (reorderMode) {
      return ReorderableListView.builder(
        shrinkWrap: shrinkWrap,
        physics: listPhysics,
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
              child: _buildMobileRow(context, item),
            ),
          );
        },
      );
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: listPhysics,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: tiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildMobileRow(context, tiles[index]),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    super.key,
    required this.item,
    required this.currentLayoutKey,
    this.tileStyle,
    this.reorderMode = false,
    this.fillCell = false,
    this.canEditLayout = false,
    this.onHoldReorder,
    this.onMoveToLayout,
    this.onDeleteTile,
    this.onEditTileStyle,
    this.onResizeTileStyle,
    this.tapOverrides,
    this.hubAssenzeBlinkKeys = const <String>{},
    this.hubAssenzeBlinkOn = true,
    this.onAfterNav,
    this.embedded = false,
  });

  final AdminHubNavItem item;
  final String currentLayoutKey;
  final HubTileStyle? tileStyle;
  final bool reorderMode;
  final bool fillCell;
  final bool canEditLayout;
  final VoidCallback? onHoldReorder;
  final void Function(String itemKey, String targetLayoutKey)? onMoveToLayout;
  final void Function(AdminHubNavItem item)? onDeleteTile;
  final void Function(AdminHubNavItem item)? onEditTileStyle;
  final void Function(AdminHubNavItem item, double sizeScale)? onResizeTileStyle;
  final Map<String, void Function(BuildContext context)>? tapOverrides;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;
  final VoidCallback? onAfterNav;
  final bool embedded;

  void _open(BuildContext context) {
    final override = tapOverrides?[item.layoutKey];
    if (override != null) {
      override(context);
      return;
    }
    final dest = item.onTap(context);
    if (dest is AdminHubActionOnly) return;
    FuturisticNavigation.pushPage(
      context,
      page: dest,
      title: item.label,
      activeSubKey: item.layoutKey,
      onAfter: onAfterNav,
    );
  }

  static Color _readableAccentColor({
    required Color? preferred,
    required Color background,
    required Color fallback,
  }) {
    if (preferred == null) return fallback;
    final bgL = background.computeLuminance();
    final fgL = preferred.computeLuminance();
    if ((bgL - fgL).abs() < 0.18) return fallback;
    return preferred;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (fillCell) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cellScale = HubTileStyleMetrics.cellScaleFromConstraints(
            constraints,
          );
          return _buildHubTileBody(context, theme, cellScale: cellScale);
        },
      );
    }
    return _buildHubTileBody(context, theme);
  }

  Widget _buildHubTileBody(
    BuildContext context,
    ThemeData theme, {
    double cellScale = 1.0,
  }) {
    final closedColor = tileStyle?.backgroundColor ?? theme.colorScheme.surface;
    final metrics = HubTileStyleMetrics.fromStyle(
      style: tileStyle,
      fillCell: fillCell,
      cellScale: cellScale,
    );
    final rawLabel = tileStyle?.effectiveLabel(item.label) ?? item.label;
    final label = rawLabel.trim().isEmpty ? 'Pulsante' : rawLabel.trim();
    final subtitle = (tileStyle ?? const HubTileStyle())
        .effectiveSubtitle(item.subtitle ?? '');
    final bg = tileStyle?.backgroundColor ?? theme.colorScheme.surface;
    final iconColor = AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: item.layoutKey,
      blinkKeys: hubAssenzeBlinkKeys,
      blinkOn: hubAssenzeBlinkOn,
      fallback: tileStyle?.iconColor ??
          _readableAccentColor(
            preferred: item.iconColor,
            background: bg,
            fallback: theme.colorScheme.primary,
          ),
    );
    final textColor = tileStyle?.textColor ??
        _readableAccentColor(
          preferred: null,
          background: bg,
          fallback: theme.colorScheme.onSurface,
        );
    final subtitleColor = tileStyle?.textColor ??
        _readableAccentColor(
          preferred: null,
          background: bg,
          fallback: theme.colorScheme.onSurfaceVariant,
        );
    final hasTapOverride = tapOverrides?.containsKey(item.layoutKey) ?? false;
    final useNeon = isGestoproFuturisticUi(context);
    final useOpenContainer = !reorderMode &&
        useMobileUi(context) &&
        !GestoproModePrefs.sessionActive &&
        !hasTapOverride &&
        !kHubActionOnlyKeys.contains(item.layoutKey);
    final canMove = reorderMode &&
        canEditLayout &&
        onMoveToLayout != null &&
        !kHubNonRelocatableKeys.contains(item.layoutKey);
    final canDelete = reorderMode && canEditLayout && onDeleteTile != null;
    final canStyle = reorderMode &&
        canEditLayout &&
        onEditTileStyle != null;
    final scale = tileStyle?.sizeScale ?? 1.0;
    final inFreeformLayout = HubGridDragScope.maybeOf(context) != null;
    final canResize = reorderMode &&
        canEditLayout &&
        fillCell &&
        !inFreeformLayout &&
        onResizeTileStyle != null;
    final displayIcon = reorderMode
        ? Icons.drag_indicator
        : (tileStyle?.effectiveIcon(item.icon) ?? item.icon);

    Widget hubCard({VoidCallback? onTap}) {
      if (useNeon) {
        final iconSize = tileStyle
                ?.resolveIconSize(fillCell: fillCell, scale: scale)
                .clamp(16.0, 56.0) ??
            metrics.iconSize;
        final neon = NeonCard(
          title: label,
          subtitle: subtitle.trim().isEmpty ? null : subtitle,
          icon: displayIcon,
          iconWidget: reorderMode && inFreeformLayout
              ? wrapFreeformDragIcon(
                  context: context,
                  icon: Icon(
                    Icons.drag_indicator,
                    size: iconSize,
                    color: iconColor,
                    shadows: [
                      Shadow(
                        color: iconColor.withValues(alpha: 0.8),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                )
              : null,
          color: iconColor,
          tileStyle: tileStyle,
          onTap: reorderMode ? null : onTap,
        );
        Widget sized = fillCell ? SizedBox.expand(child: neon) : neon;
        if (canResize) {
          sized = HubTileCornerResizeOverlay(
            enabled: true,
            sizeScale: scale,
            onScaleChanged: (v) => onResizeTileStyle!(item, v),
            child: sized,
          );
        }
        if (reorderMode && (canMove || canDelete || canStyle)) {
          if (inFreeformLayout && fillCell) {
            final styleBtn = canStyle
                ? FuturisticHubChip(
                    child: CronosHubTileStyleButton(
                      onPressed: () => onEditTileStyle!(item),
                    ),
                  )
                : null;
            final moveBtn = canMove
                ? FuturisticHubChip(
                    child: CronosHubMoveToLayoutButton(
                      currentLayoutKey: currentLayoutKey,
                      itemKey: item.layoutKey,
                      onMoveTo: (target) =>
                          onMoveToLayout!(item.layoutKey, target),
                    ),
                  )
                : null;
            final crossBtn = canMove
                ? FuturisticHubChip(
                    child: CronosHubCrossLayoutDragHandle(
                      itemKey: item.layoutKey,
                      label: item.label,
                    ),
                  )
                : null;
            final deleteBtn = canDelete
                ? FuturisticHubChip(
                    child: CronosHubDeleteTileButton(
                      onPressed: () => onDeleteTile!(item),
                    ),
                  )
                : null;
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
                _GestoproHubReorderOverlay(
                  item: item,
                  currentLayoutKey: currentLayoutKey,
                  canMove: canMove,
                  canDelete: canDelete,
                  canStyle: canStyle,
                  onMoveToLayout: onMoveToLayout,
                  onDeleteTile: onDeleteTile,
                  onEditTileStyle: onEditTileStyle,
                ),
              ],
            );
          }
        }
        return CronosJiggleMode(active: reorderMode, child: sized);
      }

      final card = Cronos3dSurface(
        color: tileStyle?.backgroundColor,
        child: InkWell(
          onTap: onTap,
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
                if (fillCell)
                  Flexible(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: wrapFreeformDragIcon(
                        context: context,
                        icon: Icon(
                          displayIcon,
                          size: subtitle.trim().isNotEmpty
                              ? metrics.iconSize * 0.88
                              : metrics.iconSize,
                          color: iconColor,
                        ),
                      ),
                    ),
                  )
                else
                  wrapFreeformDragIcon(
                    context: context,
                    icon: Icon(
                      displayIcon,
                      size: metrics.iconSize,
                      color: iconColor,
                    ),
                  ),
                SizedBox(
                  height: subtitle.trim().isNotEmpty
                      ? metrics.gapIconTitle * 0.75
                      : metrics.gapIconTitle,
                ),
                if (fillCell)
                  Flexible(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          flex: subtitle.trim().isNotEmpty ? 3 : 1,
                          child: HubTileAutoFitText(
                            text: label,
                            maxLines: 3,
                            minFontSize: 6,
                            maxFontSize: metrics.titleSize.clamp(6.0, 50.0),
                            style: metrics.resolveTitleStyle(
                              const TextStyle(
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                              textColor,
                            ),
                          ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          SizedBox(height: metrics.gapTitleSubtitle),
                          Flexible(
                            flex: 2,
                            child: HubTileAutoFitText(
                              text: subtitle,
                              maxLines: 3,
                              minFontSize: 5,
                              maxFontSize: metrics.subtitleSize.clamp(
                                5.0,
                                metrics.titleSize,
                              ),
                              style: (theme.textTheme.bodySmall ??
                                      const TextStyle())
                                  .copyWith(
                                height: 1.15,
                                color: subtitleColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else ...[
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: metrics.resolveTitleStyle(
                      const TextStyle(fontWeight: FontWeight.w700),
                      textColor,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    SizedBox(height: metrics.gapTitleSubtitle),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: metrics.subtitleSize,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ],
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
        final moveBtn = canMove
            ? FuturisticHubChip(
                child: CronosHubMoveToLayoutButton(
                  currentLayoutKey: currentLayoutKey,
                  itemKey: item.layoutKey,
                  onMoveTo: (target) =>
                      onMoveToLayout!(item.layoutKey, target),
                ),
              )
            : null;
        final crossBtn = canMove
            ? FuturisticHubChip(
                child: CronosHubCrossLayoutDragHandle(
                  itemKey: item.layoutKey,
                  label: item.label,
                ),
              )
            : null;
        final deleteBtn = canDelete
            ? FuturisticHubChip(
                child: CronosHubDeleteTileButton(
                  onPressed: () => onDeleteTile!(item),
                ),
              )
            : null;
        final styleBtn = canStyle
            ? FuturisticHubChip(
                child: CronosHubTileStyleButton(
                  onPressed: () => onEditTileStyle!(item),
                ),
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
      return CronosJiggleMode(active: reorderMode, child: sized);
    }

    Widget content;
    if (reorderMode) {
      content = hubCard();
    } else if (useOpenContainer) {
      content = MobileOpenContainer(
        closedColor: closedColor,
        closedBorderRadius: BorderRadius.circular(12),
        closedBuilder: (_, open) => hubCard(onTap: open),
        destination: Builder(
          builder: (ctx) {
            final dest = item.onTap(ctx);
            if (dest is AdminHubActionOnly) return const SizedBox.shrink();
            return dest;
          },
        ),
      );
    } else {
      content = hubCard(onTap: () => _open(context));
    }

    if (reorderMode || !canEditLayout || onHoldReorder == null) {
      return content;
    }
    return CronosHoldToReorderDetector(
      enabled: true,
      onHoldComplete: onHoldReorder!,
      child: content,
    );
  }
}

class _GestoproHubReorderOverlay extends StatelessWidget {
  const _GestoproHubReorderOverlay({
    required this.item,
    required this.currentLayoutKey,
    required this.canMove,
    required this.canDelete,
    required this.canStyle,
    this.onMoveToLayout,
    this.onDeleteTile,
    this.onEditTileStyle,
  });

  final AdminHubNavItem item;
  final String currentLayoutKey;
  final bool canMove;
  final bool canDelete;
  final bool canStyle;
  final void Function(String itemKey, String targetLayoutKey)? onMoveToLayout;
  final void Function(AdminHubNavItem item)? onDeleteTile;
  final void Function(AdminHubNavItem item)? onEditTileStyle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      left: 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (canStyle && onEditTileStyle != null)
            FuturisticHubChip(
              child: CronosHubTileStyleButton(
                onPressed: () => onEditTileStyle!(item),
              ),
            ),
          if (canDelete && onDeleteTile != null)
            FuturisticHubChip(
              child: CronosHubDeleteTileButton(
                onPressed: () => onDeleteTile!(item),
              ),
            ),
          if (canMove && onMoveToLayout != null) ...[
            FuturisticHubChip(
              child: CronosHubCrossLayoutDragHandle(
                itemKey: item.layoutKey,
                label: item.label,
              ),
            ),
            FuturisticHubChip(
              child: CronosHubMoveToLayoutButton(
                currentLayoutKey: currentLayoutKey,
                itemKey: item.layoutKey,
                onMoveTo: (target) =>
                    onMoveToLayout!(item.layoutKey, target),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHubPageHint extends StatelessWidget {
  const _EmptyHubPageHint({
    required this.canEditLayout,
    required this.embedded,
  });

  final bool canEditLayout;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.all(embedded ? 12 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 16),
              Text(
                'Pagina vuota',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                canEditLayout
                    ? 'Tieni premuto «Riordina» (o l\'icona in alto) e trascina '
                        'i pulsanti da un\'altra pagina qui. Puoi anche aggiungerne '
                        'di nuovi dalla Dashboard.'
                    : 'Nessun pulsante su questa pagina.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
