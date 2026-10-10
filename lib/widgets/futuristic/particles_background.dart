import 'package:flutter/material.dart';

import '../../theme/cronos_futuristic_theme.dart';
import 'holographic_painters.dart';

/// Sfondo volumetrico: aurora, griglia, treno, particelle.
class ParticlesBackground extends StatefulWidget {
  const ParticlesBackground({super.key});

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.2, -0.3),
                  radius: 1.4,
                  colors: [
                    Color(0xFF0A2040),
                    Color(0xFF020814),
                    Color(0xFF000408),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: AuroraPainter(t: _tick.value)),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.14,
                child: CustomPaint(
                  painter: const SchematicGridPainter(opacity: 0.4, step: 28),
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.16,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    CronosFuturisticTheme.electricBright.withValues(alpha: 0.7),
                    BlendMode.modulate,
                  ),
                  child: Image.asset(
                    'assets/bg_train_landscape.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: AmbientParticlesPainter(t: _tick.value, count: 72),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      CronosFuturisticTheme.voidBg.withValues(alpha: 0.55),
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
