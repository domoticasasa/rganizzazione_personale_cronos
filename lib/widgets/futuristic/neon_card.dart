import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../hub/hub_tile_fonts.dart';
import '../../hub/hub_tile_style.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/gestopro_tap_sound.dart';
import '../hub_tile_auto_fit_text.dart';
import '../neon_orbit_border.dart';
import 'holographic_painters.dart';

/// Pod Nexus — bordo rotante SweepGradient + glow (stile mockup utente).
class NeonCard extends StatefulWidget {
  const NeonCard({
    super.key,
    required this.title,
    required this.color,
    this.icon = Icons.apps_rounded,
    this.iconWidget,
    this.subtitle,
    this.onTap,
    this.tileStyle,
    this.solidBackground = false,
    this.backgroundOpacity = 1.0,
    this.showIconRing = true,
    this.dense = false,
    this.hideIcon = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? iconWidget;
  final Color color;
  final VoidCallback? onTap;
  final HubTileStyle? tileStyle;
  final bool solidBackground;
  final double backgroundOpacity;
  final bool showIconRing;
  final bool dense;
  final bool hideIcon;

  @override
  State<NeonCard> createState() => _NeonCardState();
}

class _NeonCardState extends State<NeonCard> {
  bool _hover = false;

  Widget _buildInner(
    double h,
    double w,
    double iconSize,
    double titleSize,
    double subtitleSize,
    Color accent,
    Color titleColor,
    Color? fillColor,
    bool showSubtitle,
    TextStyle titleStyle,
    TextStyle subtitleStyle,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: widget.solidBackground
              ? (widget.tileStyle?.backgroundColor ??
                      const Color(0xFF061020))
                  .withValues(alpha: widget.backgroundOpacity)
              : (_hover
                  ? accent.withValues(alpha: 0.07)
                  : (fillColor ?? Colors.transparent)),
        ),
        if (!widget.solidBackground)
          CustomPaint(
            painter: SchematicGridPainter(
              opacity: _hover ? 0.05 : 0.025,
              step: math.min(w, h) > 120 ? 16 : 12,
            ),
          ),
        if (widget.showIconRing)
          Center(
            child: Container(
              width: iconSize * 2.2,
              height: iconSize * 2.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            w * (widget.dense ? 0.06 : 0.08),
            h * (widget.dense ? 0.06 : 0.1),
            w * (widget.dense ? 0.06 : 0.08),
            h * (widget.dense ? 0.05 : 0.08),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!widget.hideIcon) ...[
                Flexible(
                  flex: showSubtitle ? 3 : 4,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: widget.iconWidget ??
                          Icon(
                            widget.icon,
                            size: iconSize,
                            color: accent,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: 0.8),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                    ),
                  ),
                ),
                SizedBox(height: h * (widget.dense ? 0.02 : 0.03)),
              ],
              Flexible(
                flex: showSubtitle ? 5 : 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: HubTileAutoFitText(
                        text: widget.title.toUpperCase(),
                        maxLines: 3,
                        minFontSize: 6,
                        maxFontSize: titleSize.clamp(6.0, 50.0),
                        style: titleStyle.copyWith(height: 1.1),
                      ),
                    ),
                    if (showSubtitle) ...[
                      SizedBox(height: h * 0.015),
                      Flexible(
                        child: HubTileAutoFitText(
                          text: widget.subtitle!,
                          maxLines: 3,
                          minFontSize: 5,
                          maxFontSize: subtitleSize.clamp(5.0, titleSize),
                          style: subtitleStyle.copyWith(height: 1.15),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle _resolveTitleStyle(double titleSize, Color titleColor) {
    final key = widget.tileStyle?.fontFamilyKey;
    final base = TextStyle(
      fontSize: titleSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      height: 1.1,
      color: titleColor,
    );
    if (key == null || key == HubTileFonts.keyDefault || key == 'orbitron') {
      return CronosFonts.orbitron(textStyle: base);
    }
    if (key == 'exo2') return CronosFonts.exo2(textStyle: base);
    final family = HubTileFonts.familyForKey(key);
    return base.copyWith(fontFamily: family);
  }

  TextStyle _resolveSubtitleStyle(double subtitleSize, Color accent) {
    final key = widget.tileStyle?.fontFamilyKey;
    final color =
        Color.lerp(accent, Colors.white, 0.45)!.withValues(alpha: 0.75);
    final base = TextStyle(fontSize: subtitleSize, height: 1.15, color: color);
    if (key == 'exo2') return CronosFonts.exo2(textStyle: base);
    if (key == null || key == HubTileFonts.keyDefault || key == 'orbitron') {
      return CronosFonts.exo2(textStyle: base);
    }
    final family = HubTileFonts.familyForKey(key);
    return base.copyWith(fontFamily: family);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final scale = widget.tileStyle?.sizeScale ?? 1.0;
        final iconSize = widget.tileStyle
                ?.resolveIconSize(fillCell: true, scale: scale)
                .clamp(
                  HubTileStyle.minIconFontSize,
                  HubTileStyle.maxIconFontSize,
                ) ??
            (h * 0.26 * scale).clamp(22.0, 56.0);
        final titleSize = widget.tileStyle?.titleFontSize?.clamp(
              HubTileStyle.minTitleFontSize,
              HubTileStyle.maxTitleFontSize,
            ) ??
            (h * 0.088 * scale).clamp(8.0, 18.0);
        final subtitleSize = (titleSize * 0.78).clamp(7.0, 14.0);
        final accent = Color.lerp(
          widget.color,
          CronosFuturisticTheme.borderGlow,
          0.35,
        )!;
        final titleColor =
            widget.tileStyle?.textColor ?? Colors.white.withValues(alpha: 0.96);
        final bg = widget.tileStyle?.backgroundColor;
        final fillColor = bg == null
            ? null
            : (bg.a < 0.99 ? bg : bg.withValues(alpha: 0.35));
        final titleStyle = _resolveTitleStyle(titleSize, titleColor);
        final subtitleStyle = _resolveSubtitleStyle(subtitleSize, accent);
        final showSubtitle =
            widget.subtitle != null && widget.subtitle!.trim().isNotEmpty && h > 96;
        final effectiveIconSize = showSubtitle
            ? (iconSize * 0.85).clamp(16.0, iconSize)
            : iconSize;
        final chamfer = (math.min(w, h) * 0.1).clamp(10.0, 18.0);
        final inner = _buildInner(
          h,
          w,
          effectiveIconSize,
          titleSize,
          subtitleSize,
          accent,
          titleColor,
          fillColor,
          showSubtitle,
          titleStyle,
          subtitleStyle,
        );

        final clipped = ClipPath(
          clipper: ChamferedRectClipper(chamfer: chamfer),
          child: inner,
        );
        final cardBody = AnimatedScale(
          scale: _hover ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: NeonOrbitPaint(
            active: _hover,
            chamfer: chamfer,
            strokeWidth: 3,
            color: accent,
            child: clipped,
          ),
        );

        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: widget.onTap == null
              ? cardBody
              : GestureDetector(
                  onTap: wrapGestoproTap(widget.onTap),
                  child: cardBody,
                ),
        );
      },
    );
  }
}
