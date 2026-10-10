import 'package:flutter/material.dart';

/// Scope condiviso per animare i numeri da zero al valore finale (solo Gestopro).
class GestoproCountUpScope extends StatefulWidget {
  const GestoproCountUpScope({
    super.key,
    required this.child,
    required this.enabled,
    this.restartKey,
    this.duration = const Duration(milliseconds: 950),
  });

  final Widget child;
  final bool enabled;
  final Object? restartKey;
  final Duration duration;

  /// Progresso 0→1; fuori scope o con animazione disabilitata restituisce 1.
  static double progressOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_GestoproCountUpScopeData>();
    if (scope == null || !scope.enabled) return 1.0;
    return scope.progress;
  }

  @override
  State<GestoproCountUpScope> createState() => _GestoproCountUpScopeState();
}

class _GestoproCountUpScopeState extends State<GestoproCountUpScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _startIfEnabled();
  }

  void _startIfEnabled() {
    if (widget.enabled) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant GestoproCountUpScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (!widget.enabled) {
      _controller.value = 1.0;
      return;
    }
    if (!oldWidget.enabled && widget.enabled) {
      _controller.forward(from: 0);
      return;
    }
    if (oldWidget.restartKey != widget.restartKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return _GestoproCountUpScopeData(
          enabled: widget.enabled,
          progress: widget.enabled ? _curve.value : 1.0,
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}

class _GestoproCountUpScopeData extends InheritedWidget {
  const _GestoproCountUpScopeData({
    required this.enabled,
    required this.progress,
    required super.child,
  });

  final bool enabled;
  final double progress;

  @override
  bool updateShouldNotify(_GestoproCountUpScopeData oldWidget) =>
      oldWidget.progress != progress || oldWidget.enabled != enabled;
}

/// Testo numerico che segue il progresso dello [GestoproCountUpScope].
class GestoproCountUpText extends StatelessWidget {
  const GestoproCountUpText({
    super.key,
    required this.target,
    required this.format,
    this.style,
    this.textAlign,
  });

  final double target;
  final String Function(double animatedValue) format;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final progress = GestoproCountUpScope.progressOf(context);
    return Text(
      format(target * progress),
      style: style,
      textAlign: textAlign,
    );
  }
}
