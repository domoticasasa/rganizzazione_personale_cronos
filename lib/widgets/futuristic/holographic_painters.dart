import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PathMetric;

import 'package:flutter/material.dart';

import '../../theme/cronos_futuristic_theme.dart';

/// Rettangolo con angoli smussati (chamfer) per i pod Nexus.
Path buildChamferedRectPath(Size size, double chamfer) {
  final w = size.width;
  final h = size.height;
  final c = chamfer.clamp(4.0, math.min(w, h) * 0.18);
  return Path()
    ..moveTo(c, 0)
    ..lineTo(w - c, 0)
    ..lineTo(w, c)
    ..lineTo(w, h - c)
    ..lineTo(w - c, h)
    ..lineTo(c, h)
    ..lineTo(0, h - c)
    ..lineTo(0, c)
    ..close();
}

/// Clipper per pannelli con angoli tagliati.
class ChamferedRectClipper extends CustomClipper<Path> {
  const ChamferedRectClipper({this.chamfer = 12});

  final double chamfer;

  @override
  Path getClip(Size size) => buildChamferedRectPath(size, chamfer);

  @override
  bool shouldReclip(covariant ChamferedRectClipper old) =>
      old.chamfer != chamfer;
}

/// Bordo sci-fi: SweepGradient rotante + alone sfocato (solo sul perimetro).
class GlowingBorderPainter extends CustomPainter {
  const GlowingBorderPainter({
    required this.animationValue,
    required this.color,
    this.chamfer = 12,
    this.borderRadius = 0,
    this.strokeWidth = 3,
  });

  final double animationValue;
  final Color color;
  final double chamfer;
  final double borderRadius;
  final double strokeWidth;

  Path _outlinePath(Size size) {
    final inset = strokeWidth / 2;
    final w = size.width - strokeWidth;
    final h = size.height - strokeWidth;
    if (borderRadius > 0) {
      final r = borderRadius.clamp(0.0, math.min(w, h) / 2);
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(inset, inset, w, h),
            Radius.circular(r),
          ),
        );
    }
    final path = buildChamferedRectPath(Size(w, h), chamfer);
    return path..shift(Offset(inset, inset));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final angle = animationValue * 2 * math.pi;
    final path = _outlinePath(size);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final fade = Color.lerp(color, CronosFuturisticTheme.voidBg, 0.82)!;

    final glow = Paint()
      ..strokeWidth = strokeWidth + 4
      ..style = PaintingStyle.stroke
      ..imageFilter = ImageFilter.blur(sigmaX: 8, sigmaY: 8)
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(angle),
        colors: [
          color.withValues(alpha: 0.65),
          Colors.transparent,
        ],
        stops: const [0.1, 0.6],
      ).createShader(rect);

    final border = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(angle),
        colors: [
          color,
          fade,
          Colors.transparent,
          color,
        ],
        stops: const [0.0, 0.2, 0.8, 1.0],
      ).createShader(rect);

    canvas.drawPath(path, glow);
    canvas.drawPath(path, border);
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant GlowingBorderPainter old) =>
      old.animationValue != animationValue ||
      old.color != color ||
      old.chamfer != chamfer ||
      old.borderRadius != borderRadius;
}

/// Bordo neon con fascio luminoso che percorre il perimetro (solo stroke).
class TravelingBorderPainter extends CustomPainter {
  const TravelingBorderPainter({
    required this.progress,
    required this.color,
    this.chamfer = 12,
    this.borderRadius = 0,
    this.strokeWidth = 2,
    this.spotFraction = 0.2,
    this.secondSpot = true,
  });

  final double progress;
  final Color color;
  final double chamfer;
  final double borderRadius;
  final double strokeWidth;
  final double spotFraction;
  final bool secondSpot;

  Path _outlinePath(Size size) {
    final inset = strokeWidth / 2;
    final w = size.width - strokeWidth;
    final h = size.height - strokeWidth;
    if (borderRadius > 0) {
      final r = borderRadius.clamp(0.0, math.min(w, h) / 2);
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(inset, inset, w, h),
            Radius.circular(r),
          ),
        );
    }
    return buildChamferedRectPath(Size(w, h), chamfer)
      ..shift(Offset(inset, inset));
  }

  void _paintSpot(
    Canvas canvas,
    PathMetric metric,
    double total,
    double start,
    double len,
    double intensity,
  ) {
    const steps = 18;
    for (var i = 0; i < steps; i++) {
      final t0 = (start + len * i / steps) % total;
      final t1 = (start + len * (i + 1) / steps) % total;
      final segment = t1 > t0
          ? metric.extractPath(t0, t1)
          : Path()
            ..addPath(metric.extractPath(t0, total), Offset.zero)
            ..addPath(metric.extractPath(0, t1), Offset.zero);

      final peak = math.pow(1 - (i / (steps - 1) - 0.5).abs() * 2, 2).toDouble();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + peak * 1.2
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          color.withValues(alpha: 0.35),
          Colors.white,
          peak * intensity,
        )!;

      if (peak > 0.82) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      }
      canvas.drawPath(segment, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _outlinePath(size);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.55);
    canvas.drawPath(path, base);

    for (final metric in path.computeMetrics()) {
      final total = metric.length;
      final spotLen = total * spotFraction;
      final start = (progress % 1.0) * total;

      _paintSpot(canvas, metric, total, start, spotLen, 1.0);
      if (secondSpot) {
        _paintSpot(
          canvas,
          metric,
          total,
          (start + total * 0.5) % total,
          spotLen * 0.75,
          0.85,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant TravelingBorderPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.chamfer != chamfer ||
      old.borderRadius != borderRadius;
}

/// Griglia schematica di sfondo (matrix holographic).
class SchematicGridPainter extends CustomPainter {
  const SchematicGridPainter({this.opacity = 0.2, this.step = 30});

  final double opacity;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CronosFuturisticTheme.electricBright.withValues(alpha: opacity)
      ..strokeWidth = 0.5;

    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant SchematicGridPainter old) =>
      old.opacity != opacity || old.step != step;
}

/// Riflesso diagonale sul vetro dei pannelli.
class GlassReflectPainter extends CustomPainter {
  const GlassReflectPainter({this.opacity = 0.05});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.2)
      ..lineTo(size.width, size.height * 0.8)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height * 0.4)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GlassReflectPainter old) => old.opacity != opacity;
}

/// Scan line orizzontale animata sui pannelli.
class ScanLinePainter extends CustomPainter {
  const ScanLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()..color = color.withValues(alpha: 0.14);
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2.5), paint);
  }

  @override
  bool shouldRepaint(covariant ScanLinePainter old) =>
      old.progress != progress || old.color != color;
}

/// Particelle luminose per lo sfondo volumetrico.
class AmbientParticlesPainter extends CustomPainter {
  const AmbientParticlesPainter({required this.t, this.count = 64});

  final double t;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint();
    for (var i = 0; i < count; i++) {
      final phase = (t * 4 + i * 0.17) % 1.0;
      final pulse = (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
      final x = ((i * 73) % 1000) / 1000 * size.width;
      final y = ((i * 131) % 1000) / 1000 * size.height;
      dot.color = CronosFuturisticTheme.neonCyan.withValues(
        alpha: 0.03 + pulse * 0.22,
      );
      canvas.drawCircle(Offset(x, y), 0.6 + pulse * 1.8, dot);
    }
  }

  @override
  bool shouldRepaint(covariant AmbientParticlesPainter old) => old.t != t;
}

/// Bande aurora blu elettrico.
class AuroraPainter extends CustomPainter {
  const AuroraPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (var i = 0; i < 3; i++) {
      final yBase = h * (0.15 + i * 0.22) + math.sin(t * math.pi * 2 + i) * 30;
      final path = Path()
        ..moveTo(0, yBase)
        ..quadraticBezierTo(
          w * 0.35,
          yBase - 60 - i * 20,
          w * 0.55,
          yBase + math.sin(t * math.pi * 2) * 20,
        )
        ..quadraticBezierTo(w * 0.85, yBase + 40, w, yBase - 20)
        ..lineTo(w, yBase + 80)
        ..lineTo(0, yBase + 60)
        ..close();

      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            CronosFuturisticTheme.electricBlue.withValues(alpha: 0.0),
            CronosFuturisticTheme.electricBright.withValues(alpha: 0.07 + i * 0.02),
            CronosFuturisticTheme.neonCyan.withValues(alpha: 0.05),
            CronosFuturisticTheme.electricBlue.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AuroraPainter old) => old.t != t;
}

/// Angoli HUD sui pod.
class HudCornerPainter extends CustomPainter {
  const HudCornerPainter({required this.color, this.len = 14});

  final Color color;
  final double len;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    void corner(Offset o, bool top, bool left) {
      final dx = left ? 1.0 : -1.0;
      final dy = top ? 1.0 : -1.0;
      canvas.drawLine(o, o + Offset(len * dx, 0), p);
      canvas.drawLine(o, o + Offset(0, len * dy), p);
    }

    corner(const Offset(6, 6), true, true);
    corner(Offset(size.width - 6, 6), true, false);
    corner(Offset(6, size.height - 6), false, true);
    corner(Offset(size.width - 6, size.height - 6), false, false);
  }

  @override
  bool shouldRepaint(covariant HudCornerPainter old) => old.color != color;
}
