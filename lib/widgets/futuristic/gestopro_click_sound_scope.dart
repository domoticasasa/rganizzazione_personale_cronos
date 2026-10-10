import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/gestopro_click_sound_service.dart';
import '../../services/gestopro_mode_prefs.dart';

/// Riproduce il click sci-fi su pulsanti e controlli tappabili in GESTOPRO.
class GestoproClickSoundScope extends StatefulWidget {
  const GestoproClickSoundScope({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<GestoproClickSoundScope> createState() =>
      _GestoproClickSoundScopeState();
}

class _GestoproClickSoundScopeState extends State<GestoproClickSoundScope> {
  static const _tapSlop = 18.0;

  Offset? _pointerDown;
  int? _activePointer;

  void _onPointerDown(PointerDownEvent event) {
    if (!GestoproModePrefs.sessionActive) return;
    if (event.buttons != kPrimaryButton) return;
    _activePointer = event.pointer;
    _pointerDown = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!GestoproModePrefs.sessionActive) return;
    if (_activePointer != event.pointer) return;

    final down = _pointerDown;
    _activePointer = null;
    _pointerDown = null;
    if (down == null) return;
    if ((event.position - down).distance > _tapSlop) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final global = box.localToGlobal(event.localPosition);
    if (!_hitInteractiveControl(global)) return;

    unawaited(GestoproClickSoundService.play());
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _pointerDown = null;
  }

  bool _hitInteractiveControl(Offset globalPosition) {
    final result = HitTestResult();
    final view = View.of(context);
    WidgetsBinding.instance.hitTestInView(result, globalPosition, view.viewId);

    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) continue;
      if (target is RenderIgnorePointer && target.ignoring) continue;
      if (target is RenderAbsorbPointer && target.absorbing) continue;
      if (target is RenderEditable) return false;
      if (_isLikelyButtonTarget(target)) return true;
    }
    return false;
  }

  bool _isLikelyButtonTarget(RenderObject target) {
    final type = target.runtimeType.toString();
    return type.contains('InkResponse') || type.contains('_RenderInputPadding');
  }

  @override
  Widget build(BuildContext context) {
    if (!GestoproModePrefs.sessionActive) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
