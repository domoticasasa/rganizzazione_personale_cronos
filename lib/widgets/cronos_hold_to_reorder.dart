import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../hub/hub_tile_grid.dart';

/// Dopo [holdDuration] di pressione continua invoca [onHoldComplete].
/// Mostra un anello di progresso come sulla home del telefono.
class CronosHoldToReorderDetector extends StatefulWidget {
  const CronosHoldToReorderDetector({
    super.key,
    required this.enabled,
    required this.onHoldComplete,
    required this.child,
    this.holdDuration = const Duration(seconds: 3),
  });

  final bool enabled;
  final VoidCallback onHoldComplete;
  final Widget child;
  final Duration holdDuration;

  @override
  State<CronosHoldToReorderDetector> createState() =>
      _CronosHoldToReorderDetectorState();
}

class _CronosHoldToReorderDetectorState extends State<CronosHoldToReorderDetector>
    with SingleTickerProviderStateMixin {
  Timer? _armTimer;
  Timer? _timer;
  late final AnimationController _progress;
  Offset? _downPos;
  bool _holding = false;

  static const double _moveCancelSlop = 12;
  /// Ritardo prima di assorbire i pointer: i tap brevi (mouse Windows web) restano cliccabili.
  static const Duration _armDelay = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.holdDuration);
  }

  @override
  void didUpdateWidget(CronosHoldToReorderDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdDuration != widget.holdDuration) {
      _progress.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _start(PointerDownEvent event) {
    if (!widget.enabled) return;
    _armTimer?.cancel();
    _timer?.cancel();
    _downPos = event.position;
    // Non assorbire subito: altrimenti su web desktop il click non arriva all'InkWell.
    _armTimer = Timer(_armDelay, () {
      if (!mounted || _downPos == null) return;
      setState(() => _holding = true);
      _progress.forward(from: 0);
    });
    _timer = Timer(widget.holdDuration, () {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _holding = false);
      _progress.reset();
      _downPos = null;
      widget.onHoldComplete();
    });
  }

  void _cancel() {
    _armTimer?.cancel();
    _timer?.cancel();
    _progress.reset();
    _downPos = null;
    if (_holding) setState(() => _holding = false);
  }

  void _onMove(PointerMoveEvent event) {
    if (_downPos == null) return;
    final delta = event.position - _downPos!;
    if (delta.distance > _moveCancelSlop) _cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _start,
      onPointerMove: _onMove,
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AbsorbPointer(absorbing: _holding, child: widget.child),
          if (_holding)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade700, width: 2),
                    color: Colors.amber.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) {
                          return CircularProgressIndicator(
                            value: _progress.value,
                            strokeWidth: 3,
                            color: Colors.amber.shade800,
                            backgroundColor: Colors.amber.shade100,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Griglia riordinabile trascinando i tile (modalità modifica).
class CronosReorderableTileGrid extends StatelessWidget {
  const CronosReorderableTileGrid({
    super.key,
    required this.crossAxisCount,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.spacing = 12,
    this.childAspectRatio = HubTileGridConfig.cellAspectRatio,
  });

  final int crossAxisCount;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, index) {
        return CronosReorderableGridCell(
          index: index,
          onReorder: onReorder,
          child: itemBuilder(context, index),
        );
      },
    );
  }
}

class CronosReorderableGridCell extends StatelessWidget {
  const CronosReorderableGridCell({
    super.key,
    required this.index,
    required this.onReorder,
    required this.child,
  });

  final int index;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onReorder(d.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          maxSimultaneousDrags: 1,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 120,
              height: 120,
              child: Opacity(opacity: 0.92, child: child),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: child,
          ),
          child: SizedBox.expand(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: highlighted
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Leggero «shake» in modalità riordino (come le icone sulla home).
class CronosJiggleMode extends StatefulWidget {
  const CronosJiggleMode({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<CronosJiggleMode> createState() => _CronosJiggleModeState();
}

class _CronosJiggleModeState extends State<CronosJiggleMode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(CronosJiggleMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final angle = (t - 0.5) * 0.035;
        return Transform.rotate(angle: angle, child: child);
      },
      child: widget.child,
    );
  }
}
