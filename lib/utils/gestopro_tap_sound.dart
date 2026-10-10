import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/gestopro_click_sound_service.dart';
import '../../services/gestopro_mode_prefs.dart';

/// Avvolge un'azione UI con il click sci-fi GESTOPRO.
VoidCallback? wrapGestoproTap(VoidCallback? action) {
  if (action == null) return null;
  return () {
    if (GestoproModePrefs.sessionActive) {
      unawaited(GestoproClickSoundService.play());
    }
    action();
  };
}

/// Come [wrapGestoproTap] ma per callback con parametro (es. PopupMenu).
void Function(T)? wrapGestoproTapValue<T>(void Function(T)? action) {
  if (action == null) return null;
  return (T value) {
    if (GestoproModePrefs.sessionActive) {
      unawaited(GestoproClickSoundService.play());
    }
    action(value);
  };
}

/// Per [IconButton.onPressed] / [FilledButton.onPressed].
VoidCallback? wrapGestoproPressed(VoidCallback? action) => wrapGestoproTap(action);
