import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/cronos_fonts.dart';
import 'gestopro_app_icon.dart';
import 'gestopro_orbit_logo_3d.dart';

/// Palette premium glass Area dipendente (chiaro + scuro).
abstract final class PremiumGlassHubTheme {
  static const Color navy = Color(0xFF14244F);
  static const Color brandBlue = Color(0xFF1565C0);
  static const Color cyan = Color(0xFF00B4F0);
  static const Color glassWhite = Color(0xF2FFFFFF);
  static const Color glassFill = Color(0xCCFFFFFF);
  static const Color italianGreen = Color(0xFF00C853);
  static const Color italianRed = Color(0xFFE30613);
  static const Color bachecaAmber = Color(0xFFFF8F00);
  static const Color darkPanel = Color(0xFF141B28);
  static const Color darkTile = Color(0xFF1A2436);
  static const Color onDark = Color(0xFFE8EEF8);
  static const Color onDarkMuted = Color(0xFFA8B6CC);

  static bool appIsDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color titleColor(BuildContext context) =>
      appIsDark(context) ? onDark : navy;

  static Color subtitleColor(BuildContext context) =>
      appIsDark(context) ? onDarkMuted : const Color(0xFF3E4F6F);

  static Color accentLink(BuildContext context) =>
      appIsDark(context) ? cyan : brandBlue;

  /// Accento di default per chiavi home dipendente (tricolore + moduli).
  static Color? defaultAccentForKey(String? layoutKey) {
    switch (layoutKey) {
      case 'emp_bacheca':
        return const Color(0xFFFF8F00);
      case 'emp_treni':
      case 'emp_richiedi_treno':
        return const Color(0xFF00C853);
      case 'emp_aerei':
      case 'emp_richiedi_aereo':
        return const Color(0xFF78909C);
      case 'emp_tesserino':
        return const Color(0xFFFF1744);
      case 'emp_notifiche':
        return const Color(0xFF2979FF);
      case 'emp_pernottamenti':
        return const Color(0xFF304FFE);
      default:
        if (layoutKey != null && layoutKey.startsWith('custom_hub_')) {
          return const Color(0xFFFFAB00);
        }
        return brandBlue;
    }
  }

  /// Fill tile: bianco glass (mockup 1:1) / dark panel. Accent solo su barra/icona.
  static Color resolveFill({
    required Color? styleBg,
    required String? layoutKey,
    required bool alert,
    bool preferMockup = false,
    bool appDark = false,
  }) {
    if (alert) {
      return appDark
          ? const Color(0x99C62828)
          : const Color(0x66E53935);
    }
    final alpha = appDark ? 0.94 : 0.96;

    // Mockup dipendente: tile bianche (o dark) senza tinta accent sul fill.
    if (preferMockup) {
      return appDark
          ? darkTile.withValues(alpha: alpha)
          : const Color(0xFFFFFFF8).withValues(alpha: alpha);
    }

    final accent = defaultAccentForKey(layoutKey) ?? brandBlue;
    final base = appDark ? darkTile : const Color(0xFFF8FBFF);

    if (styleBg != null) {
      final lum = styleBg.computeLuminance();
      if (lum > 0.08 && lum < 0.95) {
        return Color.lerp(base, styleBg, appDark ? 0.55 : 0.50)!
            .withValues(alpha: alpha);
      }
    }

    // Fallback leggero (desktop pill / non-mockup).
    return Color.lerp(base, accent, appDark ? 0.28 : 0.12)!
        .withValues(alpha: alpha);
  }

  /// Glow bordo azzurro dedicato (es. tile Treni nel mockup).
  static bool highlightGlowForKey(String? layoutKey) {
    return layoutKey == 'emp_treni' || layoutKey == 'emp_richiedi_treno';
  }

  static bool isDarkFill(Color fill) => fill.computeLuminance() < 0.45;

  /// Evita bianco-su-bianco / nero-su-nero da stili salvati.
  static Color contrastSafeOnFill(Color fill, {Color? preferred}) {
    final dark = isDarkFill(fill);
    final fallback = dark ? onDark : navy;
    if (preferred == null) return fallback;
    final delta = (fill.computeLuminance() - preferred.computeLuminance()).abs();
    if (delta < 0.28) return fallback;
    return preferred;
  }

  static Color contrastSafeIcon(Color fill, Color accent, {Color? preferred}) {
    final dark = isDarkFill(fill);
    final fallback = dark ? Colors.white : accent;
    if (preferred == null) return fallback;
    final delta = (fill.computeLuminance() - preferred.computeLuminance()).abs();
    if (delta < 0.22) return fallback;
    return preferred;
  }
}

/// Logo GESTOPRO360 con orbite sferiche 360° (senza sovrapporre il testo).
class GestoproOrbitBrandHeader extends StatefulWidget {
  const GestoproOrbitBrandHeader({
    super.key,
    this.iconSize = 72,
    this.showTitle = true,
    this.showTricolore = true,
  });

  final double iconSize;
  final bool showTitle;
  final bool showTricolore;

  @override
  State<GestoproOrbitBrandHeader> createState() =>
      _GestoproOrbitBrandHeaderState();
}

class _GestoproOrbitBrandHeaderState extends State<GestoproOrbitBrandHeader>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  static const _accent = Color(0xFF1565C0);
  static const _cyan = Color(0xFF00AEEF);
  static const _spinPeriod = 5.6;
  static const _pulsePeriod = 1.6;

  @override
  void initState() {
    super.initState();
    // Tempo continuo: niente 0→1 reset (con speed 0.85/-1.2 le palline scattavano).
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() => _elapsed = elapsed);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.iconSize;
    // Mockup v5: orbite strette intorno all'icona, titolo sotto netto.
    final sphereSize = iconSize * 1.58;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Clip: le orbite non devono coprire titolo/tricolore sotto.
        ClipRect(
          child: SizedBox(
            width: sphereSize,
            height: sphereSize,
            child: Builder(
              builder: (context) {
                final t = _elapsed.inMicroseconds / 1e6;
                final pulseLin = (t / _pulsePeriod) % 2.0;
                final pulseT = pulseLin <= 1.0 ? pulseLin : 2.0 - pulseLin;
                final pulse = Curves.easeInOut.transform(pulseT);
                // 3D: metà orbita dietro → icona → metà orbita davanti
                // (le palline passano sopra/sotto il logo, non restano flat dietro).
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Container(
                      width: sphereSize * 0.88,
                      height: sphereSize * 0.88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _cyan.withValues(alpha: 0.18 + pulse * 0.08),
                            _accent.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    GestoproIconHalo(
                      size: iconSize * 1.02,
                      accent: _accent,
                      cyan: _cyan,
                      intensity: 0.55 + pulse * 0.25,
                    ),
                    // Logo 3D realistico (orbite ellittiche, palline che passano
                    // dietro/davanti all'icona): vedi gestopro_orbit_logo_3d.dart.
                    GestoproOrbitLogo3D(
                      size: sphereSize / GestoproOrbitLogo3D.extentFactor,
                      progress: (t / _spinPeriod) % 1.0,
                      accent: _accent,
                      cyan: _cyan,
                      pulse: 1.0 + pulse * 0.02,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (widget.showTitle) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              return Text(
                'GESTOPRO360',
                textAlign: TextAlign.center,
                style: CronosFonts.orbitron(
                  fontSize: (iconSize * 0.22).clamp(15.0, 20.0),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: PremiumGlassHubTheme.titleColor(context),
                  height: 1,
                ),
              );
            },
          ),
        ],
        if (widget.showTricolore) ...[
          const SizedBox(height: 8),
          const _TricoloreHairline(width: 128),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _TricoloreHairline extends StatelessWidget {
  const _TricoloreHairline({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    // CustomPaint: evita problemi di layout/clip che nascondevano la barra.
    return SizedBox(
      width: width,
      height: 7,
      child: CustomPaint(
        painter: _TricolorePainter(),
      ),
    );
  }
}

class _TricolorePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3.5),
    );
    canvas.save();
    canvas.clipRRect(r);

    final w = size.width / 3;
    final h = size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF009246),
    );
    canvas.drawRect(
      Rect.fromLTWH(w, 0, w, h),
      Paint()..color = const Color(0xFFF1F1F1),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 2, 0, w + 0.5, h),
      Paint()..color = const Color(0xFFCE2B37),
    );
    canvas.restore();

    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFF1A2B5C).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pannello glass (profilo / dialog content).
class PremiumGlassPanel extends StatelessWidget {
  const PremiumGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    final dark = PremiumGlassHubTheme.appIsDark(context);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      PremiumGlassHubTheme.darkPanel.withValues(alpha: 0.88),
                      const Color(0xFF1B2740).withValues(alpha: 0.82),
                      const Color(0xFF101826).withValues(alpha: 0.78),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.82),
                      const Color(0xFFF2F7FF).withValues(alpha: 0.74),
                      const Color(0xFFE6F0FF).withValues(alpha: 0.66),
                    ],
            ),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.85),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: (dark ? Colors.black : PremiumGlassHubTheme.brandBlue)
                    .withValues(alpha: dark ? 0.45 : 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Riga hub glass con glow icona, accent bar e shimmer leggero.
class PremiumGlassHubTile extends StatefulWidget {
  const PremiumGlassHubTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.layoutKey,
    this.backgroundColor,
    this.iconColor,
    this.textColor,
    this.alert = false,
    this.borderRadius = 22,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final String? layoutKey;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? textColor;
  final bool alert;
  final double borderRadius;
  final EdgeInsetsGeometry margin;

  @override
  State<PremiumGlassHubTile> createState() => _PremiumGlassHubTileState();
}

class _PremiumGlassHubTileState extends State<PremiumGlassHubTile>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final AnimationController _pressPulse;
  bool _pressed = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _pressPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pressPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appDark = PremiumGlassHubTheme.appIsDark(context);
    final fill = PremiumGlassHubTheme.resolveFill(
      styleBg: widget.backgroundColor,
      layoutKey: widget.layoutKey,
      alert: widget.alert,
      preferMockup: true,
      appDark: appDark,
    );
    final accentKey =
        PremiumGlassHubTheme.defaultAccentForKey(widget.layoutKey) ??
            PremiumGlassHubTheme.brandBlue;
    final accent = widget.alert ? Colors.redAccent : accentKey;
    final highlight =
        PremiumGlassHubTheme.highlightGlowForKey(widget.layoutKey);
    final titleColor = widget.alert
        ? (appDark ? Colors.redAccent.shade100 : Colors.red.shade700)
        : (appDark
            ? PremiumGlassHubTheme.onDark
            : PremiumGlassHubTheme.navy);
    final subtitleColor = appDark
        ? PremiumGlassHubTheme.onDarkMuted
        : const Color(0xFF6B7A90);
    final r = BorderRadius.circular(widget.borderRadius);
    final active = _pressed || _hover;

    return Padding(
      padding: widget.margin,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _pressed ? 0.975 : (_hover ? 1.015 : 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: Listenable.merge([_shimmer, _pressPulse]),
            builder: (context, _) {
              final t = _shimmer.value;
              final pulse = Curves.easeInOut.transform(_pressPulse.value);
              // Mockup v5: tile vetro bianco, glow soft sull'accento, niente barra laterale piena.
              final glowColor = highlight
                  ? PremiumGlassHubTheme.cyan
                  : accent;
              final glowA = active
                  ? (0.28 + pulse * 0.12)
                  : (highlight ? 0.22 + pulse * 0.08 : 0.14 + pulse * 0.05);
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: r,
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: glowA),
                      blurRadius: active ? 22 : 16,
                      spreadRadius: active ? 0.4 : 0,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: appDark ? 0.30 : 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: r,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onTap,
                        onHighlightChanged: (v) =>
                            setState(() => _pressed = v),
                        borderRadius: r,
                        splashColor: accent.withValues(alpha: 0.12),
                        highlightColor: accent.withValues(alpha: 0.06),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: r,
                            gradient: LinearGradient(
                              begin: Alignment(-1.2 + t * 2.4, -0.5),
                              end: Alignment(0.2 + t * 2.4, 1.1),
                              colors: appDark
                                  ? [
                                      fill,
                                      Color.lerp(fill, accent, 0.08)!,
                                      fill,
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.96),
                                      fill,
                                      Color.lerp(fill, Colors.white, 0.35)!,
                                    ],
                            ),
                            border: Border.all(
                              color: appDark
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.white.withValues(
                                      alpha: active ? 0.98 : 0.88,
                                    ),
                              width: 1.25,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                            child: Row(
                              children: [
                                _GlowIconBadge(
                                  icon: widget.icon,
                                  accent: accent,
                                  onDark: false,
                                  boost: active
                                      ? 1.08 + pulse * 0.12
                                      : 1.0 + pulse * 0.06,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          height: 1.15,
                                          color: titleColor,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      if ((widget.subtitle ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          widget.subtitle!.trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            height: 1.25,
                                            color: subtitleColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: (appDark
                                          ? Colors.white
                                          : PremiumGlassHubTheme.navy)
                                      .withValues(alpha: active ? 0.55 : 0.35),
                                  size: 26,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlowIconBadge extends StatelessWidget {
  const _GlowIconBadge({
    required this.icon,
    required this.accent,
    required this.onDark,
    this.boost = 1.0,
  });

  final IconData icon;
  final Color accent;
  /// Reserved (always white glyph on accent plate in mockup).
  final bool onDark;
  final double boost;

  @override
  Widget build(BuildContext context) {
    final b = boost.clamp(0.7, 1.35);
    // Icona 3D lucida: cerchio colorato + glifo bianco (mockup 1:1).
    return Transform.scale(
      scale: 0.96 + (b - 1) * 0.35,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.05,
            colors: [
              Color.lerp(Colors.white, accent, 0.15)!,
              accent,
              Color.lerp(accent, Colors.black, 0.22)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: (onDark ? 0.55 : 0.75) * b),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.72 * b),
              blurRadius: 18 * b,
              spreadRadius: 1.4 * b,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.35 * b),
              blurRadius: 28 * b,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 24,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog glass chiaro (cartelle / popup Area dipendente).
Future<T?> showPremiumGlassDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: PremiumGlassPanel(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: PremiumGlassHubTheme.brandBlue
                            .withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.folder_special_outlined,
                        color: PremiumGlassHubTheme.brandBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: PremiumGlassHubTheme.titleColor(ctx),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Chiudi',
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        Icons.close_rounded,
                        color: PremiumGlassHubTheme.titleColor(ctx),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _TricoloreHairline(width: 64),
                const SizedBox(height: 14),
                content,
                if (actions != null && actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Bottom sheet glass per scelta cartella.
Future<T?> showPremiumGlassBottomSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: PremiumGlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: PremiumGlassHubTheme.titleColor(ctx),
                          ),
                        ),
                      ),
                      const _TricoloreHairline(width: 48),
                    ],
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Decorazione leggera shimmer per pill desktop.
class PremiumGlassPillShell extends StatefulWidget {
  const PremiumGlassPillShell({
    super.key,
    required this.child,
    required this.background,
    required this.accent,
    this.onPressed,
  });

  final Widget child;
  final Color background;
  final Color accent;
  final VoidCallback? onPressed;

  @override
  State<PremiumGlassPillShell> createState() => _PremiumGlassPillShellState();
}

class _PremiumGlassPillShellState extends State<PremiumGlassPillShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final g = 0.12 + _glow.value * 0.14;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: g),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: widget.background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(28),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Piccolo alone orbitale riutilizzabile (es. FAB).
class PremiumOrbitDots extends StatelessWidget {
  const PremiumOrbitDots({
    super.key,
    required this.progress,
    required this.size,
    this.color = PremiumGlassHubTheme.cyan,
  });

  final double progress;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MiniOrbitPainter(progress: progress, color: color),
    );
  }
}

class _MiniOrbitPainter extends CustomPainter {
  _MiniOrbitPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 2;
    final sweep = progress * math.pi * 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.25),
    );
    for (var i = 0; i < 3; i++) {
      final a = sweep + i * (math.pi * 2 / 3);
      canvas.drawCircle(
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        i == 0 ? 3.2 : 2.0,
        Paint()..color = color.withValues(alpha: i == 0 ? 0.95 : 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
