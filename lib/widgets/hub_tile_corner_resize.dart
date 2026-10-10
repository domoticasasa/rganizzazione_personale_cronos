import 'package:flutter/material.dart';

import '../hub/hub_tile_style.dart';

/// Contenitore tile: la dimensione è decisa dalla griglia adattiva esterna.
class HubTileScaledShell extends StatelessWidget {
  const HubTileScaledShell({
    super.key,
    required this.fillCell,
    required this.child,
  });

  final bool fillCell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return fillCell ? SizedBox.expand(child: child) : child;
  }
}

enum _ResizeCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Maniglie agli angoli per ridimensionare trascinando (modalità riordino).
class HubTileCornerResizeOverlay extends StatelessWidget {
  const HubTileCornerResizeOverlay({
    super.key,
    required this.enabled,
    required this.sizeScale,
    required this.onScaleChanged,
    required this.child,
    this.gripColor,
  });

  final bool enabled;
  final double sizeScale;
  final ValueChanged<double> onScaleChanged;
  final Widget child;
  final Color? gripColor;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    final grip = gripColor ?? theme.colorScheme.primary.withValues(alpha: 0.85);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        _cornerHandle(
          gripColor: grip,
          corner: _ResizeCorner.topLeft,
          cursor: SystemMouseCursors.resizeUpLeft,
        ),
        _cornerHandle(
          gripColor: grip,
          corner: _ResizeCorner.topRight,
          cursor: SystemMouseCursors.resizeUpRight,
        ),
        _cornerHandle(
          gripColor: grip,
          corner: _ResizeCorner.bottomLeft,
          cursor: SystemMouseCursors.resizeDownLeft,
        ),
        _cornerHandle(
          gripColor: grip,
          corner: _ResizeCorner.bottomRight,
          cursor: SystemMouseCursors.resizeDownRight,
        ),
      ],
    );
  }

  Widget _cornerHandle({
    required Color gripColor,
    required _ResizeCorner corner,
    required MouseCursor cursor,
  }) {
    const size = 22.0;
    double deltaScale(Offset delta) {
      final dx = delta.dx;
      final dy = delta.dy;
      final change = switch (corner) {
        _ResizeCorner.bottomRight => (dx + dy) / 130,
        _ResizeCorner.topLeft => (-dx - dy) / 130,
        _ResizeCorner.topRight => (dx - dy) / 130,
        _ResizeCorner.bottomLeft => (-dx + dy) / 130,
      };
      return (sizeScale + change)
          .clamp(HubTileStyle.minScale, HubTileStyle.maxScale);
    }

    Widget positioned(Widget handle) {
      return switch (corner) {
        _ResizeCorner.topLeft => Positioned(top: 0, left: 0, child: handle),
        _ResizeCorner.topRight => Positioned(top: 0, right: 0, child: handle),
        _ResizeCorner.bottomLeft =>
          Positioned(bottom: 0, left: 0, child: handle),
        _ResizeCorner.bottomRight =>
          Positioned(bottom: 0, right: 0, child: handle),
      };
    }

    return positioned(
      MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) => onScaleChanged(deltaScale(details.delta)),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _CornerGripPainter(
                corner: corner,
                color: gripColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerGripPainter extends CustomPainter {
  _CornerGripPainter({required this.corner, required this.color});

  final _ResizeCorner corner;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 10.0;
    switch (corner) {
      case _ResizeCorner.topLeft:
        canvas.drawLine(const Offset(2, 2), Offset(2 + len, 2), paint);
        canvas.drawLine(const Offset(2, 2), Offset(2, 2 + len), paint);
      case _ResizeCorner.topRight:
        canvas.drawLine(
          Offset(size.width - 2, 2),
          Offset(size.width - 2 - len, 2),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - 2, 2),
          Offset(size.width - 2, 2 + len),
          paint,
        );
      case _ResizeCorner.bottomLeft:
        canvas.drawLine(
          Offset(2, size.height - 2),
          Offset(2 + len, size.height - 2),
          paint,
        );
        canvas.drawLine(
          Offset(2, size.height - 2),
          Offset(2, size.height - 2 - len),
          paint,
        );
      case _ResizeCorner.bottomRight:
        canvas.drawLine(
          Offset(size.width - 2, size.height - 2),
          Offset(size.width - 2 - len, size.height - 2),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - 2, size.height - 2),
          Offset(size.width - 2, size.height - 2 - len),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerGripPainter oldDelegate) =>
      oldDelegate.corner != corner || oldDelegate.color != color;
}
