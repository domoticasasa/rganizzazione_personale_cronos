import 'package:flutter/material.dart';

import '../../theme/cronos_futuristic_theme.dart';
import 'holographic_painters.dart';

/// Contenitore con bordo luminoso rotante (stesso effetto dei pulsanti hub).
class GlowingBorderShell extends StatefulWidget {
  const GlowingBorderShell({
    super.key,
    required this.child,
    this.color = CronosFuturisticTheme.neonCyan,
    this.strokeWidth = 2,
    this.chamfer = 0,
    this.borderRadius = 0,
    this.margin,
    this.duration = const Duration(seconds: 4),
  });

  final Widget child;
  final Color color;
  final double strokeWidth;
  final double chamfer;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final Duration duration;

  @override
  State<GlowingBorderShell> createState() => _GlowingBorderShellState();
}

class _GlowingBorderShellState extends State<GlowingBorderShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
      builder: (context, child) {
        return Container(
          margin: widget.margin,
          child: CustomPaint(
            painter: GlowingBorderPainter(
              animationValue: _controller.value,
              color: widget.color,
              chamfer: widget.chamfer,
              borderRadius: widget.borderRadius,
              strokeWidth: widget.strokeWidth,
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.strokeWidth),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
