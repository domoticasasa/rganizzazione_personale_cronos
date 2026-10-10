import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_branding_service.dart';
import '../utils/cronos_fonts.dart';
import 'gestopro_app_icon.dart';
import 'gestopro_orbit_logo_3d.dart';

/// Intro splash premium Gestopro360 (route `/splash` o overlay).
class GestoproIntroSplash extends StatefulWidget {
  const GestoproIntroSplash({
    super.key,
    this.duration = defaultDuration,
    this.glowIntensity = defaultGlowIntensity,
    this.title = defaultTitle,
    this.lines = defaultLines,
    this.accent,
    this.cyan,
    this.onFinished,
    this.onPointerDown,
  });

  static const Duration defaultDuration = Duration(milliseconds: 2500);
  static const double defaultGlowIntensity = 1.0;
  static const String defaultTitle = 'GESTOPRO360';
  static const List<String> defaultLines = [
    'Tutte le informazioni che contano.',
    'Sempre aggiornate.',
    'Con un solo clic',
  ];

  /// Durata totale visibile prima di [onFinished] (2.3–2.8s, default 2.5s).
  final Duration duration;

  /// 0–1.5 circa: intensità glow di sfondo e alone.
  final double glowIntensity;

  final String title;
  final List<String> lines;
  final Color? accent;
  final Color? cyan;
  final VoidCallback? onFinished;
  final VoidCallback? onPointerDown;

  @override
  State<GestoproIntroSplash> createState() => _GestoproIntroSplashState();
}

class _GestoproIntroSplashState extends State<GestoproIntroSplash>
    with TickerProviderStateMixin {
  static const _exitMs = 380;

  late final AnimationController _master;
  late final AnimationController _orbit;
  late final AnimationController _pulse;
  late final AnimationController _glowDrift;
  Timer? _endTimer;
  bool _finished = false;

  late final Animation<double> _enterFade;
  late final Animation<double> _enterScale;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _exitFade;
  late final Animation<double> _halo;

  @override
  void initState() {
    super.initState();
    final totalMs = widget.duration.inMilliseconds.clamp(2300, 2800);

    _master = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _glowDrift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();

    _enterFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _enterScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.0, 0.32, curve: Curves.easeOutBack),
      ),
    );
    _halo = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.04, 0.42, curve: Curves.easeOut),
    );
    _textFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.30, 0.58, curve: Curves.easeOut),
    );
    _textSlide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.30, 0.58, curve: Curves.easeOutCubic),
      ),
    );
    final exitStart = ((totalMs - _exitMs) / totalMs).clamp(0.82, 0.92);
    _exitFade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _master,
        curve: Interval(exitStart, 1.0, curve: Curves.easeIn),
      ),
    );

    _master.forward();
    _endTimer = Timer(Duration(milliseconds: totalMs), _finish);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    _master.dispose();
    _orbit.dispose();
    _pulse.dispose();
    _glowDrift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branding = AppBrandingService.instance;
    final accent = widget.accent ?? branding.accentColor;
    final cyan = widget.cyan ?? const Color(0xFF00AEEF);
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    final iconSize = (shortest * 0.30).clamp(176.0, 288.0);
    final titleSize = size.width >= 900
        ? 52.0
        : size.width >= 600
            ? 42.0
            : 32.0;
    final glow = widget.glowIntensity.clamp(0.35, 1.6);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onPointerDown?.call(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_master, _orbit, _pulse, _glowDrift]),
        builder: (context, _) {
          final pulse = 1.0 + (_pulse.value * 0.045);
          final enter = _enterFade.value;
          final out = _exitFade.value;
          final opacity = (enter * out).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: _enterScale.value,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFFF4F8FD)),
                  CustomPaint(
                    painter: _PremiumBgPainter(
                      t: _glowDrift.value,
                      accent: accent,
                      cyan: cyan,
                      intensity: glow,
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: iconSize * GestoproOrbitLogo3D.extentFactor,
                            height: iconSize * GestoproOrbitLogo3D.extentFactor,
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                GestoproIconHalo(
                                  size: iconSize,
                                  accent: accent,
                                  cyan: cyan,
                                  intensity: _halo.value * glow * pulse,
                                ),
                                // Logo 3D: orbite ellittiche con palline che
                                // passano dietro/davanti all'icona.
                                GestoproOrbitLogo3D(
                                  size: iconSize,
                                  progress: _orbit.value,
                                  accent: accent,
                                  cyan: cyan,
                                  pulse: pulse,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: _textFade.value,
                            child: Transform.translate(
                              offset: Offset(0, _textSlide.value),
                              child: Column(
                                children: [
                                  Text(
                                    widget.title,
                                    textAlign: TextAlign.center,
                                    style: CronosFonts.orbitron(
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 3.2,
                                      color: const Color(0xFF1E3A5F),
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    width: 128,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      gradient: LinearGradient(
                                        colors: [
                                          cyan.withValues(alpha: 0),
                                          cyan,
                                          accent,
                                          accent.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  ...widget.lines.map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        line,
                                        textAlign: TextAlign.center,
                                        style: CronosFonts.montserrat(
                                          fontSize: size.width >= 900 ? 20 : 16,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                          color: const Color(0xFF4B5563),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Overlay/dialog con la stessa intro (fade + lieve scale in ingresso).
Future<void> showGestoproIntroSplash(
  BuildContext context, {
  Duration duration = GestoproIntroSplash.defaultDuration,
  double glowIntensity = GestoproIntroSplash.defaultGlowIntensity,
  VoidCallback? onFinished,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return GestoproIntroSplash(
        duration: duration,
        glowIntensity: glowIntensity,
        onFinished: () {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
          onFinished?.call();
        },
      );
    },
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PremiumBgPainter extends CustomPainter {
  _PremiumBgPainter({
    required this.t,
    required this.accent,
    required this.cyan,
    required this.intensity,
  });

  final double t;
  final Color accent;
  final Color cyan;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final i = intensity;
    final a = t * math.pi * 2;
    _blob(
      canvas,
      size,
      Offset(
        size.width * (0.50 + 0.10 * math.cos(a)),
        size.height * (0.38 + 0.06 * math.sin(a * 0.8)),
      ),
      size.shortestSide * 0.55,
      cyan.withValues(alpha: 0.16 * i),
    );
    _blob(
      canvas,
      size,
      Offset(
        size.width * (0.72 + 0.08 * math.sin(a)),
        size.height * (0.22 + 0.05 * math.cos(a)),
      ),
      size.shortestSide * 0.38,
      accent.withValues(alpha: 0.10 * i),
    );
    _blob(
      canvas,
      size,
      Offset(
        size.width * (0.22 + 0.07 * math.cos(a * 1.3)),
        size.height * (0.70 + 0.05 * math.sin(a)),
      ),
      size.shortestSide * 0.42,
      cyan.withValues(alpha: 0.08 * i),
    );
  }

  void _blob(Canvas canvas, Size size, Offset c, double r, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumBgPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.accent != accent ||
        oldDelegate.cyan != cyan ||
        oldDelegate.intensity != intensity;
  }
}
