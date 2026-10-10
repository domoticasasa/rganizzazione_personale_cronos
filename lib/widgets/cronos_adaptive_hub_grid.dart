import 'package:flutter/material.dart';

/// Numero di colonne in base alla larghezza (mobile, tablet, desktop).
int hubResponsiveCrossAxisCount({
  required double width,
  required double maxCellWidth,
  bool isMobileLayout = false,
  double spacing = 12,
}) {
  if (!width.isFinite || width <= 0) return 1;

  if (isMobileLayout) {
    if (width < 340) return 1;
    if (width < 560) return 2;
    return 3;
  }

  if (width < 480) return 1;
  if (width < 640) return 2;
  if (width < 840) return 3;

  final count = ((width + spacing) / (maxCellWidth + spacing)).floor();
  return count.clamp(3, 7);
}

/// Colonne per hub embedded (dialog / impostazioni) — rispetta [maxCellWidth] e scala.
int hubEmbeddedCrossAxisCount({
  required double width,
  required double maxCellWidth,
  double spacing = 12,
}) {
  if (!width.isFinite || width <= 0) return 2;
  if (width < 300) return 1;
  if (width < 420) return 2;
  final count = ((width + spacing) / (maxCellWidth + spacing)).floor();
  return count.clamp(2, 8);
}

/// Dimensioni cella base per la griglia hub adattiva.
({double baseWidth, double baseHeight}) hubGridBaseCellSize({
  required double maxWidth,
  required int crossAxisCount,
  required double childAspectRatio,
  double spacing = 12,
}) {
  final cols = crossAxisCount.clamp(1, 12);
  final baseWidth = (maxWidth - spacing * (cols - 1)) / cols;
  final baseHeight = baseWidth / childAspectRatio;
  return (baseWidth: baseWidth, baseHeight: baseHeight);
}

/// Griglia hub che si adatta alle dimensioni di ogni pulsante (wrap, no overlap).
class CronosAdaptiveHubGrid extends StatelessWidget {
  const CronosAdaptiveHubGrid({
    super.key,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.itemCount,
    required this.itemBuilder,
    required this.scaleForIndex,
    this.reorderMode = false,
    this.onReorder,
    this.spacing = 12,
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double Function(int index) scaleForIndex;
  final bool reorderMode;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        final base = hubGridBaseCellSize(
          maxWidth: maxWidth,
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          spacing: spacing,
        );

        final children = <Widget>[];
        for (var i = 0; i < itemCount; i++) {
          final scale = scaleForIndex(i).clamp(0.6, 2.0);
          final tile = SizedBox(
            width: base.baseWidth * scale,
            height: base.baseHeight * scale,
            child: itemBuilder(context, i),
          );
          children.add(
            reorderMode && onReorder != null
                ? _ReorderableWrapCell(
                    index: i,
                    onReorder: onReorder!,
                    child: tile,
                  )
                : tile,
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.start,
          children: children,
        );
      },
    );
  }
}

class _ReorderableWrapCell extends StatelessWidget {
  const _ReorderableWrapCell({
    required this.index,
    required this.onReorder,
    required this.child,
  });

  final int index;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          maxSimultaneousDrags: 1,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Opacity(
              opacity: 0.92,
              child: child,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: highlighted
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
