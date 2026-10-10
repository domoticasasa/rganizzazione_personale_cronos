import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/background_notif_service.dart';
import '../../widgets/app_logo.dart';

// === SERVIZI ===
import '../../services/employee_programmazione_service.dart';
import '../../services/visite_mediche_service.dart';
import '../../services/bacheca_service.dart';
import '../../services/hub_pending_poll_service.dart';
import '../../services/classic_nav_session_cache.dart';
import '../../services/classic_nav_sub_items_cache.dart';
import '../../services/notification_bell.dart';
import '../../services/app_ui_layout_service.dart';
import '../../utils/admin_vista_guard.dart';
import '../../utils/app_copyright.dart';
import '../../utils/app_logout.dart';
import '../../utils/custom_hub_creator.dart';
import '../../utils/dipendente_view_navigation.dart';
import '../../utils/dt_view_navigation.dart';
import '../../utils/futuristic_navigation.dart';
import '../../utils/dt_view_role.dart';
import '../../utils/responsive.dart';
import '../../utils/roles.dart';
import '../../utils/buono_pasto_scan_deep_link.dart';
import '../../utils/viaggio_mezzo_scan_deep_link.dart';
import '../../utils/video_gallery_navigation.dart';
import '../../Mobile/admin_misc_mobile_pages.dart';
import '../../pages/admin_custom_hub_page.dart';
import '../../widgets/cronos_3d_surface.dart';
import '../../widgets/mobile_open_container.dart';
import '../../hub/hub_tile_grid.dart';
import '../../hub/hub_tile_style.dart';
import '../../hub/admin_hub_catalog.dart';
import '../../hub/app_ui_custom_hub.dart';
import '../../hub/app_ui_hub_registry.dart';
import '../../hub/dashboard_hub_nav_items.dart';
import '../../hub/home_dipendente_nav_items.dart';
import '../../widgets/cronos_adaptive_hub_grid.dart';
import '../../widgets/cronos_freeform_hub_canvas.dart';
import '../../widgets/cronos_hold_to_reorder.dart';
import '../../widgets/cronos_hub_cross_layout_move.dart';
import '../../widgets/cronos_hub_delete_tile_button.dart';
import '../../widgets/hub_tile_auto_fit_text.dart';
import '../../widgets/hub_tile_corner_resize.dart';
import '../../widgets/hub_tile_style_editor.dart';
import '../../widgets/ui_view_mode_switch.dart';
import '../../widgets/classic_app_bar_chrome.dart';
import '../../widgets/futuristic/futuristic_nav_sub_item.dart';

/// Parametri layout Home (ordine/stili Supabase per ruolo).
class HomeHubLayoutConfig {
  const HomeHubLayoutConfig({
    required this.layoutKey,
    required this.defaultOrderKeys,
    required this.useCompactHomeGrid,
    required this.isAdminHomeGrid,
    required this.isDtHomeGrid,
    required this.compactMaxWidth,
    this.resolveOrderKeys,
  });

  final String layoutKey;
  final List<String> defaultOrderKeys;
  final bool useCompactHomeGrid;
  final bool isAdminHomeGrid;
  final bool isDtHomeGrid;
  final double compactMaxWidth;
  final List<String> Function(List<String>? saved, List<String> defaults)?
      resolveOrderKeys;

  List<String> orderKeys(List<String>? saved) =>
      resolveOrderKeys?.call(saved, defaultOrderKeys) ??
      (saved ?? defaultOrderKeys);
}

abstract class HomeHubPage extends StatefulWidget {
  final String username;
  final String fullName;
  final String role;
  final int userId;
  final HomeHubLayoutConfig layoutConfig;

  /// Admin in anteprima (es. vista DT): layout salvato per tutti sul layout della pagina.
  final String? layoutEditorRole;

  /// Ruolo secondario da profilo (es. DT per admin).
  final String? secondaryRole;

  const HomeHubPage({
    super.key,
    required this.username,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.layoutConfig,
    this.layoutEditorRole,
    this.secondaryRole,
  });

  bool get isLayoutPreviewMode => layoutEditorRole != null;

  @override
  HomeHubPageState createState();
}

abstract class HomeHubPageState extends State<HomeHubPage> {
  List<HomeHubTile> buildRoleTiles(ThemeData theme);

  String get _homeLayoutKey => widget.layoutConfig.layoutKey;

  bool get _useCompactHomeGrid => widget.layoutConfig.useCompactHomeGrid;

  bool get _isAdminHomeGrid => widget.layoutConfig.isAdminHomeGrid;

  bool get _isDtHomeGrid => widget.layoutConfig.isDtHomeGrid;

  double get _compactMaxWidth => widget.layoutConfig.compactMaxWidth;
  @protected
  bool hasPendingApprovals = false;
  @protected
  bool hasPendingAssenzeRichieste = false;
  int _pendingApprovalsCount = 0;
  @protected
  bool hasMyProgrammazione = false;
  @protected
  bool hasMyProgrammazioneRfi = false;
  @protected
  bool hasVisitaMedica = false;
  @protected
  bool hasBachecaUnread = false;
  @protected
  bool pendingBlinkOn = true;
  Timer? _pendingBlinkTimer;
  final _supa = Supabase.instance.client;
  final Set<String> customAllowedPages = <String>{};
  bool _customPermissionsLoaded = false;
  List<String>? _homeOrderKeys;
  bool _loadingHomeLayout = true;
  bool _reorderMode = false;
  List<HomeHubTile> _reorderDraft = <HomeHubTile>[];
  Map<String, HubTileStyle> _tileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraft = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraftBaseline = <String, HubTileStyle>{};
  HubLayoutOrders? _hubOrders;
  final Set<String> _pendingHiddenKeys = <String>{};
  List<AppUiCustomHub> _customHubs = <AppUiCustomHub>[];

  /// Override in [AdminHomePage] per salvataggio globale «per tutti».
  @protected
  bool get canEditHomeLayout => canEditHomePageLayout(widget.role);

  bool get _canCreateHomeFolders =>
      AppUiLayoutService.canEditGlobalLayout(layoutPersistenceRole);

  @protected
  bool get usesPersonalHomeLayout =>
      AppUiLayoutService.usesPersonalLayoutPersistence(widget.role);

  /// Ruolo per caricare ordine/stili layout (anteprima admin → globale).
  @protected
  String get layoutPersistenceRole {
    final editor = widget.layoutEditorRole;
    if (widget.isLayoutPreviewMode &&
        editor != null &&
        AppUiLayoutService.canEditGlobalLayout(editor)) {
      return editor;
    }
    return widget.role;
  }

  /// Pulsante «Vista DT» in AppBar (solo home admin).
  @protected
  bool get showDtViewButton => false;

  /// Selettore Classica / Gestopro in AppBar (home admin/DT).
  @protected
  bool get showUiViewModeSwitch => false;

  /// Apre GESTOPRO dalla barra (senza password).
  @protected
  VoidCallback? get onOpenGestoproFromBar => null;

  String get _saveLayoutActionLabel =>
      usesPersonalHomeLayout ? 'Salva' : 'Salva per tutti';

  String get _saveLayoutPrompt => usesPersonalHomeLayout
      ? 'Poi «Salva».'
      : 'Poi «Salva per tutti».';

  Map<String, HubTileStyle> get _activeStyles =>
      _reorderMode ? _styleDraft : _tileStyles;

  bool get _dtViewPreview =>
      widget.isLayoutPreviewMode && widget.layoutConfig.isDtHomeGrid;

  /// In Vista DT (anteprima) il ruolo effettivo è DT, non admin.
  @protected
  String get effectiveRole => _dtViewPreview
      ? dtPreviewEffectiveRole(
          sessionPrimaryRole: widget.layoutEditorRole ?? widget.role,
          sessionSecondaryRole: widget.secondaryRole,
        )
      : widget.role;

  bool get isAdmin => isAnyAdminRole(effectiveRole);
  bool get isAssistenteDt => normalizedRole == 'assistente_dt';
  bool get isDT => normalizedRole == 'dt';
  bool get isDipendente => effectiveRole.toLowerCase() == 'dipendente';
  bool get isDipendenteLike =>
      const {'dipendente', 'dipendenti', 'user'}.contains(normalizedRole);
  bool get isLogistica => normalizeRole(effectiveRole) == 'logistica';
  bool get isAdminGenerale => isAdminGeneraleRole(effectiveRole);
  @protected
  String get normalizedRole => normalizeRole(effectiveRole);

  Widget _wrapDtPreviewScope(Widget child) {
    if (!_dtViewPreview) return child;
    return DtViewRoleScope(
      effectiveRole: effectiveRole,
      sessionPrimaryRole: widget.layoutEditorRole ?? widget.role,
      sessionSecondaryRole: widget.secondaryRole,
      child: child,
    );
  }
  bool get _isBuiltInRole => const {
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
        'logistica',
        'user',
        'dipendente',
        'admin',
      }.contains(normalizedRole);

  /// Ruolo logistica: pagine home da [app_custom_role_pages] (Impostazioni App).
  bool get _logisticaUsesCustomPages => isLogistica;

  @protected
  bool canShowPage(
    String pageKey,
    bool fallbackAllowed, {
    bool allowCustomRoleOverride = true,
  }) {
    if (_logisticaUsesCustomPages) {
      if (!_customPermissionsLoaded) return false;
      return customAllowedPages.contains(pageKey);
    }
    if (_isBuiltInRole) return fallbackAllowed;
    if (!allowCustomRoleOverride) return false;
    if (!_customPermissionsLoaded) return false;
    return customAllowedPages.contains(pageKey);
  }

  Future<void> _loadCustomRolePermissions() async {
    customAllowedPages.clear();
    _customPermissionsLoaded = false;
    if (_isBuiltInRole && !_logisticaUsesCustomPages) {
      _customPermissionsLoaded = true;
      return;
    }
    try {
      final rows = await _supa
          .from('app_custom_role_pages')
          .select('page_key, can_view')
          .eq('role_key', normalizedRole)
          .eq('can_view', true);
      for (final row in (rows as List)) {
        final key = (row['page_key'] ?? '').toString().trim();
        if (key.isNotEmpty) customAllowedPages.add(key);
      }
    } catch (_) {
      // fallback to default visibility rules if custom permissions are unavailable
    } finally {
      _customPermissionsLoaded = true;
      if (mounted) setState(() {});
    }
  }

  void _openDipendenteView() {
    openDipendenteView(
      context,
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
    );
  }

  bool get _canPreviewDipendenteView =>
      canPreviewDipendenteView(widget.role);

  Widget _buildAppBarDipendenteViewButton(ThemeData theme) {
    if (!_canPreviewDipendenteView) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Vista dipendente',
      icon: Icon(Icons.switch_account, color: theme.colorScheme.onPrimary),
      onPressed: _openDipendenteView,
    );
  }

  void _openDtView() {
    openDtView(
      context,
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
      sessionRole: widget.role,
      sessionSecondaryRole: widget.secondaryRole,
    );
  }

  Widget _buildAppBarDtViewButton(ThemeData theme) {
    if (!showDtViewButton) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Vista DT',
      icon: Icon(Icons.assignment_ind, color: theme.colorScheme.onPrimary),
      onPressed: _openDtView,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ruolo reale di sessione (non il ruolo effettivo DT in anteprima),
    // altrimenti Home in sidebar resta bloccata sulla Vista DT.
    ClassicNavSessionCache.update(
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
      role: widget.layoutEditorRole ?? widget.role,
      secondaryRole: widget.secondaryRole,
    );
  }

  Future<void> _hubPollTick() => loadPendingApprovals();

  @override
  void initState() {
    super.initState();
    // Non chiamare ClassicNavSessionCache.update qui in modo sincrono:
    // notifier → AnimatedBuilder → setState durante build di HomePage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ClassicNavSessionCache.update(
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
        role: widget.layoutEditorRole ?? widget.role,
        secondaryRole: widget.secondaryRole,
      );
      unawaited(() async {
        await AppCopyright.ensureAccepted(context, userId: widget.userId);
        if (!mounted) return;
        await ViaggioMezzoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
        if (!mounted) return;
        await BuonoPastoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
      }());
    });
    _pendingBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      if (!hasPendingApprovals &&
          !hasPendingAssenzeRichieste &&
          !hasMyProgrammazione &&
          !hasMyProgrammazioneRfi &&
          !hasVisitaMedica &&
          !hasBachecaUnread) {
        return;
      }
      setState(() => pendingBlinkOn = !pendingBlinkOn);
    });
    HubPendingPollService.instance.attach(_hubPollTick);
    _loadCustomRolePermissions();
    _loadHomeEditorData();
    if (canEditHomeLayout) {
      unawaited(_ensureHubOrdersLoaded());
    }
    loadPendingApprovals();
    loadEmployeeProgrammazioneAlert();
    loadVisitaMedicaAlert();
    loadBachecaUnreadAlert();
    if (!widget.isLayoutPreviewMode &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(BackgroundNotifService.startForUser(widget.userId));
    }
  }

  @protected
  Future<void> loadVisitaMedicaAlert() async {
    if (!isDipendenteLike) return;
    try {
      final has = await VisiteMedicheService.hasUpcomingForCurrentUser(
        employeeFullName: widget.fullName,
      );
      if (!mounted) return;
      setState(() => hasVisitaMedica = has);
    } catch (_) {}
  }

  @protected
  Future<void> loadBachecaUnreadAlert() async {
    try {
      final has = await BachecaService.hasUnread();
      if (!mounted) return;
      setState(() => hasBachecaUnread = has);
    } catch (_) {}
  }

  @protected
  Future<void> loadEmployeeProgrammazioneAlert() async {
    if (!isDipendenteLike) return;
    try {
      final hasDlgs =
          await EmployeeProgrammazioneService.hasScheduledForCurrentUser(
        employeeFullName: widget.fullName,
      );
      final hasRfi =
          await EmployeeProgrammazioneService.hasRfiScheduledForCurrentUser(
        employeeFullName: widget.fullName,
      );
      if (!mounted) return;
      setState(() {
        hasMyProgrammazione = hasDlgs;
        hasMyProgrammazioneRfi = hasRfi;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _pendingBlinkTimer?.cancel();
    HubPendingPollService.instance.detach(_hubPollTick);
    super.dispose();
  }

  Future<void> _loadHomeEditorData({Map<String, HubTileStyle>? priorStyles}) async {
    Map<String, HubTileStyle> styles = priorStyles ?? _tileStyles;
  List<String>? order = _homeOrderKeys;
    try {
      styles = await AppUiLayoutService.loadTileStylesForLayout(
        _homeLayoutKey,
        role: layoutPersistenceRole,
      );
    } catch (e) {
      if (mounted && priorStyles == null && _tileStyles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stili Home non caricati: $e. '
              'Verifica la migration app_ui_tile_styles.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    try {
      order = await AppUiLayoutService.loadOrder(
        _homeLayoutKey,
        role: layoutPersistenceRole,
      );
    } catch (_) {}
    List<AppUiCustomHub> customHubs = _customHubs;
    try {
      customHubs = await AppUiLayoutService.loadCustomHubs();
      AppUiHubRegistry.bindCustomHubs(customHubs);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _tileStyles = styles;
      _homeOrderKeys = order;
      _customHubs = customHubs;
      _loadingHomeLayout = false;
      _reorderMode = false;
      _reorderDraft = <HomeHubTile>[];
      _styleDraft = <String, HubTileStyle>{};
      _styleDraftBaseline = <String, HubTileStyle>{};
      _pendingHiddenKeys.clear();
    });
  }

  Future<void> _ensureHubOrdersLoaded() async {
    if (_hubOrders != null || !canEditHomeLayout) return;
    try {
      final customHubs =
          await AppUiLayoutService.loadCustomHubsWithSyncedLabels();
      if (!mounted) return;
      final catalog = AdminHubCatalog.build(
        context,
        adminId: widget.userId,
        role: widget.role,
        customAllowedPages: customAllowedPages,
        showUqsaTesserino: isAdminGeneraleLikeRole(normalizedRole),
        showUqsaTesserini: isAdminGeneraleLikeRole(normalizedRole),
        homeDipendente: HomeDipendenteNavParams(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
        ),
        customHubs: customHubs,
      );
      _hubOrders = await AppUiLayoutService.loadHubOrders(
        defaultKeysByLayout: catalog.defaultKeysByLayout,
        customHubs: customHubs,
        role: widget.role,
      );
    } catch (_) {}
  }

  Future<void> _enterReorderMode(List<HomeHubTile> currentTiles) async {
    await _ensureHubOrdersLoaded();
    if (!mounted) return;
    setState(() {
      _reorderMode = true;
      _reorderDraft = List<HomeHubTile>.from(currentTiles);
      _styleDraftBaseline = Map<String, HubTileStyle>.from(_tileStyles);
      _styleDraft = Map<String, HubTileStyle>.from(_tileStyles);
    });
  }

  Future<void> _editTileStyle(HomeHubTile item) async {
    final current = _activeStyles[item.layoutKey];
    final result = await showHubTileStyleEditor(
      context: context,
      itemKey: item.layoutKey,
      defaultLabel: item.label,
      defaultIcon: item.icon,
      initial: current,
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
        layoutKey: _homeLayoutKey,
        itemKey: item.layoutKey,
        style: result,
      );
    }
  }

  void _updateTileScale(HomeHubTile item, double sizeScale) {
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
    HomeHubTile item,
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
        _homeLayoutKey,
        _reorderDraft.map((t) => t.layoutKey).toList(growable: false),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${movedLabel ?? itemKey} spostato in $targetLabel. '
          'Premi «$_saveLayoutActionLabel» per confermare.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteHomeTile(HomeHubTile item) async {
    if (_hubOrders == null) return;
    final homeLayout = _homeLayoutKey;
    final duplicateCount =
        _reorderDraft.where((t) => t.layoutKey == item.layoutKey).length;
    final existsElsewhere = AppUiLayoutService.itemExistsOnOtherLayouts(
      _hubOrders!,
      homeLayout,
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
          homeLayout,
          item.layoutKey,
        );
      });
    } else if (scope == HubTileDeleteScope.currentPageOnly) {
      setState(() {
        _reorderDraft.removeWhere((t) => t.layoutKey == item.layoutKey);
        _hubOrders = AppUiLayoutService.removeAllFromLayout(
          _hubOrders!,
          homeLayout,
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
          scope == HubTileDeleteScope.currentPageOnly
              ? '«${item.label}» rimosso dalla Home. $_saveLayoutPrompt'
              : '«${item.label}» rimosso. $_saveLayoutPrompt',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _shouldUseFreeformLayout({
    required double width,
    required bool isMobileLayout,
    required List<HomeHubTile> tiles,
  }) {
    return hubShouldUseFreeformLayout(
      isMobileLayout: isMobileLayout,
      width: width,
      reorderMode: _reorderMode,
      canEditLayout: canEditHomeLayout,
      layoutKeys: tiles.map((t) => t.layoutKey),
      activeStyles: _activeStyles,
    );
  }

  List<HomeHubTile> _sortTilesByPosition(
    List<HomeHubTile> tiles,
    Map<String, HubTileStyle> styles,
  ) {
    return hubSortItemsByPosition(tiles, styles, (t) => t.layoutKey);
  }

  Future<void> _saveHomeLayout(List<HomeHubTile> currentTiles) async {
    if (!await ensureCanPersist(context, widget.role)) return;
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
    var tilesForOrder = _reorderMode ? _reorderDraft : currentTiles;
    if (mergedStyles.values.any((s) => s.hasCustomPosition)) {
      tilesForOrder = _sortTilesByPosition(tilesForOrder, mergedStyles);
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
    try {
      if (usesPersonalHomeLayout) {
        await _ensureHubOrdersLoaded();
        if (!mounted) return;
        _hubOrders ??= HubLayoutOrders(<String, List<String>>{
          _homeLayoutKey: keys,
        });
        _hubOrders!.setKeysFor(_homeLayoutKey, keys);
        await AppUiLayoutService.savePersonalHomeLayout(
          layoutKey: _homeLayoutKey,
          itemKeys: keys,
          styles: stylesToPersist,
          gridPlacements: gridToPersist,
          hubOrders: _hubOrders!,
          hiddenKeysToAdd: _pendingHiddenKeys,
        );
        _pendingHiddenKeys.clear();
      } else {
        if (_hubOrders != null) {
          _hubOrders!.setKeysFor(_homeLayoutKey, keys);
          for (final key in _pendingHiddenKeys) {
            await AppUiLayoutService.hideItemKey(key);
          }
          _pendingHiddenKeys.clear();
          await AppUiLayoutService.saveHubOrders(_hubOrders!);
        }
        await AppUiLayoutService.saveOrder(
          layoutKey: _homeLayoutKey,
          itemKeys: keys,
        );
        await AppUiLayoutService.saveTileStyles(stylesToPersist);
        await AppUiLayoutService.saveTileGridPlacements(
          layoutKey: _homeLayoutKey,
          placements: gridToPersist,
        );
      }
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
        _homeOrderKeys = keys;
        _tileStyles = stylesWithGrid;
        _reorderMode = false;
        _reorderDraft = <HomeHubTile>[];
        _styleDraft = <String, HubTileStyle>{};
        _styleDraftBaseline = <String, HubTileStyle>{};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usesPersonalHomeLayout
                ? 'Home: layout salvato solo per il tuo account.'
                : 'Home: ordine, posizioni e colori salvati per tutti gli utenti.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      await _loadHomeEditorData(priorStyles: mergedStyles);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Errore salvataggio Home: '
            '${AppUiLayoutService.formatPersistError(e)}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  List<HomeHubTile> _customFolderTiles() {
    final onThisHome = (_homeOrderKeys ?? const <String>[]).toSet();
    return [
      for (final hub in _customHubs)
        if (onThisHome.contains(hub.launcherKey))
          HomeHubTile(
            layoutKey: hub.launcherKey,
            icon: Icons.folder_outlined,
            label: hub.label,
            onTap: () => _openHomeFolder(hub),
          ),
    ];
  }

  HomeDipendenteNavParams get _homeDipendenteParams => HomeDipendenteNavParams(
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
      );

  Future<void> _openHomeFolder(AppUiCustomHub hub) async {
    final page = useMobileUi(context)
        ? AdminCustomHubMobilePage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: widget.userId,
            role: widget.role,
            initialHub: hub,
            homeDipendente: _homeDipendenteParams,
          )
        : AdminCustomHubPage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: widget.userId,
            role: widget.role,
            initialHub: hub,
            homeDipendente: _homeDipendenteParams,
          );
    await FuturisticNavigation.pushPage<void>(
      context,
      page: page,
      title: hub.label,
    );
    if (mounted) await _loadHomeEditorData();
  }

  Future<void> _createHomeFolder() async {
    await promptCreateCustomHubPage(
      context,
      userId: widget.userId,
      role: widget.role,
      originLayoutKey: _homeLayoutKey,
      asSubfolder: true,
      homeDipendente: _homeDipendenteParams,
    );
    if (mounted) await _loadHomeEditorData();
  }

  List<String> _homeOrderKeysForCurrentRole() =>
      widget.layoutConfig.orderKeys(_homeOrderKeys);

  List<HomeHubTile> _applyHomeOrder(List<HomeHubTile> tiles) {
    if (_loadingHomeLayout) return tiles;
    return AppUiLayoutService.applyOrder(
      items: tiles,
      savedOrder: _homeOrderKeysForCurrentRole(),
      keyOf: (t) => t.layoutKey,
    );
  }

  @protected
  Future<void> loadPendingApprovals({bool force = false}) async {
    var trainAereoPending = false;
    var trainAereoCount = 0;

    if (isDT) {
      trainAereoCount = await HubPendingPollService.instance.trainAereoPendingCount(
        _supa,
        userId: widget.userId,
        force: force,
      );
      trainAereoPending = trainAereoCount > 0;
    }

    var assenzePending = false;
    if (canManageDipendenteAssenze(normalizedRole)) {
      try {
        final count = await HubPendingPollService.instance.assenzePendingCount(
          _supa,
          force: force,
        );
        assenzePending = count > 0;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      hasPendingApprovals = trainAereoPending;
      _pendingApprovalsCount = trainAereoCount;
      hasPendingAssenzeRichieste = assenzePending;
      if (!hasPendingApprovals && !hasPendingAssenzeRichieste) {
        pendingBlinkOn = true;
      }
    });
  }

  /// Pulsante extra sotto la griglia (es. GESTOPRO su admin home).
  @protected
  Widget? buildAdminHomeFooter(BuildContext context) => null;

  void _syncClassicSidebarSubs(List<HomeHubTile> tiles) {
    ClassicNavSessionCache.setActiveSection(ClassicNavSection.home);
    ClassicNavSubItemsCache.updateHome([
      for (final t in tiles)
        FuturisticNavSubItem(
          key: t.layoutKey,
          icon: t.icon,
          label: t.label,
          accentColor: t.color,
          onTap: t.onTap,
        ),
    ]);
  }

  HomeHubTile navTile({
    required String layoutKey,
    required IconData icon,
    required String label,
    required Widget mobilePage,
    required Widget desktopPage,
    Color? color,
    VoidCallback? onClosed,
  }) {
    final mobile = useMobileUi(context);
    return HomeHubTile(
      layoutKey: layoutKey,
      icon: icon,
      label: label,
      color: color,
      destination: mobile ? mobilePage : null,
      onClosed: onClosed,
      onTap: () {
        if (!mobile) {
          FuturisticNavigation.pushPage(
            context,
            page: _wrapDtPreviewScope(desktopPage),
            title: label,
            activeSubKey: layoutKey,
            onAfter: onClosed,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tiles = [
      ...buildRoleTiles(theme),
      ..._customFolderTiles(),
    ];
    final orderedTiles = _applyHomeOrder(tiles);
    final displayTiles =
        _reorderMode ? _reorderDraft : orderedTiles;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _syncClassicSidebarSubs(displayTiles);
    });

    final isMobileLayout = useMobileUi(context);
    final int crossAxis;
    const childAspectRatio = HubTileGridConfig.cellAspectRatio;
    final double gridSpacing;
    if (_isAdminHomeGrid) {
      gridSpacing = 12;
      crossAxis = cronosHubCrossAxisCount(
        context: context,
        itemCount: displayTiles.length,
        maxTileWidth: 200,
      );
    } else if (_isDtHomeGrid) {
      gridSpacing = 12;
      crossAxis = cronosHubCrossAxisCount(
        context: context,
        itemCount: displayTiles.length,
        maxTileWidth: 180,
      );
    } else {
      gridSpacing = 16;
      crossAxis = cronosHubCrossAxisCount(
        context: context,
        itemCount: displayTiles.length,
        maxTileWidth: 240,
      );
    }

    Widget buildTileCard(HomeHubTile tile, {bool fillCell = false}) {
      final isPendingTile = tile.layoutKey == 'richieste_da_approvare';
      return HomeHubCard(
        item: tile,
        homeLayoutKey: _homeLayoutKey,
        tileStyle: _activeStyles[tile.layoutKey],
        badgeCount: isPendingTile ? _pendingApprovalsCount : null,
        compact: _useCompactHomeGrid,
        fillCell: fillCell,
        reorderMode: _reorderMode,
        canEditLayout: canEditHomeLayout,
        onHoldReorder: () => _enterReorderMode(orderedTiles),
        onEditTileStyle: canEditHomeLayout ? _editTileStyle : null,
        onResizeTileStyle: canEditHomeLayout ? _updateTileScale : null,
        onMoveToLayout: canEditHomeLayout ? _moveTileToLayout : null,
        onDeleteTile: canEditHomeLayout ? _deleteHomeTile : null,
      );
    }

    Widget buildGrid({required double width, double? height}) {
      final useFreeform = _shouldUseFreeformLayout(
        width: width,
        isMobileLayout: isMobileLayout,
        tiles: displayTiles,
      );

      var cross = crossAxis;
      if (_isDtHomeGrid && !isMobileLayout) {
        cross = width >= 1200
            ? 6
            : (width >= 900 ? 4 : (width >= 600 ? 3 : 2));
      }
      if (_isAdminHomeGrid && !isMobileLayout && width >= 720) {
        cross = displayTiles.length.clamp(1, 5);
      }

      if (useFreeform) {
        return CronosFreeformHubCanvas(
          itemCount: displayTiles.length,
          crossAxisCount: cross,
          childAspectRatio: childAspectRatio,
          spacing: gridSpacing,
          maxCanvasHeight: height,
          reorderMode: _reorderMode,
          layoutKeyForIndex: (index) => displayTiles[index].layoutKey,
          styleForKey: (key) => _activeStyles[key],
          scaleForIndex: (index) =>
              _activeStyles[displayTiles[index].layoutKey]?.sizeScale ?? 1.0,
          onGridCellChanged: canEditHomeLayout
              ? (key, col, row, colSpan, rowSpan) {
                  final tile = displayTiles.firstWhere(
                    (t) => t.layoutKey == key,
                  );
                  _updateTileGrid(tile, col, row, colSpan, rowSpan);
                }
              : null,
          itemBuilder: (context, index) => buildTileCard(
            displayTiles[index],
            fillCell: true,
          ),
        );
      }

      final useAdaptiveGrid = _reorderMode &&
          canEditHomeLayout &&
          !isMobileLayout &&
          width >= 600;

      if (_useCompactHomeGrid && !isMobileLayout && useAdaptiveGrid) {
        var adaptiveCross = cross;
        if (_isDtHomeGrid) {
          adaptiveCross = width >= 1200
              ? 6
              : (width >= 900 ? 4 : (width >= 600 ? 3 : 2));
        }
        return CronosAdaptiveHubGrid(
          crossAxisCount: adaptiveCross,
          childAspectRatio: childAspectRatio,
          spacing: gridSpacing,
          itemCount: displayTiles.length,
          reorderMode: _reorderMode,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final next = List<HomeHubTile>.from(_reorderDraft);
              final item = next.removeAt(oldIndex);
              next.insert(newIndex, item);
              _reorderDraft = next;
            });
          },
          scaleForIndex: (index) =>
              _activeStyles[displayTiles[index].layoutKey]?.sizeScale ?? 1.0,
          itemBuilder: (context, index) => buildTileCard(
            displayTiles[index],
            fillCell: true,
          ),
        );
      }

      return GridView.builder(
        shrinkWrap: _useCompactHomeGrid,
        physics: _useCompactHomeGrid
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: displayTiles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          mainAxisSpacing: gridSpacing,
          crossAxisSpacing: gridSpacing,
          childAspectRatio: childAspectRatio,
        ),
        itemBuilder: (context, index) => buildTileCard(
          displayTiles[index],
          fillCell: true,
        ),
      );
    }

    Widget buildCompactHomeBody() {
      if (isMobileLayout) {
        return HomeHubMobileList(
          tiles: displayTiles,
          pendingCount: _pendingApprovalsCount,
          tileStyles: _activeStyles,
          reorderMode: _reorderMode,
          canEditLayout: canEditHomeLayout,
          onHoldReorder: () => _enterReorderMode(orderedTiles),
          onEditTileStyle: canEditHomeLayout ? _editTileStyle : null,
          onReorder: _reorderMode
              ? (oldIndex, newIndex) {
                  setState(() {
                    final next = List<HomeHubTile>.from(_reorderDraft);
                    if (newIndex > oldIndex) newIndex--;
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);
                    _reorderDraft = next;
                  });
                }
              : null,
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          const pad = EdgeInsets.fromLTRB(8, 4, 8, 8);
          final innerW = (w - pad.horizontal).clamp(0.0, w);
          final innerH = (h - pad.vertical).clamp(0.0, h);
          final useFreeform = _shouldUseFreeformLayout(
            width: innerW,
            isMobileLayout: isMobileLayout,
            tiles: displayTiles,
          );
          if (useFreeform) {
            return Padding(
              padding: pad,
              child: SizedBox(
                width: innerW,
                height: innerH,
                child: buildGrid(width: innerW, height: innerH),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _compactMaxWidth,
                ),
                child: buildGrid(width: w),
              ),
            ),
          );
        },
      );
    }

    return _wrapDtPreviewScope(
      Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: widget.isLayoutPreviewMode
            ? Text(
                widget.layoutConfig.isDtHomeGrid
                    ? 'Vista DT (anteprima)'
                    : 'Anteprima',
              )
            : WelcomeAppBarTitle(
                fullName: widget.fullName,
                username: widget.username,
                onAvatarTap:
                    _canPreviewDipendenteView ? _openDipendenteView : null,
              ),
        actions: [
          if (showUiViewModeSwitch &&
              shouldShowClassicRail(context) &&
              !useMobileUi(context)) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: UiViewModeSwitch(
                  gestoproSelected: false,
                  lightOnDark: true,
                  compact: false,
                  onSelectGestopro: onOpenGestoproFromBar,
                ),
              ),
            ),
          ],
          if (!widget.isLayoutPreviewMode) ...[
            // Su viewport stretto Logout/Vista DT stanno nel menu ⋮.
            if (shouldShowClassicRail(context)) ...[
              _buildAppBarDipendenteViewButton(theme),
              _buildAppBarDtViewButton(theme),
            ],
          ],
          if (_canCreateHomeFolders &&
              !_reorderMode &&
              !_loadingHomeLayout)
            IconButton(
              tooltip: 'Nuova cartella',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createHomeFolder,
            ),
          if (canEditHomeLayout &&
              !_reorderMode &&
              !_loadingHomeLayout &&
              shouldShowClassicRail(context))
            IconButton(
              tooltip: 'Riordina pulsanti (3 sec. su un tile)',
              icon: const Icon(Icons.reorder),
              onPressed: () => _enterReorderMode(orderedTiles),
            ),
          if (_reorderMode) ...[
            TextButton(
              onPressed: () => setState(() {
                _reorderMode = false;
                _reorderDraft = <HomeHubTile>[];
                _styleDraft = <String, HubTileStyle>{};
                _styleDraftBaseline = <String, HubTileStyle>{};
              }),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => _saveHomeLayout(orderedTiles),
              child: Text(_saveLayoutActionLabel),
            ),
          ],
          NotificationBell(
              userId: widget.userId, iconColor: theme.colorScheme.onPrimary),
          if (shouldShowClassicRail(context))
            IconButton(
              tooltip: 'Video',
              icon: const Icon(Icons.video_library_outlined),
              onPressed: () => VideoGalleryNavigation.open(
                context,
                role: widget.role,
              ),
            ),
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await loadPendingApprovals(force: true);
              await loadEmployeeProgrammazioneAlert();
              await loadVisitaMedicaAlert();
              await loadBachecaUnreadAlert();
              await _loadHomeEditorData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Home aggiornata')),
              );
            },
          ),
          if (widget.isLayoutPreviewMode)
            IconButton(
              tooltip: 'Torna alla home admin',
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                ClassicNavSessionCache.setActiveSection(ClassicNavSection.home);
                Navigator.of(context).pop();
              },
            )
          else if (shouldShowClassicRail(context))
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () => unawaited(performAppLogout(context)),
            ),
        ],
      )),
      body: PageWithTopLogo(
        showLogo: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isLayoutPreviewMode && !_reorderMode)
              Material(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'Anteprima: riordina i pulsanti e usa «Salva per tutti» '
                    'per applicare il layout a tutti gli utenti del ruolo.',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (isAdminVistaRole(widget.role) && !widget.isLayoutPreviewMode)
              Material(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'Account in sola vista: puoi consultare tutto come un admin '
                    'generale, ma non puoi salvare modifiche. Contatta un amministratore.',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
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
                    '$_saveLayoutPrompt',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            if (_reorderMode && canEditHomeLayout)
              CronosHubCrossLayoutDropBar(
                currentLayoutKey: _homeLayoutKey,
                onAcceptItemKey: _moveTileToLayout,
              ),
            Expanded(
              child: _loadingHomeLayout
                  ? const Center(child: CircularProgressIndicator())
                  : _useCompactHomeGrid
                      ? buildCompactHomeBody()
                      : isMobileLayout
                          ? HomeHubMobileList(
                              tiles: displayTiles,
                              pendingCount: _pendingApprovalsCount,
                              tileStyles: _activeStyles,
                              reorderMode: _reorderMode,
                              canEditLayout: canEditHomeLayout,
                              onHoldReorder: () =>
                                  _enterReorderMode(orderedTiles),
                              onEditTileStyle: canEditHomeLayout
                                  ? _editTileStyle
                                  : null,
                              onReorder: _reorderMode
                                  ? (oldIndex, newIndex) {
                                      setState(() {
                                        final next = List<HomeHubTile>.from(
                                            _reorderDraft);
                                        if (newIndex > oldIndex) {
                                          newIndex--;
                                        }
                                        final item = next.removeAt(oldIndex);
                                        next.insert(newIndex, item);
                                        _reorderDraft = next;
                                      });
                                    }
                                  : null,
                            )
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    buildGrid(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                ),
                              ),
                            ),
            ),
          ],
        ),
            if ((_isAdminHomeGrid || _isDtHomeGrid) &&
                buildAdminHomeFooter(context) != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: buildAdminHomeFooter(context)!,
              ),
          ],
        ),
      ),
    ),
    );
  }
}

class HomeHubTile {
  final String layoutKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? destination;
  final VoidCallback? onClosed;

  HomeHubTile({
    required this.layoutKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.destination,
    this.onClosed,
  });
}

class HomeHubCard extends StatelessWidget {
  final HomeHubTile item;
  final HubTileStyle? tileStyle;
  final int? badgeCount;
  final bool compact;
  final bool fillCell;
  final bool reorderMode;
  final bool canEditLayout;
  final VoidCallback? onHoldReorder;
  final void Function(HomeHubTile item)? onEditTileStyle;
  final void Function(HomeHubTile item, double sizeScale)? onResizeTileStyle;
  final void Function(String itemKey, String targetLayoutKey)? onMoveToLayout;
  final void Function(HomeHubTile item)? onDeleteTile;
  final String homeLayoutKey;

  const HomeHubCard({super.key, 
    required this.item,
    required this.homeLayoutKey,
    this.tileStyle,
    this.badgeCount,
    this.compact = false,
    this.fillCell = false,
    this.reorderMode = false,
    this.canEditLayout = false,
    this.onHoldReorder,
    this.onEditTileStyle,
    this.onResizeTileStyle,
    this.onMoveToLayout,
    this.onDeleteTile,
  });

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (fillCell) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cellScale = HubTileStyleMetrics.cellScaleFromConstraints(
            constraints,
          );
          return _buildCard(context, theme, cellScale: cellScale);
        },
      );
    }
    return _buildCard(context, theme);
  }

  Widget _buildCard(
    BuildContext context,
    ThemeData theme, {
    double cellScale = 1.0,
  }) {
    final metrics = HubTileStyleMetrics.fromStyle(
      style: tileStyle,
      fillCell: fillCell,
      cellScale: cellScale,
    );
    final rawLabel = tileStyle?.effectiveLabel(item.label) ?? item.label;
    final label = rawLabel.trim().isEmpty ? item.label : rawLabel.trim();
    final bg = tileStyle?.backgroundColor ?? theme.colorScheme.surface;
    final blinkColor = item.color;
    final iconColor = tileStyle?.iconColor ??
        _readableAccentColor(
          preferred: blinkColor,
          background: bg,
          fallback: blinkColor ?? theme.colorScheme.primary,
        );
    final textColor = tileStyle?.textColor ??
        (blinkColor == Colors.red
            ? Colors.red
            : (bg.computeLuminance() < 0.45
                ? Colors.white
                : theme.colorScheme.onSurface));
    final radius = BorderRadius.circular(compact ? 12 : 14);
    final closedColor = bg;
    final canStyle =
        reorderMode && canEditLayout && onEditTileStyle != null;
    final canMove = reorderMode &&
        canEditLayout &&
        onMoveToLayout != null &&
        !kHubNonRelocatableKeys.contains(item.layoutKey);
    final canDelete = reorderMode && canEditLayout && onDeleteTile != null;
    final canResize = reorderMode &&
        canEditLayout &&
        fillCell &&
        onResizeTileStyle != null;
    final inFreeformLayout = HubGridDragScope.maybeOf(context) != null;

    final tap = reorderMode ? null : item.onTap;

    final displayIcon = reorderMode
        ? Icons.drag_indicator
        : (tileStyle?.effectiveIcon(item.icon) ?? item.icon);

    Widget cardContent({VoidCallback? onTap}) {
      return Cronos3dSurface(
        color: tileStyle?.backgroundColor,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    wrapFreeformDragIcon(
                      context: context,
                      icon: Icon(
                        displayIcon,
                        size: metrics.iconSize,
                        color: iconColor,
                      ),
                    ),
                    if (badgeCount != null && badgeCount! > 0)
                      Positioned(
                        right: -10,
                        top: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeCount! > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: metrics.gapIconTitle),
                if (fillCell)
                  Expanded(
                    child: HubTileAutoFitText(
                      text: label,
                      maxLines: 3,
                      minFontSize: 6,
                      maxFontSize: metrics.titleSize.clamp(6.0, 50.0),
                      style: metrics.resolveTitleStyle(
                        TextStyle(
                          fontWeight:
                              compact ? FontWeight.w700 : FontWeight.w600,
                          height: 1.15,
                        ),
                        textColor,
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
                      TextStyle(
                        fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                      ),
                      textColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget body = HubTileScaledShell(
      fillCell: fillCell,
      child: cardContent(onTap: tap),
    );
    Widget sized = fillCell ? SizedBox.expand(child: body) : body;

    if (canResize) {
      sized = HubTileCornerResizeOverlay(
        enabled: true,
        sizeScale: tileStyle?.sizeScale ?? 1.0,
        onScaleChanged: (scale) => onResizeTileStyle!(item, scale),
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
                currentLayoutKey: homeLayoutKey,
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

    Widget content;
    if (item.destination != null && useMobileUi(context) && !reorderMode) {
      final mobileNav = MobileOpenContainer(
        onClosed: item.onClosed,
        closedColor: closedColor,
        closedBorderRadius: radius,
        closedBuilder: (_, open) => cardContent(onTap: open),
        destination: item.destination!,
      );
      content = fillCell ? SizedBox.expand(child: mobileNav) : mobileNav;
    } else if (fillCell) {
      content = sized;
    } else {
      content = cardContent(onTap: tap);
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

class HomeHubMobileList extends StatelessWidget {
  final List<HomeHubTile> tiles;
  final int pendingCount;
  final Map<String, HubTileStyle> tileStyles;
  final bool reorderMode;
  final bool canEditLayout;
  final VoidCallback? onHoldReorder;
  final void Function(HomeHubTile item)? onEditTileStyle;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const HomeHubMobileList({super.key, 
    required this.tiles,
    required this.pendingCount,
    this.tileStyles = const <String, HubTileStyle>{},
    this.reorderMode = false,
    this.canEditLayout = false,
    this.onHoldReorder,
    this.onEditTileStyle,
    this.onReorder,
  });

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

  Widget _buildMobileRow(BuildContext context, HomeHubTile tile) {
    final theme = Theme.of(context);
    final style = tileStyles[tile.layoutKey];
    final scale = style?.sizeScale ?? 1.0;
    final metrics = HubTileStyleMetrics.fromStyle(style: style, fillCell: false);
    final rawLabel = style?.effectiveLabel(tile.label) ?? tile.label;
    final label = rawLabel.trim().isEmpty ? tile.label : rawLabel.trim();
    final bg = style?.backgroundColor ?? theme.colorScheme.surface;
    final iconColor = style?.iconColor ??
        _readableAccentColor(
          preferred: style?.iconColor ?? tile.color,
          background: bg,
          fallback: tile.color ?? theme.colorScheme.primary,
        );
    final textColor = style?.textColor ??
        (tile.color == Colors.red
            ? Colors.red
            : _readableAccentColor(
                preferred: style?.textColor,
                background: bg,
                fallback: theme.colorScheme.onSurface,
              ));
    const radius = BorderRadius.all(Radius.circular(12));
    final badgeCount = tile.layoutKey == 'richieste_da_approvare' && pendingCount > 0
        ? pendingCount
        : null;
    final canStyle =
        reorderMode && canEditLayout && onEditTileStyle != null;

    final displayIcon = reorderMode
        ? Icons.drag_indicator
        : (style?.effectiveIcon(tile.icon) ?? tile.icon);

    Widget listContent({VoidCallback? onTap}) {
      return Cronos3dSurface(
        color: style?.backgroundColor,
        borderRadius: radius,
        onTap: reorderMode ? null : onTap,
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14 * scale,
            vertical: 10 * scale,
          ),
          minVerticalPadding: 0,
          visualDensity: VisualDensity.standard,
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                displayIcon,
                color: iconColor,
                size: 24 * scale,
              ),
              if (badgeCount != null)
                Positioned(
                  right: -8,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: metrics.resolveTitleStyle(
              theme.textTheme.titleMedium ?? const TextStyle(),
              textColor,
            ).copyWith(height: 1.2),
          ),
          trailing: canStyle
              ? CronosHubTileStyleButton(
                  onPressed: () => onEditTileStyle!(tile),
                )
              : (reorderMode
                  ? null
                  : Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.outline,
                    )),
          onTap: reorderMode ? null : onTap,
        ),
      );
    }

    Widget row;
    if (tile.destination != null && useMobileUi(context) && !reorderMode) {
      row = MobileOpenContainer(
        onClosed: tile.onClosed,
        closedColor: bg,
        closedBorderRadius: radius,
        closedBuilder: (_, open) => listContent(onTap: open),
        destination: tile.destination!,
      );
    } else {
      row = listContent(onTap: tile.onTap);
    }

    if (reorderMode) {
      return CronosJiggleMode(active: true, child: row);
    }
    if (canEditLayout && onHoldReorder != null) {
      return CronosHoldToReorderDetector(
        enabled: true,
        onHoldComplete: onHoldReorder!,
        child: row,
      );
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    if (reorderMode && onReorder != null) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        buildDefaultDragHandles: false,
        itemCount: tiles.length,
        // ignore: deprecated_member_use
        onReorder: onReorder!,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>(tile.layoutKey),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildMobileRow(context, tile),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: tiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _buildMobileRow(context, tiles[index]),
    );
  }
}
