import 'package:flutter/material.dart';

import 'neon_orbit_border.dart';

/// Decorazione effetto 3D (rilievo + ombra).
/// Nota: con [borderRadius] Flutter non consente bordi a colori diversi per lato.
BoxDecoration cronos3dDecoration({
  required Color baseColor,
  bool pressed = false,
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
}) {
  final dark = baseColor.computeLuminance() < 0.22;
  final highlight = Color.alphaBlend(
    Colors.white.withValues(alpha: dark ? 0.06 : 0.26),
    baseColor,
  );
  final shadowTone = Color.alphaBlend(
    Colors.black.withValues(alpha: dark ? 0.22 : 0.14),
    baseColor,
  );
  return BoxDecoration(
    borderRadius: borderRadius,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: pressed
          ? <Color>[shadowTone, highlight]
          : <Color>[highlight, shadowTone],
    ),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: pressed ? 0.14 : (dark ? 0.38 : 0.32)),
        blurRadius: pressed ? 3 : 11,
        offset: Offset(0, pressed ? 2 : 6),
      ),
      if (!dark)
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.28),
          blurRadius: 0,
          offset: const Offset(-1.5, -1.5),
        ),
    ],
  );
}

/// Rilievo simulato con gradienti (sostituisce il bordo multicolore).
Widget cronos3dBevelOverlay({
  required BorderRadius borderRadius,
  bool pressed = false,
  bool dark = false,
}) {
  if (pressed) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  return Stack(
    fit: StackFit.expand,
    children: <Widget>[
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.6, 0.6),
            colors: <Color>[
              Colors.white.withValues(alpha: dark ? 0.08 : 0.5),
              Colors.transparent,
            ],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: const Alignment(0.4, 0.4),
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.transparent,
              Colors.black.withValues(alpha: 0.16),
            ],
          ),
        ),
      ),
    ],
  );
}

Color cronos3dBaseColor(BuildContext context, {Color? override}) {
  if (override != null) return override;
  return Theme.of(context).colorScheme.surface;
}

/// Superficie/pulsante con effetto 3D (tile hub, home, ecc.).
class Cronos3dSurface extends StatefulWidget {
  const Cronos3dSurface({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.margin = EdgeInsets.zero,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry margin;
  final Clip clipBehavior;

  @override
  State<Cronos3dSurface> createState() => _Cronos3dSurfaceState();
}

class _Cronos3dSurfaceState extends State<Cronos3dSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = cronos3dBaseColor(context, override: widget.color);
    final decoration = cronos3dDecoration(
      baseColor: base,
      pressed: _pressed,
      borderRadius: widget.borderRadius,
    );

    Widget surface = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      margin: widget.margin,
      decoration: decoration,
      clipBehavior: Clip.none,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: cronos3dBevelOverlay(
                borderRadius: widget.borderRadius,
                pressed: _pressed,
                dark: base.computeLuminance() < 0.22,
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: widget.child,
          ),
        ],
      ),
    );

    if (widget.onTap != null) {
      surface = GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: surface,
      );
    }

    return NeonOrbitHover(
      borderRadius: widget.borderRadius.topLeft.x,
      child: surface,
    );
  }
}

/// Stili pulsanti Material con effetto 3D (tema globale).
ButtonStyle cronos3dFilledButtonStyle({
  Color? background,
  Color? foreground,
  bool dark = false,
}) {
  const radius = BorderRadius.all(Radius.circular(14));
  final bg = background ?? const Color(0xFF2F6FED);
  final fg = foreground ?? Colors.white;
  final lift = dark ? 0.05 : 0.12;
  return ButtonStyle(
    elevation: WidgetStateProperty.resolveWith<double>((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return 2;
      return dark ? 4 : 7;
    }),
    shadowColor: WidgetStateProperty.all(
      Colors.black.withValues(alpha: dark ? 0.45 : 0.35),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return bg.withValues(alpha: 0.45);
      }
      if (states.contains(WidgetState.pressed)) {
        return Color.alphaBlend(Colors.black.withValues(alpha: 0.12), bg);
      }
      return Color.alphaBlend(Colors.white.withValues(alpha: lift), bg);
    }),
    foregroundColor: WidgetStateProperty.all(fg),
    side: WidgetStateProperty.resolveWith<BorderSide>((states) {
      if (states.contains(WidgetState.pressed)) {
        return BorderSide(color: Colors.black.withValues(alpha: 0.2), width: 1.2);
      }
      return BorderSide(
        color: Colors.white.withValues(alpha: dark ? 0.14 : 0.35),
        width: 1.2,
      );
    }),
    shape: WidgetStateProperty.all(
      const RoundedRectangleBorder(borderRadius: radius),
    ),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    backgroundBuilder: (context, states, child) {
      final c = child ?? const SizedBox.shrink();
      return NeonOrbitPaint(
        active: states.contains(WidgetState.hovered) &&
            !states.contains(WidgetState.disabled),
        borderRadius: 999,
        child: c,
      );
    },
  );
}

ButtonStyle cronos3dElevatedButtonStyle({
  Color? background,
  Color? foreground,
  bool dark = false,
}) {
  return cronos3dFilledButtonStyle(
    background: background ??
        (dark ? const Color(0xFF1B2430) : const Color(0xFFECECEC)),
    foreground: foreground ??
        (dark ? const Color(0xFFE6ECF5) : const Color(0xFF2F6FED)),
    dark: dark,
  );
}

ButtonStyle cronos3dOutlinedButtonStyle({
  Color? foreground,
  Color? background,
  bool dark = false,
}) {
  final fg = foreground ??
      (dark ? const Color(0xFFE6ECF5) : const Color(0xFF2F6FED));
  final bg = background ??
      (dark
          ? const Color(0xFF1B2430)
          : Colors.white.withValues(alpha: 0.92));
  return ButtonStyle(
    elevation: WidgetStateProperty.resolveWith<double>((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return 1;
      return dark ? 2 : 4;
    }),
    shadowColor: WidgetStateProperty.all(
      Colors.black.withValues(alpha: dark ? 0.40 : 0.22),
    ),
    foregroundColor: WidgetStateProperty.all(fg),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.pressed)) {
        return fg.withValues(alpha: dark ? 0.12 : 0.08);
      }
      return bg;
    }),
    side: WidgetStateProperty.all(
      BorderSide(
        color: dark ? Colors.white.withValues(alpha: 0.14) : fg,
        width: 1.2,
      ),
    ),
    shape: WidgetStateProperty.all(
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    backgroundBuilder: (context, states, child) {
      final c = child ?? const SizedBox.shrink();
      return NeonOrbitPaint(
        active: states.contains(WidgetState.hovered) &&
            !states.contains(WidgetState.disabled),
        borderRadius: 999,
        child: c,
      );
    },
  );
}
