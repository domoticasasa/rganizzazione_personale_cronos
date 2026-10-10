import 'package:flutter/material.dart';

import '../services/app_branding_service.dart';
import '../theme/cronos_futuristic_theme.dart';
import 'futuristic/holographic_painters.dart';

/// Ticker condiviso: un solo controller per i bordi neon in hover.
class NeonOrbitTicker extends StatefulWidget {
  const NeonOrbitTicker({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NeonOrbitScope>()?.animation;

  @override
  State<NeonOrbitTicker> createState() => _NeonOrbitTickerState();
}

class _NeonOrbitTickerState extends State<NeonOrbitTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NeonOrbitScope(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _NeonOrbitScope extends InheritedWidget {
  const _NeonOrbitScope({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  @override
  bool updateShouldNotify(covariant _NeonOrbitScope old) =>
      old.animation != animation;
}

/// Alone neon rotante **sopra** il child, solo in hover. Non cambia colori né layout.
class NeonOrbitHover extends StatefulWidget {
  const NeonOrbitHover({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.chamfer = 0,
    this.strokeWidth = 2.2,
    this.color,
    this.enabled = true,
  });

  final Widget child;
  final double borderRadius;
  final double chamfer;
  final double strokeWidth;
  final Color? color;
  final bool enabled;

  @override
  State<NeonOrbitHover> createState() => _NeonOrbitHoverState();
}

class _NeonOrbitHoverState extends State<NeonOrbitHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onEnter: (_) {
        if (!_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: NeonOrbitPaint(
        active: _hover,
        borderRadius: widget.borderRadius,
        chamfer: widget.chamfer,
        strokeWidth: widget.strokeWidth,
        color: widget.color,
        child: widget.child,
      ),
    );
  }
}

/// Overlay neon che **non** intercetta i tap: il child resta cliccabile.
class NeonOrbitPaint extends StatelessWidget {
  const NeonOrbitPaint({
    super.key,
    required this.child,
    this.active = true,
    this.borderRadius = 14,
    this.chamfer = 0,
    this.strokeWidth = 2.2,
    this.color,
  });

  final Widget child;
  final bool active;
  final double borderRadius;
  final double chamfer;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shared = NeonOrbitTicker.maybeOf(context);
    final glow = color ??
        Color.lerp(
          AppBrandingService.instance.accentColor,
          CronosFuturisticTheme.borderGlow,
          0.35,
        )!;

    Widget overlay(double t) {
      return IgnorePointer(
        child: CustomPaint(
          painter: GlowingBorderPainter(
            animationValue: t,
            color: glow,
            chamfer: chamfer,
            borderRadius: borderRadius,
            strokeWidth: strokeWidth,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        child,
        if (active)
          Positioned.fill(
            child: shared != null
                ? AnimatedBuilder(
                    animation: shared,
                    builder: (context, _) => overlay(shared.value),
                  )
                : _NeonOrbitTickerBox(builder: overlay),
          ),
      ],
    );
  }
}

class _NeonOrbitTickerBox extends StatefulWidget {
  const _NeonOrbitTickerBox({required this.builder});

  final Widget Function(double t) builder;

  @override
  State<_NeonOrbitTickerBox> createState() => _NeonOrbitTickerBoxState();
}

class _NeonOrbitTickerBoxState extends State<_NeonOrbitTickerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(_controller.value),
    );
  }
}

/// Compatibilità: stesso overlay, sempre visibile (es. FAB chat).
class NeonOrbitBorder extends StatelessWidget {
  const NeonOrbitBorder({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.strokeWidth = 2,
    this.color,
    this.enabled = true,
  });

  final Widget child;
  final double borderRadius;
  final double strokeWidth;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return NeonOrbitPaint(
      borderRadius: borderRadius,
      chamfer: 0,
      strokeWidth: strokeWidth,
      color: color,
      child: child,
    );
  }
}
