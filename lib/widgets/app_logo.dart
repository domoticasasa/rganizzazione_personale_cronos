import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Titolo app bar con logo Gestopro360 integrato.
class ResponsiveAppBarTitle extends StatelessWidget {
  final String title;
  final bool showIcon;

  const ResponsiveAppBarTitle({
    super.key,
    required this.title,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 640;
    return Row(
      children: [
        if (showIcon) ...[
          const GestoproAppIcon(size: 30),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrapper pagina con logo brand in alto e contenuto sotto.
class PageWithTopLogo extends StatelessWidget {
  final Widget child;
  final bool showBrandHeader;

  const PageWithTopLogo({
    super.key,
    required this.child,
    this.showBrandHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBrandHeader) return child;
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              GestoproAppIcon(size: 34),
              SizedBox(width: 10),
              _BrandText(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: child),
      ],
    );
  }
}

class _BrandText extends StatelessWidget {
  const _BrandText();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2947A9), Color(0xFF2CCAF2)],
          ).createShader(bounds),
          child: const Text(
            'GESTOPRO360',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Text(
          'Sempre aggiornate. Con un solo clic.',
          style: TextStyle(
            fontSize: 10.5,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Splash intro in stile premium con animazioni "video-like".
class GestoproIntroSplash extends StatefulWidget {
  final double iconSize;

  const GestoproIntroSplash({
    super.key,
    this.iconSize = 150,
  });

  @override
  State<GestoproIntroSplash> createState() => _GestoproIntroSplashState();
}

class _GestoproIntroSplashState extends State<GestoproIntroSplash>
    with TickerProviderStateMixin {
  late final AnimationController _revealCtrl;
  late final AnimationController _loopCtrl;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..forward();
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _revealCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.iconSize.clamp(120.0, 190.0).toDouble();
    return AnimatedBuilder(
      animation: Listenable.merge([_revealCtrl, _loopCtrl]),
      builder: (context, _) {
        final reveal = Curves.easeOutCubic.transform(_revealCtrl.value);
        final breathe = 0.5 + 0.5 * math.sin(_loopCtrl.value * 2 * math.pi);
        final iconScale = 0.88 + (0.12 * reveal) + (0.018 * breathe);
        final contentYOffset = (1 - reveal) * 36;
        final titleShift = (_loopCtrl.value * 2) - 1;

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PremiumSplashBackdropPainter(
                  t: _loopCtrl.value,
                  reveal: reveal,
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: reveal,
                child: Transform.translate(
                  offset: Offset(0, contentYOffset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: iconSize * 1.9,
                        height: iconSize * 1.58,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Transform.scale(
                              scale: 1.06 + (0.07 * breathe),
                              child: Container(
                                width: iconSize * 1.42,
                                height: iconSize * 1.42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2ADAF4)
                                          .withValues(alpha: 0.14 + (0.12 * breathe)),
                                      blurRadius: 46 + (24 * breathe),
                                      spreadRadius: 8 + (6 * breathe),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: _loopCtrl.value * 2 * math.pi * 0.27,
                              child: CustomPaint(
                                size: Size(iconSize * 1.33, iconSize * 1.33),
                                painter: _OrbitSweepPainter(glow: breathe),
                              ),
                            ),
                            Transform.scale(
                              scale: iconScale,
                              child: GestoproAppIcon(size: iconSize),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment(-1.1 + (titleShift * 0.20), -1),
                          end: Alignment(1.1 + (titleShift * 0.20), 1),
                          colors: const [
                            Color(0xFF243F97),
                            Color(0xFF3D6DE6),
                            Color(0xFF2ADAF4),
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'GESTOPRO360',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Tutte le informazioni che contano.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF304164),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sempre aggiornate. Con un solo clic.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF355080),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PremiumSplashBackdropPainter extends CustomPainter {
  final double t;
  final double reveal;

  const _PremiumSplashBackdropPainter({
    required this.t,
    required this.reveal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseRect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF8FBFF),
          Color(0xFFEDF4FF),
          Color(0xFFE9F1FF),
        ],
      ).createShader(baseRect);
    canvas.drawRect(baseRect, basePaint);

    void drawGlow({
      required Offset center,
      required double radius,
      required Color color,
      required double alpha,
    }) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }

    final p1 = Offset(
      size.width * (0.18 + (0.05 * math.sin((t * 2 * math.pi) + 0.4))),
      size.height * (0.23 + (0.03 * math.cos(t * 2 * math.pi))),
    );
    final p2 = Offset(
      size.width * (0.84 + (0.05 * math.cos((t * 2 * math.pi) + 0.9))),
      size.height * (0.76 + (0.04 * math.sin((t * 2 * math.pi) + 0.6))),
    );
    final p3 = Offset(
      size.width * (0.52 + (0.02 * math.sin((t * 2 * math.pi) + 1.8))),
      size.height * (0.48 + (0.03 * math.cos((t * 2 * math.pi) + 2.2))),
    );

    drawGlow(
      center: p1,
      radius: size.shortestSide * 0.34,
      color: const Color(0xFF75B6FF),
      alpha: 0.26 * reveal,
    );
    drawGlow(
      center: p2,
      radius: size.shortestSide * 0.30,
      color: const Color(0xFF66E0FA),
      alpha: 0.24 * reveal,
    );
    drawGlow(
      center: p3,
      radius: size.shortestSide * 0.26,
      color: const Color(0xFF4B78ED),
      alpha: 0.16 * reveal,
    );

    final highlightTop = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.55 * reveal),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.3));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.3), highlightTop);
  }

  @override
  bool shouldRepaint(covariant _PremiumSplashBackdropPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.reveal != reveal;
  }
}

class _OrbitSweepPainter extends CustomPainter {
  final double glow;

  const _OrbitSweepPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = math.max(2.0, size.width * 0.022);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFB6D7FF).withValues(alpha: 0.46 + (0.20 * glow));
    canvas.drawCircle(center, radius, base);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 0.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF4D77EF),
          Color(0xFF2ADAF4),
        ],
      ).createShader(rect);
    const startAngle = -2.14;
    const sweepAngle = 2.56;
    canvas.drawArc(rect, startAngle, sweepAngle, false, arc);

    final arrowAngle = startAngle + sweepAngle;
    final tip = Offset(
      center.dx + math.cos(arrowAngle) * radius,
      center.dy + math.sin(arrowAngle) * radius,
    );
    final side = stroke * 1.35;
    final wingA = Offset(
      tip.dx - math.cos(arrowAngle - 0.55) * side,
      tip.dy - math.sin(arrowAngle - 0.55) * side,
    );
    final wingB = Offset(
      tip.dx - math.cos(arrowAngle + 0.55) * side,
      tip.dy - math.sin(arrowAngle + 0.55) * side,
    );
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(wingA.dx, wingA.dy)
      ..lineTo(wingB.dx, wingB.dy)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = const Color(0xFF2ADAF4).withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitSweepPainter oldDelegate) {
    return oldDelegate.glow != glow;
  }
}

/// Mostra splash introduttiva con auto-chiusura.
Future<void> showGestoproIntroSplash(
  BuildContext context, {
  Duration duration = const Duration(milliseconds: 2500),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'intro-splash',
    barrierColor: const Color(0xD9F5F8FF),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => _AutoCloseSplash(duration: duration),
    transitionBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _AutoCloseSplash extends StatefulWidget {
  final Duration duration;

  const _AutoCloseSplash({required this.duration});

  @override
  State<_AutoCloseSplash> createState() => _AutoCloseSplashState();
}

class _AutoCloseSplashState extends State<_AutoCloseSplash> {
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _closeTimer = Timer(widget.duration, () {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: GestoproIntroSplash(),
    );
  }
}

class GestoproAppIcon extends StatelessWidget {
  final double size;

  const GestoproAppIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GestoproIconPainter(),
      ),
    );
  }
}

/// Riproduzione vettoriale semplificata dell'icona "combo":
/// documento/check + monogramma G360.
class _GestoproIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF142768), Color(0xFF1C5DC3)],
      ).createShader(rect);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.22));
    canvas.drawRRect(outer, bgPaint);

    final center = Offset(size.width / 2, size.height / 2);
    final discRadius = size.width * 0.33;
    final discPaint = Paint()..color = const Color(0xFFF7FBFF);
    canvas.drawCircle(center, discRadius, discPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width * 0.028)
      ..color = const Color(0xFFA8CBF9);
    canvas.drawCircle(center, discRadius * 0.88, ringPaint);

    final arcRect = Rect.fromCircle(center: center, radius: discRadius * 0.89);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.8, size.width * 0.034)
      ..shader = const LinearGradient(
        colors: [Color(0xFF436FF0), Color(0xFF2ADAF4)],
      ).createShader(arcRect);
    canvas.drawArc(arcRect, 3.9, 4.4, false, arcPaint);

    final arrow = Path()
      ..moveTo(size.width * 0.28, size.height * 0.63)
      ..lineTo(size.width * 0.23, size.height * 0.73)
      ..lineTo(size.width * 0.34, size.height * 0.71)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF2ADAF4));

    final docRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.31,
        size.height * 0.34,
        size.width * 0.17,
        size.height * 0.24,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(
      docRect,
      Paint()..color = const Color(0xFFEEF4FF),
    );
    canvas.drawRRect(
      docRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size.width * 0.009)
        ..color = const Color(0xFF9FC3F2),
    );

    final linePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.width * 0.013)
      ..color = const Color(0xFFA2BFEB);
    final l1y = size.height * 0.40;
    final l2y = size.height * 0.435;
    final l3y = size.height * 0.47;
    canvas.drawLine(Offset(size.width * 0.34, l1y), Offset(size.width * 0.43, l1y), linePaint);
    canvas.drawLine(Offset(size.width * 0.34, l2y), Offset(size.width * 0.42, l2y), linePaint);
    canvas.drawLine(Offset(size.width * 0.34, l3y), Offset(size.width * 0.425, l3y), linePaint);

    final checkPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.016)
      ..color = const Color(0xFF16B77B);
    final check = Path()
      ..moveTo(size.width * 0.34, size.height * 0.53)
      ..lineTo(size.width * 0.37, size.height * 0.56)
      ..lineTo(size.width * 0.45, size.height * 0.49);
    canvas.drawPath(check, checkPaint);

    final dividerPaint = Paint()
      ..color = const Color(0xFFA7C8F5).withValues(alpha: 0.65);
    final dividerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.34,
        math.max(1.2, size.width * 0.01),
        size.height * 0.24,
      ),
      Radius.circular(size.width * 0.01),
    );
    canvas.drawRRect(dividerRect, dividerPaint);

    final gStyle = TextStyle(
      color: const Color(0xFF2747A0),
      fontWeight: FontWeight.w800,
      fontSize: size.width * 0.20,
      height: 1.0,
    );
    final tG = TextPainter(
      text: TextSpan(text: 'G', style: gStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tG.paint(canvas, Offset(size.width * 0.56, size.height * 0.39));

    final nStyle = TextStyle(
      color: const Color(0xFF2F8DDE),
      fontWeight: FontWeight.w800,
      fontSize: size.width * 0.10,
      height: 1.0,
    );
    final tN = TextPainter(
      text: TextSpan(text: '360', style: nStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tN.paint(canvas, Offset(size.width * 0.59, size.height * 0.53));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
