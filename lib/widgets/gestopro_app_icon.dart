import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/cronos_fonts.dart';

/// Icona combo Gestopro360: documento + check e marchio G360.
class GestoproAppIcon extends StatelessWidget {
  const GestoproAppIcon({
    super.key,
    this.size = 200,
    this.accent = const Color(0xFF1565C0),
    this.cyan = const Color(0xFF00AEEF),
  });

  final double size;
  final Color accent;
  final Color cyan;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GestoproAppIconPainter(
          accent: accent,
          cyan: cyan,
          g360Style: CronosFonts.orbitron(
            fontSize: size * 0.16,
            fontWeight: FontWeight.w700,
            letterSpacing: size * 0.012,
            color: accent,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _GestoproAppIconPainter extends CustomPainter {
  _GestoproAppIconPainter({
    required this.accent,
    required this.cyan,
    required this.g360Style,
  });

  final Color accent;
  final Color cyan;
  final TextStyle g360Style;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = Radius.circular(s * 0.22);
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.04, s * 0.04, s * 0.92, s * 0.92),
      r,
    );

    final platePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white,
          Color.lerp(Colors.white, cyan, 0.10)!,
          Color.lerp(Colors.white, accent, 0.16)!,
        ],
      ).createShader(plate.outerRect);
    canvas.drawRRect(plate, platePaint);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cyan.withValues(alpha: 0.85), accent],
      ).createShader(plate.outerRect);
    canvas.drawRRect(plate, rim);

    // Documento.
    final docRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.20, s * 0.14, s * 0.46, s * 0.58),
      Radius.circular(s * 0.06),
    );
    canvas.drawRRect(
      docRect,
      Paint()
        ..color = Colors.white
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.01),
    );
    canvas.drawRRect(docRect, Paint()..color = const Color(0xFFF8FBFF));
    canvas.drawRRect(
      docRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = accent.withValues(alpha: 0.28),
    );

    // Angolo piegato.
    final fold = Path()
      ..moveTo(docRect.right - s * 0.12, docRect.top)
      ..lineTo(docRect.right, docRect.top + s * 0.12)
      ..lineTo(docRect.right - s * 0.12, docRect.top + s * 0.12)
      ..close();
    canvas.drawPath(fold, Paint()..color = Color.lerp(Colors.white, cyan, 0.22)!);
    canvas.drawPath(
      fold,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = accent.withValues(alpha: 0.25),
    );

    // Righe documento.
    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = s * 0.016
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = docRect.top + s * 0.28 + i * s * 0.075;
      canvas.drawLine(
        Offset(docRect.left + s * 0.08, y),
        Offset(docRect.right - s * 0.10, y),
        linePaint,
      );
    }

    // Badge check.
    final badgeC = Offset(docRect.left + s * 0.02, docRect.bottom - s * 0.02);
    final badgeR = s * 0.13;
    canvas.drawCircle(
      badgeC,
      badgeR + s * 0.012,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      badgeC,
      badgeR,
      Paint()
        ..shader = RadialGradient(
          colors: [cyan, accent],
        ).createShader(Rect.fromCircle(center: badgeC, radius: badgeR)),
    );

    final check = Path()
      ..moveTo(badgeC.dx - badgeR * 0.42, badgeC.dy + badgeR * 0.02)
      ..lineTo(badgeC.dx - badgeR * 0.08, badgeC.dy + badgeR * 0.38)
      ..lineTo(badgeC.dx + badgeR * 0.46, badgeC.dy - badgeR * 0.32);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.038
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Punto luminoso in alto a destra.
    final spark = Offset(s * 0.78, s * 0.22);
    canvas.drawCircle(
      spark,
      s * 0.035,
      Paint()..color = cyan.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      spark,
      s * 0.07,
      Paint()
        ..color = cyan.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );

    // G360 disegnato sul canvas: niente nodo HTML, niente evidenziatore Chrome.
    final g360 = TextPainter(
      text: TextSpan(text: 'G360', style: g360Style),
      textDirection: TextDirection.ltr,
    )..layout();
    g360.paint(
      canvas,
      Offset(s * 0.73 - g360.width / 2, s * 0.79 - g360.height / 2),
    );
    g360.dispose();
  }

  @override
  bool shouldRepaint(covariant _GestoproAppIconPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.cyan != cyan ||
        oldDelegate.g360Style != g360Style;
  }
}

/// Glow morbido dietro [GestoproAppIcon] (intensità 0–1).
class GestoproIconHalo extends StatelessWidget {
  const GestoproIconHalo({
    super.key,
    required this.size,
    required this.accent,
    required this.cyan,
    required this.intensity,
  });

  final double size;
  final Color accent;
  final Color cyan;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final t = intensity.clamp(0.0, 1.0);
    return IgnorePointer(
      child: Container(
        width: size * 1.55,
        height: size * 1.55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              cyan.withValues(alpha: 0.42 * t),
              accent.withValues(alpha: 0.18 * t),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Anello/orbita intorno all'icona.
class GestoproIconOrbit extends StatelessWidget {
  const GestoproIconOrbit({
    super.key,
    required this.size,
    required this.progress,
    required this.accent,
    required this.cyan,
  });

  final double size;
  final double progress;
  final Color accent;
  final Color cyan;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OrbitPainter(
        progress: progress,
        accent: accent,
        cyan: cyan,
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.accent,
    required this.cyan,
  });

  final double progress;
  final Color accent;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 3;
    final sweep = progress * math.pi * 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = accent.withValues(alpha: 0.14);
    canvas.drawCircle(c, r, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: sweep,
        endAngle: sweep + math.pi,
        colors: [
          Colors.transparent,
          cyan,
          accent,
          Colors.transparent,
        ],
        transform: GradientRotation(sweep),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      sweep,
      math.pi * 1.15,
      false,
      arc,
    );

    for (var i = 0; i < 3; i++) {
      final a = sweep + i * (math.pi * 2 / 3);
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      canvas.drawCircle(
        p,
        i == 0 ? 5.5 : 3.2,
        Paint()..color = i == 0 ? cyan : accent.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.cyan != cyan;
  }
}
