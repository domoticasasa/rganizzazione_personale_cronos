import 'package:flutter/material.dart';
import 'dart:async';

import '../services/app_branding_service.dart';
import '../theme/cronos_app_themes.dart';
import 'neon_orbit_border.dart';

/// Colori stile neumorfico (tema chiaro).
const _kBg = Color(0xFFECECEC);
const _kShadowDark = Color(0xFFBEBEBE);
const _kShadowLight = Color(0xFFFFFFFF);
const _kText = Color(0xFF222222);

BoxDecoration _neoDecoration({
  required bool dark,
  double radius = 14,
  Color? color,
  bool enabled = true,
}) {
  if (dark) {
    final bg = color ?? CronosAppThemes.darkSurfaceHigh;
    return BoxDecoration(
      color: enabled ? bg : bg.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.40),
          offset: const Offset(2, 3),
          blurRadius: 8,
        ),
      ],
    );
  }
  return BoxDecoration(
    color: color ?? _kBg,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: _kShadowDark.withValues(alpha: 0.6),
        offset: const Offset(5, 5),
        blurRadius: 10,
      ),
      BoxShadow(
        color: _kShadowLight.withValues(alpha: 0.9),
        offset: const Offset(-5, -5),
        blurRadius: 10,
      ),
    ],
  );
}

/// Pulsante 3D stile neumorfico (grigio, per azioni secondarie)
class NeoButton extends StatelessWidget {
  final Widget child;
  final FutureOr<void> Function()? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;

  const NeoButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark
        ? (enabled
            ? CronosAppThemes.darkSidebarFg
            : CronosAppThemes.darkSidebarFg.withValues(alpha: 0.4))
        : (enabled ? _kText : _kText.withValues(alpha: 0.4));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: enabled
            ? () {
                // InkWell richiede void Function(); wrappiamo FutureOr.
                final fn = onTap;
                if (fn == null) return;
                final result = fn();
                if (result is Future) {
                  unawaited(result);
                }
              }
            : null,
        child: NeonOrbitHover(
          borderRadius: radius,
          enabled: enabled,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: _neoDecoration(
            dark: dark,
            radius: radius,
            enabled: enabled,
            color: dark
                ? null
                : (enabled ? _kBg : _kBg.withValues(alpha: 0.6)),
          ),
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: IconTheme.merge(
            data: IconThemeData(color: textColor, size: 20),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                    color: textColor,
                  ),
              child: child,
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Pulsante 3D blu (primario) – stesso effetto ombra ma sfondo blu
class NeoFilledButton extends StatelessWidget {
  final Widget child;
  final FutureOr<void> Function()? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;

  const NeoFilledButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppBrandingService.instance.accentColor;
    final onAccent =
        accent.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: enabled
            ? () {
                final fn = onTap;
                if (fn == null) return;
                final result = fn();
                if (result is Future) {
                  unawaited(result);
                }
              }
            : null,
        child: NeonOrbitHover(
          borderRadius: radius,
          enabled: enabled,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: enabled ? accent : accent.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.25),
                offset: const Offset(4, 4),
                blurRadius: 8,
              ),
              if (!dark)
                BoxShadow(
                  color: accent.withValues(alpha: 0.3),
                  offset: const Offset(-2, -2),
                  blurRadius: 6,
                ),
            ],
          ),
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: onAccent,
              fontWeight: FontWeight.w600,
            ),
            child: child,
          ),
        ),
        ),
      ),
    );
  }
}

/// Variante primario con lock anti-doppio-click e spinner automatico.
class NeoAsyncFilledButton extends StatefulWidget {
  final Widget child;
  final FutureOr<void> Function()? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;

  const NeoAsyncFilledButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding,
    this.radius = 14,
  });

  @override
  State<NeoAsyncFilledButton> createState() => _NeoAsyncFilledButtonState();
}

class _NeoAsyncFilledButtonState extends State<NeoAsyncFilledButton> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy || widget.onTap == null) return;
    setState(() => _busy = true);
    try {
      await Future.sync(widget.onTap!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeoFilledButton(
      onTap: _busy ? null : _handleTap,
      padding: widget.padding,
      radius: widget.radius,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : widget.child,
    );
  }
}
