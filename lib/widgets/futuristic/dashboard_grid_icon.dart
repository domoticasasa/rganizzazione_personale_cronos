import 'package:flutter/material.dart';

/// Icona griglia GESTOPRO — asset PNG con fallback vettoriale.
class DashboardGridIcon extends StatelessWidget {
  const DashboardGridIcon({
    super.key,
    required this.color,
    this.size = 24,
  });

  static const assetPath = 'assets/icons/gestopro_grid_icon.png';

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => CustomPaint(
          size: Size.square(size),
          painter: _DashboardGridPainter(color: color),
        ),
      ),
    );
  }
}

class _DashboardGridPainter extends CustomPainter {
  _DashboardGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const gapFactor = 0.13;
    final gap = size.width * gapFactor;
    final cell = (size.width - gap) / 2;
    final radius = cell * 0.16;

    void drawCell(double left, double top) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, cell, cell),
          Radius.circular(radius),
        ),
        paint,
      );
    }

    drawCell(0, 0);
    drawCell(cell + gap, 0);
    drawCell(0, cell + gap);
    drawCell(cell + gap, cell + gap);
  }

  @override
  bool shouldRepaint(covariant _DashboardGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
