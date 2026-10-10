import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../theme/cronos_futuristic_theme.dart';
import 'holographic_painters.dart';

/// Pannello metriche holographic in basso.
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF131D2F).withValues(alpha: 0.82),
        border: Border.all(
          color: const Color(0xFF2979FF).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: CronosFuturisticTheme.neonBlue.withValues(alpha: 0.2),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: CustomPaint(painter: GlassReflectPainter(opacity: 0.06)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
              _Stat('Utenti online', '128', CronosFuturisticTheme.neonGreen),
              _Stat('Richieste', '23', Color(0xFF2979FF)),
              _Stat('Treni oggi', '14', CronosFuturisticTheme.neonCyan),
              _Stat('Alert', '2', CronosFuturisticTheme.neonRed),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: CronosFonts.audiowide(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: CronosFonts.montserrat(
            color: Colors.white54,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
