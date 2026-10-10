import 'package:flutter/material.dart';

import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../utils/responsive.dart';

/// Margine interno per ✕ / ⇄ attorno al tile in cella griglia.
const double kGridTileChromeInset = 4;

/// Scope drag griglia hub ([HubTileGridConfig.sizeLabel]).
class HubGridDragScope extends InheritedWidget {
  const HubGridDragScope({
    super.key,
    required this.enabled,
    required this.onPanUpdate,
    required this.onPanEnd,
    required super.child,
  });

  final bool enabled;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  static HubGridDragScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HubGridDragScope>();
  }

  @override
  bool updateShouldNotify(HubGridDragScope oldWidget) =>
      enabled != oldWidget.enabled;
}

typedef FreeformPositionPanScope = HubGridDragScope;

/// Avvolge l'icona trascinamento in modalità griglia.
Widget wrapFreeformDragIcon({
  required BuildContext context,
  required Widget icon,
}) {
  final scope = HubGridDragScope.maybeOf(context);
  if (scope == null || !scope.enabled) return icon;
  return _freeformDragGesture(
    scope: scope,
    child: Tooltip(
      message: 'Trascina sulla griglia ${HubTileGridConfig.sizeLabel}',
      child: icon,
    ),
  );
}

/// Area trascinamento ampia (tile intero in riordino griglia).
Widget wrapFreeformDragTarget({
  required BuildContext context,
  required Widget child,
}) {
  final scope = HubGridDragScope.maybeOf(context);
  if (scope == null || !scope.enabled) return child;
  return _freeformDragGesture(scope: scope, child: child);
}

Widget _freeformDragGesture({
  required HubGridDragScope scope,
  required Widget child,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanUpdate: scope.onPanUpdate,
    onPanEnd: scope.onPanEnd,
    child: child,
  );
}

class HubTileControlInsets {
  HubTileControlInsets._();

  static const double top = 8;
  static const double side = 24;
  static const double bottom = 24;
  static const double corner = 8;
}

class HubTileFreeformChromeLayout extends StatelessWidget {
  const HubTileFreeformChromeLayout({
    super.key,
    required this.tileBody,
    this.topLeft,
    this.topRight,
    this.bottomLeft,
    this.bottomRight,
  });

  final Widget tileBody;
  final Widget? topLeft;
  final Widget? topRight;
  final Widget? bottomLeft;
  final Widget? bottomRight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: tileBody),
        if (topLeft != null)
          Positioned(
            top: kGridTileChromeInset,
            left: kGridTileChromeInset,
            child: _elevated(topLeft!),
          ),
        if (topRight != null)
          Positioned(
            top: kGridTileChromeInset,
            right: kGridTileChromeInset,
            child: _elevated(topRight!),
          ),
        if (bottomLeft != null)
          Positioned(
            bottom: kGridTileChromeInset,
            left: kGridTileChromeInset,
            child: _elevated(bottomLeft!),
          ),
        if (bottomRight != null)
          Positioned(
            bottom: kGridTileChromeInset,
            right: kGridTileChromeInset,
            child: _elevated(bottomRight!),
          ),
      ],
    );
  }

  static Widget _elevated(Widget child) {
    return Material(
      color: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black26,
      child: child,
    );
  }
}

bool hubShouldUseFreeformLayout({
  required bool isMobileLayout,
  required double width,
  required bool reorderMode,
  required bool canEditLayout,
  required Iterable<String> layoutKeys,
  required Map<String, HubTileStyle> activeStyles,
  double minWidth = 600,
}) {
  if (isMobileLayout || width < minWidth) return false;
  if (reorderMode && canEditLayout) return true;
  for (final key in layoutKeys) {
    if (activeStyles[key]?.hasGridPlacement ?? false) return true;
  }
  return false;
}

List<T> hubSortItemsByPosition<T>(
  List<T> items,
  Map<String, HubTileStyle> styles,
  String Function(T item) keyOf,
) {
  final copy = List<T>.from(items);
  copy.sort((a, b) {
    final sa = styles[keyOf(a)];
    final sb = styles[keyOf(b)];
    final ar = sa?.gridRow ?? 99;
    final br = sb?.gridRow ?? 99;
    final rCmp = ar.compareTo(br);
    if (rCmp != 0) return rCmp;
    return (sa?.gridCol ?? 99).compareTo(sb?.gridCol ?? 99);
  });
  return copy;
}

/// Canvas hub a griglia (tile multi-cella).
class CronosFreeformHubCanvas extends StatefulWidget {
  const CronosFreeformHubCanvas({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.layoutKeyForIndex,
    required this.styleForKey,
    required this.scaleForIndex,
    required this.crossAxisCount,
    required this.childAspectRatio,
    this.spacing = 12,
    this.reorderMode = false,
    this.onGridCellChanged,
    this.baseTileWidth = 148,
    this.maxCanvasHeight,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final String Function(int index) layoutKeyForIndex;
  final HubTileStyle? Function(String layoutKey) styleForKey;
  final double Function(int index) scaleForIndex;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;
  final bool reorderMode;
  final void Function(
    String layoutKey,
    int col,
    int row,
    int colSpan,
    int rowSpan,
  )? onGridCellChanged;
  final double baseTileWidth;
  final double? maxCanvasHeight;

  @override
  State<CronosFreeformHubCanvas> createState() =>
      _CronosFreeformHubCanvasState();
}

class _CronosFreeformHubCanvasState extends State<CronosFreeformHubCanvas> {
  final GlobalKey _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth;
        if (!w.isFinite || w <= 0) {
          return const SizedBox.shrink();
        }
        const cols = HubTileGridConfig.columns;
        const rows = HubTileGridConfig.rows;
        const gap = HubTileGridConfig.spacing;
        final maxH = widget.maxCanvasHeight ?? constraints.maxHeight;

        // Solo tablet: celle quadrate (evita tile allungati in portrait).
        // Desktop/PC: comportamento originale — riempie l'altezza del viewport.
        final tabletAspect = isTabletDevice(context) ||
            (isMobileWebPlatform() &&
                MediaQuery.sizeOf(context).shortestSide >=
                    CronosBreakpoints.phone);

        late double cellW;
        late double cellH;
        late double canvasW;
        late double h;

        if (tabletAspect) {
          var cell = (w - gap * (cols - 1)) / cols;
          if (cell < 1) cell = 1;
          canvasW = w;
          h = rows * cell + gap * (rows - 1);
          if (maxH.isFinite && maxH > 0 && h > maxH) {
            cell = (maxH - gap * (rows - 1)) / rows;
            if (cell < 1) cell = 1;
            h = maxH;
            canvasW = cols * cell + gap * (cols - 1);
          }
          cellW = cell;
          cellH = cell;
        } else {
          // Desktop: griglia 26×20 che occupa tutta l'area visibile.
          h = (maxH.isFinite && maxH > 0)
              ? maxH
              : rows * ((w - gap * (cols - 1)) / cols) * 0.92 +
                  gap * (rows - 1);
          canvasW = w;
          var cw = (w - gap * (cols - 1)) / cols;
          var ch = (h - gap * (rows - 1)) / rows;
          if (cw < 1) cw = 1;
          if (ch < 1) ch = 1;
          cellW = cw;
          cellH = ch;
        }

        final keys = List<String>.generate(
          widget.itemCount,
          widget.layoutKeyForIndex,
        );
        final styles = <String, HubTileStyle>{
          for (final k in keys)
            if (widget.styleForKey(k) != null) k: widget.styleForKey(k)!,
        };
        final placements = HubTileGridLayout.resolve(
          keysInOrder: keys,
          styles: styles,
          scaleForKey: (key) {
            final idx = keys.indexOf(key);
            return idx >= 0 ? widget.scaleForIndex(idx) : 1.0;
          },
        );

        final stack = Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.reorderMode)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _HubGridPainter(
                        cellW: cellW,
                        cellH: cellH,
                        gap: gap,
                        lineColor: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < widget.itemCount; i++)
                if (placements[widget.layoutKeyForIndex(i)] case final rect?)
                _GridTileSlot(
                  key: ValueKey<String>(widget.layoutKeyForIndex(i)),
                  canvasKey: _canvasKey,
                  layoutKey: widget.layoutKeyForIndex(i),
                  gridRect: rect,
                  canvasSize: Size(canvasW, h),
                  reorderMode: widget.reorderMode,
                  placed: placements,
                  onGridCellChanged: widget.onGridCellChanged,
                  itemBuilder: (ctx) => widget.itemBuilder(ctx, i),
                ),
            ],
          );

        final canvas = SizedBox(
          key: _canvasKey,
          width: canvasW,
          height: h,
          child: stack,
        );
        if (!tabletAspect || canvasW >= w - 0.5) {
          return canvas;
        }
        return Align(
          alignment: Alignment.topCenter,
          child: canvas,
        );
      },
    );
  }
}

class _GridTileSlot extends StatefulWidget {
  const _GridTileSlot({
    super.key,
    required this.canvasKey,
    required this.layoutKey,
    required this.gridRect,
    required this.canvasSize,
    required this.reorderMode,
    required this.placed,
    required this.itemBuilder,
    this.onGridCellChanged,
  });

  final GlobalKey canvasKey;
  final String layoutKey;
  final HubTileGridRect gridRect;
  final Size canvasSize;
  final bool reorderMode;
  final Map<String, HubTileGridRect> placed;
  final Widget Function(BuildContext context) itemBuilder;
  final void Function(
    String layoutKey,
    int col,
    int row,
    int colSpan,
    int rowSpan,
  )? onGridCellChanged;

  @override
  State<_GridTileSlot> createState() => _GridTileSlotState();
}

class _GridTileSlotState extends State<_GridTileSlot> {
  HubTileGridRect? _preview;
  String? _swapPartnerKey;

  HubTileGridRect get _rect => _preview ?? widget.gridRect;

  /// Ridimensiona per celle mantenendo fisso l'angolo in alto a sinistra.
  void _updateResizePreview(
    Offset global, {
    required bool horizontal,
    required bool vertical,
  }) {
    final canvasRender =
        widget.canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasRender == null) return;
    final local = canvasRender.globalToLocal(global);
    final (cellW, cellH) = HubTileGridLayout.cellSize(
      canvasWidth: widget.canvasSize.width,
      canvasHeight: widget.canvasSize.height,
    );
    const gap = HubTileGridConfig.spacing;
    final origin = widget.gridRect;
    var colSpan = origin.colSpan;
    var rowSpan = origin.rowSpan;
    if (horizontal) {
      final pointerCol = (local.dx / (cellW + gap)).floor();
      colSpan = (pointerCol - origin.col + 1)
          .clamp(1, HubTileGridConfig.columns - origin.col);
    }
    if (vertical) {
      final pointerRow = (local.dy / (cellH + gap)).floor();
      rowSpan = (pointerRow - origin.row + 1)
          .clamp(1, HubTileGridConfig.rows - origin.row);
    }
    final candidate = HubTileGridRect(
      col: origin.col,
      row: origin.row,
      colSpan: colSpan,
      rowSpan: rowSpan,
    );
    if (!candidate.isValid) return;
    if (!HubTileGridLayout.canPlace(
      candidate: candidate,
      placed: widget.placed,
      exceptKey: widget.layoutKey,
    )) {
      return;
    }
    setState(() {
      _preview = candidate;
      _swapPartnerKey = null;
    });
  }

  void _updatePreview(Offset global) {
    final canvasRender =
        widget.canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasRender == null) return;
    final local = canvasRender.globalToLocal(global);
    final candidate = HubTileGridLayout.cellAtLocalPoint(
      localX: local.dx,
      localY: local.dy,
      canvasWidth: widget.canvasSize.width,
      canvasHeight: widget.canvasSize.height,
      colSpan: widget.gridRect.colSpan,
      rowSpan: widget.gridRect.rowSpan,
    );
    if (candidate == null) return;
    final partner = HubTileGridLayout.swapPartnerKey(
      candidate: candidate,
      placed: widget.placed,
      exceptKey: widget.layoutKey,
    );
    final canMove = partner != null ||
        HubTileGridLayout.canPlace(
          candidate: candidate,
          placed: widget.placed,
          exceptKey: widget.layoutKey,
        );
    if (canMove) {
      setState(() {
        _preview = candidate;
        _swapPartnerKey = partner;
      });
    }
  }

  void _commitPreview() {
    final preview = _preview;
    final partnerKey = _swapPartnerKey;
    final origin = widget.gridRect;
    setState(() {
      _preview = null;
      _swapPartnerKey = null;
    });
    if (preview == null || widget.onGridCellChanged == null) return;
    widget.onGridCellChanged!(
      widget.layoutKey,
      preview.col,
      preview.row,
      preview.colSpan,
      preview.rowSpan,
    );
    if (partnerKey != null) {
      final partnerRect = widget.placed[partnerKey];
      if (partnerRect != null) {
        widget.onGridCellChanged!(
          partnerKey,
          origin.col,
          origin.row,
          origin.colSpan,
          origin.rowSpan,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final px = HubTileGridLayout.pixelRect(
      grid: _rect,
      canvasWidth: widget.canvasSize.width,
      canvasHeight: widget.canvasSize.height,
    );

    final draggable = widget.reorderMode && widget.onGridCellChanged != null;
    Widget content;
    if (draggable) {
      content = HubGridDragScope(
        enabled: true,
        onPanUpdate: (d) => _updatePreview(d.globalPosition),
        onPanEnd: (_) => _commitPreview(),
        child: Builder(
          builder: (ctx) => widget.itemBuilder(ctx),
        ),
      );
      content = Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: content),
          _resizeHandle(context, horizontal: true, vertical: false),
          _resizeHandle(context, horizontal: false, vertical: true),
        ],
      );
    } else {
      content = widget.itemBuilder(context);
    }

    return Positioned(
      left: px.left,
      top: px.top,
      width: px.width,
      height: px.height,
      child: content,
    );
  }

  /// Maniglia di ridimensionamento per celle.
  /// - destra: solo larghezza · sotto: solo altezza · angolo: entrambe.
  Widget _resizeHandle(
    BuildContext context, {
    required bool horizontal,
    required bool vertical,
  }) {
    final color = Theme.of(context).colorScheme.primary;
    final corner = horizontal && vertical;
    final cursor = corner
        ? SystemMouseCursors.resizeDownRight
        : (horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown);

    Widget grip;
    if (corner) {
      grip = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomRight: Radius.circular(6),
          ),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const Icon(
          Icons.open_in_full,
          size: 12,
          color: Colors.white,
        ),
      );
    } else {
      grip = Container(
        width: horizontal ? 10 : double.infinity,
        height: horizontal ? double.infinity : 10,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 1),
        ),
      );
    }

    final handle = MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => _updateResizePreview(
          d.globalPosition,
          horizontal: horizontal,
          vertical: vertical,
        ),
        onPanEnd: (_) => _commitPreview(),
        child: grip,
      ),
    );

    if (corner) {
      return Positioned(right: 0, bottom: 0, child: handle);
    }
    if (horizontal) {
      // Bordo destro (solo larghezza): evita gli angoli con i pulsanti.
      return Positioned(right: 0, top: 30, bottom: 30, child: handle);
    }
    // Bordo inferiore (solo altezza): evita gli angoli con i pulsanti.
    return Positioned(left: 30, right: 30, bottom: 0, child: handle);
  }
}

class _HubGridPainter extends CustomPainter {
  _HubGridPainter({
    required this.cellW,
    required this.cellH,
    required this.gap,
    required this.lineColor,
  });

  final double cellW;
  final double cellH;
  final double gap;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (var c = 0; c < HubTileGridConfig.columns; c++) {
      final left = c * (cellW + gap);
      for (var r = 0; r < HubTileGridConfig.rows; r++) {
        final top = r * (cellH + gap);
        canvas.drawRect(Rect.fromLTWH(left, top, cellW, cellH), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HubGridPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}
