import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../utils/gestopro_tap_sound.dart';
import '../cronos_futuristic_tile.dart';
import 'command_center_painters.dart';

/// Hub centrale CRONOS con globo GPS (mockup).
class CronosHubCore extends StatelessWidget {
  const CronosHubCore({
    super.key,
    required this.t,
    this.gpsTile,
  });

  final double t;
  final CronosFuturisticTile? gpsTile;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: wrapGestoproTap(gpsTile?.onTap),
      child: Column(
        children: [
          Text(
            'CRONOS',
            style: CronosFonts.audiowide(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 22,
              letterSpacing: 6,
              shadows: const [
                Shadow(color: Color(0xFF00E5FF), blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: HubGlobePainter(t: t),
                ),
                if (gpsTile != null)
                  Positioned(
                    bottom: 8,
                    child: Text(
                      gpsTile!.label,
                      style: CronosFonts.montserrat(
                        fontSize: 10,
                        color: const Color(0xFF00E5FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: HubPedestalPainter(t: t),
                ),
                Positioned(
                  top: 12,
                  child: Text(
                    'CRONOS HUB',
                    style: CronosFonts.montserrat(
                      fontSize: 9,
                      letterSpacing: 2,
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
