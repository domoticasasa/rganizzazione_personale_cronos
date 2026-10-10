import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'gestopro_app_icon.dart';

/// Logo Gestopro360 "atomico" 3D: icona G360 al centro con tre orbite
/// ellittiche inclinate e palline luminose che ci viaggiano sopra.
///
/// Profondita' reale: la meta' posteriore di ogni orbita (e le palline che ci
/// passano) e' disegnata DIETRO l'icona, la meta' anteriore DAVANTI.
/// Palline piu' grandi/luminose davanti, piu' piccole/tenui dietro.
/// Usato da GestoproOrbitBrandHeader (mini logo in testa alle pagine) e
/// dalla splash GestoproIntroSplash.
///
/// [size] e' la dimensione dell'icona centrale; il widget occupa
/// `size * extentFactor` per lasciare spazio alle orbite.
/// [progress] (0-1, ripetuto) guida il moto: con un controller in `repeat()`
/// l'animazione e' continua e senza scatti.
class GestoproOrbitLogo3D extends StatelessWidget {
  const GestoproOrbitLogo3D({
    super.key,
    required this.size,
    required this.progress,
    this.accent = const Color(0xFF1565C0),
    this.cyan = const Color(0xFF00AEEF),
    this.pulse = 1.0,
  });

  /// Lato del riquadro occupato dal logo rispetto a [size].
  static const double extentFactor = 1.8;

  final double size;
  final double progress;
  final Color accent;
  final Color cyan;

  /// Scala dell'icona centrale (respiro), 1.0 = nessuna pulsazione.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size * extentFactor,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _OrbitLogo3DPainter(
                front: false,
                iconSize: size,
                progress: progress,
                accent: accent,
                cyan: cyan,
                pulse: pulse,
              ),
            ),
          ),
          Transform.scale(
            scale: pulse,
            child: RepaintBoundary(
              child: GestoproAppIcon(size: size, accent: accent, cyan: cyan),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OrbitLogo3DPainter(
                  front: true,
                  iconSize: size,
                  progress: progress,
                  accent: accent,
                  cyan: cyan,
                  pulse: pulse,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _OrbitStyle { halo, light, white }

class _OrbitSpec {
  const _OrbitSpec({
    required this.radius,
    required this.tilt,
    required this.roll,
    required this.wobble,
    required this.wobblePhase,
    required this.stroke,
    required this.style,
    required this.speed,
    required this.balls,
  });

  /// Semiasse maggiore, in frazioni del lato icona.
  final double radius;

  /// Inclinazione del piano orbitale (rad): 0 = cerchio frontale.
  final double tilt;

  /// Rotazione dell'ellisse nello schermo (rad, orario).
  final double roll;

  /// Ampiezza della lenta precessione (rad).
  final double wobble;
  final double wobblePhase;

  /// Spessore linea, in frazioni del lato icona.
  final double stroke;
  final _OrbitStyle style;

  /// Giri per ciclo del controller (intero => loop perfetto).
  final int speed;

  /// Fasi iniziali delle palline (frazioni di giro).
  final List<double> balls;
}

const List<_OrbitSpec> _orbits = [
  // Grande orbita quasi circolare, azzurro tenue.
  _OrbitSpec(
    radius: 0.74,
    tilt: 0.42,
    roll: -0.35,
    wobble: 0.06,
    wobblePhase: 0.0,
    stroke: 0.007,
    style: _OrbitStyle.halo,
    speed: 1,
    balls: [0.72],
  ),
  // Orbita stretta azzurra, inclinata verso destra.
  _OrbitSpec(
    radius: 0.80,
    tilt: 1.24,
    roll: 0.47,
    wobble: 0.07,
    wobblePhase: 2.1,
    stroke: 0.012,
    style: _OrbitStyle.light,
    speed: 1,
    balls: [0.0, 0.5],
  ),
  // Orbita stretta bianca, inclinata verso sinistra, verso opposto.
  _OrbitSpec(
    radius: 0.80,
    tilt: 1.20,
    roll: -0.55,
    wobble: 0.07,
    wobblePhase: 4.2,
    stroke: 0.013,
    style: _OrbitStyle.white,
    speed: -1,
    balls: [0.18, 0.68],
  ),
];

class _Ball {
  _Ball(this.pos, this.depth);
  final Offset pos;
  final double depth;
}

class _OrbitLogo3DPainter extends CustomPainter {
  _OrbitLogo3DPainter({
    required this.front,
    required this.iconSize,
    required this.progress,
    required this.accent,
    required this.cyan,
    required this.pulse,
  });

  final bool front;
  final double iconSize;
  final double progress;
  final Color accent;
  final Color cyan;
  final double pulse;

  static const Color _navy = Color(0xFF1E3A5F);
  static const int _trailSteps = 12;
  static const double _trailStep = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    final s = iconSize;
    final c = size.center(Offset.zero);
    final t = progress * math.pi * 2;

    if (!front) _paintIconShadow(canvas, c, s);

    final balls = <_Ball>[];
    final lightBlue = Color.lerp(cyan, Colors.white, 0.28)!;
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final o in _orbits) {
      final roll = o.roll + o.wobble * math.sin(t + o.wobblePhase);
      final a = o.radius * s;
      final b = a * math.cos(o.tilt);
      final ext = a + s * 0.2;
      final cosR = math.cos(roll);
      final sinR = math.sin(roll);

      // Meta' orbita (dietro: y locale < 0, davanti: y locale >= 0).
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(roll);
      canvas.clipRect(
        front
            ? Rect.fromLTRB(-ext, 0, ext, ext)
            : Rect.fromLTRB(-ext, -ext, ext, 0),
      );
      _paintRing(canvas, o, a, b, s, lightBlue);

      // Scie luminose dietro le palline (tagliate dalla stessa meta').
      final dir = o.speed.sign.toDouble();
      for (final phase in o.balls) {
        final theta = (phase + o.speed * progress) * math.pi * 2;
        for (var k = 0; k < _trailSteps; k++) {
          final t0 = theta - dir * k * _trailStep;
          final t1 = theta - dir * (k + 1) * _trailStep;
          final fade = 1 - k / _trailSteps;
          final depthK = (math.sin(t0) + 1) / 2;
          trailPaint
            ..strokeWidth = math.max(s * o.stroke, 1.0) * (1 + 1.6 * fade)
            ..color = Colors.white.withValues(
              alpha: (0.15 + 0.55 * depthK) * fade * fade,
            );
          canvas.drawLine(
            Offset(a * math.cos(t0), b * math.sin(t0)),
            Offset(a * math.cos(t1), b * math.sin(t1)),
            trailPaint,
          );
        }
      }
      canvas.restore();

      // Palline di questa meta' (posizione in coordinate schermo).
      for (final phase in o.balls) {
        final theta = (phase + o.speed * progress) * math.pi * 2;
        final depth = math.sin(theta);
        if ((depth >= 0) != front) continue;
        final lx = a * math.cos(theta);
        final ly = b * depth;
        balls.add(
          _Ball(
            Offset(c.dx + lx * cosR - ly * sinR, c.dy + lx * sinR + ly * cosR),
            depth,
          ),
        );
      }
    }

    // Dal piu' lontano al piu' vicino.
    balls.sort((x, y) => x.depth.compareTo(y.depth));
    for (final ball in balls) {
      _paintBall(canvas, ball.pos, ball.depth, s);
    }
  }

  void _paintIconShadow(Canvas canvas, Offset c, double s) {
    final p = s * pulse;
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: p * 0.92, height: p * 0.92),
      Radius.circular(p * 0.22),
    );
    // Ombra a terra morbida.
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(0, s * 0.66),
        width: s * 0.95,
        height: s * 0.12,
      ),
      Paint()
        ..color = _navy.withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
    );
    // Ombra portata sotto l'icona.
    canvas.drawRRect(
      plate.shift(Offset(0, s * 0.055)),
      Paint()
        ..color = _navy.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.07),
    );
    // Bagliore azzurro attorno alla placca.
    canvas.drawRRect(
      plate.inflate(s * 0.02),
      Paint()
        ..color = cyan.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06),
    );
  }

  void _paintRing(
    Canvas canvas,
    _OrbitSpec o,
    double a,
    double b,
    double s,
    Color lightBlue,
  ) {
    final oval = Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2);
    // Gradiente lungo l'asse minore locale = profondita' (dietro -> davanti).
    Shader depthShader(Color back, Color frontColor) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [back, frontColor],
        ).createShader(oval);

    // Minimi in pixel: nitido anche come mini logo (32-64 px).
    final minW = switch (o.style) {
      _OrbitStyle.halo => 1.0,
      _OrbitStyle.light => 1.4,
      _OrbitStyle.white => 1.5,
    };
    final w = math.max(s * o.stroke, minW);
    final col = Color.lerp(cyan, Colors.white, 0.45)!;
    switch (o.style) {
      case _OrbitStyle.halo:
        canvas.drawOval(
          oval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..shader = depthShader(
              col.withValues(alpha: 0.30),
              col.withValues(alpha: 0.85),
            ),
        );
      case _OrbitStyle.light:
        if (front) {
          canvas.drawOval(
            oval,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 3.2
              ..color = cyan.withValues(alpha: 0.22)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.6),
          );
        }
        canvas.drawOval(
          oval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..shader = depthShader(
              accent.withValues(alpha: 0.28),
              lightBlue.withValues(alpha: 0.98),
            ),
        );
      case _OrbitStyle.white:
        // Ombra sottile per staccare il bianco dallo sfondo chiaro.
        canvas.drawOval(
          oval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 2.4
            ..shader = depthShader(
              _navy.withValues(alpha: 0.08),
              _navy.withValues(alpha: 0.22),
            )
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.9),
        );
        canvas.drawOval(
          oval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..shader = depthShader(
              Colors.white.withValues(alpha: 0.55),
              Colors.white,
            ),
        );
    }
  }

  void _paintBall(Canvas canvas, Offset p, double depth, double s) {
    final k = (depth + 1) / 2; // 0 = dietro, 1 = davanti
    final r = math.max(s * (0.024 + 0.018 * k), 1.6 + 1.6 * k);
    final alpha = 0.45 + 0.55 * k;

    canvas.drawCircle(
      p.translate(0, r * 0.6),
      r * 1.05,
      Paint()
        ..color = _navy.withValues(alpha: 0.22 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
    canvas.drawCircle(
      p,
      r * 2.6,
      Paint()
        ..color = cyan.withValues(alpha: 0.30 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.4),
    );
    final rim = Color.lerp(cyan, Colors.white, 0.55)!;
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [
            Colors.white.withValues(alpha: alpha),
            const Color(0xFFEAF6FF).withValues(alpha: alpha),
            rim.withValues(alpha: alpha),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitLogo3DPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.front != front ||
        oldDelegate.iconSize != iconSize ||
        oldDelegate.pulse != pulse ||
        oldDelegate.accent != accent ||
        oldDelegate.cyan != cyan;
  }
}
