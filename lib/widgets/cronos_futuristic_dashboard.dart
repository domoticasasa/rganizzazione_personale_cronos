import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../services/app_ui_layout_service.dart';
import '../hub/dashboard_hub_nav_items.dart';
import '../services/assenza_richieste_pending_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/video_gallery_navigation.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../widgets/cronos_hold_to_reorder.dart';
import '../widgets/cronos_adaptive_hub_grid.dart';
import '../widgets/cronos_freeform_hub_canvas.dart';
import '../widgets/cronos_hub_cross_layout_move.dart';
import '../widgets/cronos_hub_delete_tile_button.dart';
import '../widgets/hub_tile_style_editor.dart';
import '../widgets/hub_tile_corner_resize.dart';
import 'cronos_futuristic_tile.dart';
import 'futuristic/futuristic_footer.dart';
import 'futuristic/futuristic_nav_section.dart';
import 'futuristic/futuristic_nav_sub_item.dart';
import 'futuristic/futuristic_sidebar.dart';
import 'futuristic/futuristic_topbar.dart';
import 'futuristic/futuristic_hub_chip.dart';
import 'futuristic/gestopro_click_sound_scope.dart';
import 'futuristic/gestopro_nav_sub_items_cache.dart';
import 'futuristic/neon_card.dart';
import 'futuristic/particles_background.dart';

export 'cronos_futuristic_tile.dart';

/// Dashboard CRONOS Nexus — command interface blu elettrico.
class CronosFuturisticDashboard extends StatefulWidget {
  const CronosFuturisticDashboard({
    super.key,
    required this.tiles,
    required this.userDisplayName,
    required this.username,
    required this.userId,
    required this.roleLabel,
    required     this.onSwitchToClassic,
    this.switchToClassicTooltip,
    this.onToggleClassicLayout,
    this.onAdminNewPage,
    this.onAdminReorder,
    this.onOpenHome,
    this.onOpenDashboard,
    this.onOpenNotifiche,
    this.onOpenAlert,
    this.onOpenImpostazioni,
    this.onOpenSupport,
    this.onOpenDipendente,
    this.onOpenDtView,
    this.hubAssenzeBlinkKeys = const <String>{},
    this.hubAssenzeBlinkOn = true,
    this.reorderMode = false,
    this.canEditLayout = false,
    this.onCancelReorder,
    this.onSaveReorder,
    this.onReorder,
    this.onDeleteTile,
    this.onEditTileStyle,
    this.onMoveToLayout,
    this.onResizeTile,
    this.onGridCellChanged,
    this.dashboardLayoutKey = AppUiLayoutService.layoutDashboardAdminFuturistic,
    this.activeNavSection = FuturisticNavSection.dashboard,
    this.useLocalNavSubItemsOnly = false,
  });

  final List<CronosFuturisticTile> tiles;
  final String userDisplayName;
  final String username;
  final int userId;
  final String roleLabel;
  final VoidCallback onSwitchToClassic;
  final String? switchToClassicTooltip;
  /// Menu impostazioni: passa alla griglia classica (solo Command Center).
  final VoidCallback? onToggleClassicLayout;
  final VoidCallback? onAdminNewPage;
  final VoidCallback? onAdminReorder;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onOpenNotifiche;
  final VoidCallback? onOpenAlert;
  final VoidCallback? onOpenImpostazioni;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenDipendente;
  final VoidCallback? onOpenDtView;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;
  final bool reorderMode;
  final bool canEditLayout;
  final VoidCallback? onCancelReorder;
  final VoidCallback? onSaveReorder;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(String layoutKey)? onDeleteTile;
  final void Function(String layoutKey)? onEditTileStyle;
  final void Function(String itemKey, String targetLayoutKey)? onMoveToLayout;
  final void Function(String layoutKey, double sizeScale)? onResizeTile;
  final void Function(
    String layoutKey,
    int col,
    int row,
    int colSpan,
    int rowSpan,
  )? onGridCellChanged;
  final String dashboardLayoutKey;
  final FuturisticNavSection activeNavSection;
  /// Solo moduli della pagina corrente (es. home DT), senza cache admin.
  final bool useLocalNavSubItemsOnly;

  @override
  State<CronosFuturisticDashboard> createState() =>
      _CronosFuturisticDashboardState();
}

class _CronosFuturisticDashboardState extends State<CronosFuturisticDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String _haystack(CronosFuturisticTile tile) =>
      '${tile.layoutKey} ${tile.label}'.toLowerCase();

  Color _colorFor(CronosFuturisticTile tile) {
    if (tile.accentColor != null) {
      return Color.lerp(
        tile.accentColor,
        CronosFuturisticTheme.electricBright,
        0.2,
      )!;
    }
    final hay = _haystack(tile);
    if (hay.contains('pernott')) return CronosFuturisticTheme.neonGreen;
    if (hay.contains('tren')) return CronosFuturisticTheme.neonCyan;
    if (hay.contains('aer')) return const Color(0xFFFF6B8A);
    if (hay.contains('visite') || hay.contains('medic')) {
      return CronosFuturisticTheme.neonMagenta;
    }
    if (hay.contains('formaz') || hay.contains('dlgs')) {
      return CronosFuturisticTheme.neonPurple;
    }
    if (hay.contains('rfi')) return const Color(0xFF6B8AFF);
    if (hay.contains('carbur') || hay.contains('riforn')) {
      return CronosFuturisticTheme.neonTeal;
    }
    if (hay.contains('logistic')) return CronosFuturisticTheme.neonGold;
    if (hay.contains('uqsa') || hay.contains('osa') || hay.contains('qsa')) {
      return CronosFuturisticTheme.electricBright;
    }
    if (hay.contains('personale') || hay.contains('admin')) {
      return CronosFuturisticTheme.cobaltBlue;
    }
    return CronosFuturisticTheme.electricBright;
  }

  VoidCallback? _resolveOpenDipendente() {
    if (widget.reorderMode) return null;
    if (widget.onOpenDipendente != null) return widget.onOpenDipendente;
    if (!canPreviewDipendenteView(widget.roleLabel)) return null;
    return () => openDipendenteView(
          context,
          userId: widget.userId,
          username: widget.username,
          fullName: widget.userDisplayName,
        );
  }

  List<FuturisticNavSubItem> _navSubItems() {
    return [
      for (final tile in widget.tiles)
        FuturisticNavSubItem.fromTile(
          tile,
          accentColor: _colorFor(tile),
        ),
    ];
  }

  bool get _hasQuickSettings =>
      !widget.reorderMode &&
      (widget.onAdminNewPage != null ||
          widget.onAdminReorder != null ||
          widget.onToggleClassicLayout != null);

  Future<void> _showSettingsMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + box.size.height,
        box.size.width,
        box.size.height,
      ),
      Offset.zero & overlay.size,
    );
    final items = <PopupMenuEntry<String>>[
      if (widget.onAdminNewPage != null)
        const PopupMenuItem(
          value: 'new',
          child: Text('Nuova cartella', style: TextStyle(color: Colors.white)),
        ),
      if (widget.onAdminReorder != null && !widget.reorderMode)
        const PopupMenuItem(
          value: 'reorder',
          child: Text('Riordina moduli', style: TextStyle(color: Colors.white)),
        ),
      if (!widget.reorderMode && widget.onToggleClassicLayout != null)
        const PopupMenuItem(
          value: 'classic',
          child: Text('Vista classica', style: TextStyle(color: Colors.white)),
        ),
    ];
    if (items.isEmpty) return;
    final pick = await showMenu<String>(
      context: context,
      color: const Color(0xFF061020),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: CronosFuturisticTheme.electricBright.withValues(alpha: 0.4),
        ),
      ),
      position: position,
      items: items,
    );
    switch (pick) {
      case 'new':
        widget.onAdminNewPage?.call();
      case 'reorder':
        widget.onAdminReorder?.call();
      case 'classic':
        widget.onToggleClassicLayout?.call();
    }
  }

  Widget _buildReorderToolbar() {
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
              'Angoli = ridimensiona (come versione classica). '
              'Tile grandi = più celle sulla griglia. '
              'Palette = colori e nome. '
              '✕ elimina. ⇄ sposta pagina. Poi «Salva per tutti».',
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
            onPressed: widget.onCancelReorder,
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
            onPressed: widget.onSaveReorder,
            child: const Text('Salva per tutti'),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderOverlay(BuildContext context, CronosFuturisticTile tile) {
    final inFreeform = HubGridDragScope.maybeOf(context) != null;
    final canMove = widget.canEditLayout &&
        widget.onMoveToLayout != null &&
        !kHubNonRelocatableKeys.contains(tile.layoutKey);
    final canDelete =
        widget.canEditLayout && widget.onDeleteTile != null;
    final canStyle =
        widget.canEditLayout && widget.onEditTileStyle != null;

    if (!inFreeform && !canMove && !canDelete && !canStyle) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (inFreeform)
          Positioned(
            top: 2,
            left: 2,
            child: wrapFreeformDragIcon(
              context: context,
              icon: const FuturisticHubDragChip(
                icon: Icons.open_with,
                size: 20,
              ),
            ),
          ),
        if (canMove || canDelete || canStyle)
          Positioned(
            top: 2,
            right: 2,
            left: inFreeform ? 36 : 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canStyle)
                  FuturisticHubChip(
                    child: CronosHubTileStyleButton(
                      onPressed: () => widget.onEditTileStyle!(tile.layoutKey),
                    ),
                  ),
                if (canDelete)
                  FuturisticHubChip(
                    child: CronosHubDeleteTileButton(
                      onPressed: () => widget.onDeleteTile!(tile.layoutKey),
                    ),
                  ),
                if (canMove) ...[
                  FuturisticHubChip(
                    child: CronosHubCrossLayoutDragHandle(
                      itemKey: tile.layoutKey,
                      label: tile.label,
                    ),
                  ),
                  FuturisticHubChip(
                    child: CronosHubMoveToLayoutButton(
                      currentLayoutKey: widget.dashboardLayoutKey,
                      itemKey: tile.layoutKey,
                      onMoveTo: (target) =>
                          widget.onMoveToLayout!(tile.layoutKey, target),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    CronosFuturisticTile tile, {
    bool reordering = false,
  }) {
    final color = AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: tile.layoutKey,
      blinkKeys: widget.hubAssenzeBlinkKeys,
      blinkOn: widget.hubAssenzeBlinkOn,
      fallback: _colorFor(tile),
    );
    final inFreeformLayout = HubGridDragScope.maybeOf(context) != null;
    final card = NeonCard(
      title: tile.label,
      subtitle: tile.subtitle,
      icon: reordering ? Icons.drag_indicator : tile.icon,
      color: color,
      tileStyle: tile.tileStyle,
      onTap: reordering ? null : tile.onTap,
    );

    if (!reordering) return card;

    Widget body = Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (inFreeformLayout)
          Positioned.fill(
            child: wrapFreeformDragTarget(context: context, child: card),
          )
        else
          card,
        _buildReorderOverlay(context, tile),
      ],
    );

    if (widget.canEditLayout &&
        widget.onResizeTile != null &&
        !inFreeformLayout) {
      final scale = tile.tileStyle?.sizeScale ?? 1.0;
      body = HubTileCornerResizeOverlay(
        enabled: true,
        sizeScale: scale,
        gripColor: CronosFuturisticTheme.neonCyan,
        onScaleChanged: (v) => widget.onResizeTile!(tile.layoutKey, v),
        child: body,
      );
    }

    return CronosJiggleMode(
      active: true,
      child: body,
    );
  }

  Widget _buildSidebar() {
    return ListenableBuilder(
      listenable: GestoproNavSubItemsCache.revision,
      builder: (context, _) {
        final cached = GestoproNavSubItemsCache.items;
        final subItems = widget.useLocalNavSubItemsOnly
            ? _navSubItems()
            : (cached.isNotEmpty ? cached : _navSubItems());
        return FuturisticSidebar(
          activeSection: widget.activeNavSection,
          subItems: subItems,
          activeSubKey: widget.useLocalNavSubItemsOnly
              ? null
              : GestoproNavSubItemsCache.activeKey,
          profileFullName: widget.userDisplayName,
          profileUsername: widget.username,
          profileUsersTableId: widget.userId,
          onHome: widget.reorderMode ? null : widget.onOpenHome,
          onDashboard:
              widget.reorderMode ? null : widget.onOpenDashboard,
          onNotifiche:
              widget.reorderMode ? null : widget.onOpenNotifiche,
          onAlert: widget.reorderMode ? null : widget.onOpenAlert,
          onImpostazioni:
              widget.reorderMode ? null : widget.onOpenImpostazioni,
          onSupporto: widget.reorderMode ? null : widget.onOpenSupport,
          onOpenDtView: widget.reorderMode ? null : widget.onOpenDtView,
        );
      },
    );
  }

  Widget _buildTopBar(bool wide) {
    final topBar = FuturisticTopBar(
      userName: widget.userDisplayName,
      username: widget.username,
      role: widget.roleLabel,
      usersTableId: widget.userId,
      onSettings: _hasQuickSettings ? _showSettingsMenu : null,
      onNotifiche: widget.reorderMode ? null : widget.onOpenNotifiche,
      onVideo: widget.reorderMode
          ? null
          : () => VideoGalleryNavigation.open(
                context,
                role: widget.roleLabel,
              ),
      onSwitchToClassic:
          widget.reorderMode ? null : widget.onSwitchToClassic,
      switchToClassicTooltip: widget.switchToClassicTooltip,
      onOpenDipendente: _resolveOpenDipendente(),
      onOpenDtView: widget.reorderMode ? null : widget.onOpenDtView,
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
                child: SafeArea(child: _buildSidebar()),
              ),
        body: Stack(
          children: [
            const ParticlesBackground(),
            Row(
              children: [
                if (wide) _buildSidebar(),
                Expanded(
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildTopBar(wide),
                        if (widget.reorderMode) _buildReorderToolbar(),
                        if (widget.reorderMode && widget.canEditLayout)
                          CronosHubCrossLayoutDropBar(
                            currentLayoutKey: widget.dashboardLayoutKey,
                            onAcceptItemKey: widget.onMoveToLayout ?? (_, _) {},
                          ),
                        Expanded(
                          child: widget.tiles.isEmpty
                              ? Center(
                                  child: Text(
                                    'Nessun modulo attivo.',
                                    style: TextStyle(
                                      color: CronosFuturisticTheme.neonCyan
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                )
                              : _buildGrid(wide),
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

  Widget _buildGrid(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final cross = wide
              ? (w >= 1200 ? 6 : (w >= 960 ? 5 : 4))
              : (w >= 560 ? 3 : 2);
          final styles = <String, HubTileStyle>{
            for (final tile in widget.tiles)
              tile.layoutKey: tile.tileStyle ?? const HubTileStyle(),
          };
          final useFreeform = hubShouldUseFreeformLayout(
            isMobileLayout: !wide,
            width: w,
            reorderMode: widget.reorderMode,
            canEditLayout: widget.canEditLayout,
            layoutKeys: widget.tiles.map((t) => t.layoutKey),
            activeStyles: styles,
          );

          Widget grid;
          if (useFreeform) {
            grid = CronosFreeformHubCanvas(
              itemCount: widget.tiles.length,
              crossAxisCount: cross,
              childAspectRatio: HubTileGridConfig.cellAspectRatio,
              maxCanvasHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : null,
              reorderMode: widget.reorderMode,
              layoutKeyForIndex: (i) => widget.tiles[i].layoutKey,
              styleForKey: (key) => styles[key],
              scaleForIndex: (i) =>
                  widget.tiles[i].tileStyle?.sizeScale ?? 1.0,
              onGridCellChanged: widget.onGridCellChanged,
              itemBuilder: (_, i) => _buildTile(
                    context,
                    widget.tiles[i],
                    reordering: widget.reorderMode,
                  ),
            );
          } else {
            grid = CronosAdaptiveHubGrid(
              crossAxisCount: cross,
              childAspectRatio: HubTileGridConfig.cellAspectRatio,
              spacing: 12,
              itemCount: widget.tiles.length,
              reorderMode: widget.reorderMode,
              onReorder: widget.onReorder,
              scaleForIndex: (i) =>
                  widget.tiles[i].tileStyle?.sizeScale ?? 1.0,
              itemBuilder: (ctx, i) => _buildTile(
                    ctx,
                    widget.tiles[i],
                    reordering: widget.reorderMode,
                  ),
            );
          }

          if (useFreeform) return grid;
          if (widget.reorderMode) return grid;
          return SingleChildScrollView(child: grid);
        },
      ),
    );
  }
}
