import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/gestopro_audio_loader.dart';

/// Sottofondo sonoro sci-fi in loop durante la sessione GESTOPRO.
abstract final class GestoproAmbientSoundService {
  GestoproAmbientSoundService._();

  static const _assetPath = 'assets/gestopro_ambient.mp3';
  static const _mutePrefKey = 'gestopro_ambient_muted';

  /// Volume molto basso — sottofondo non invasivo.
  static const double ambientVolume = 0.07;

  static final AudioPlayer _player = AudioPlayer();
  static final ValueNotifier<bool> muted = ValueNotifier(false);
  static bool _loaded = false;
  static bool _loading = false;
  static bool _shouldPlay = false;
  static bool _muteLoaded = false;

  static bool get isMuted => muted.value;

  static Future<void> loadMutePreference() async {
    if (_muteLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    muted.value = prefs.getBool(_mutePrefKey) ?? false;
    _muteLoaded = true;
  }

  static Future<void> setMuted(bool value) async {
    await loadMutePreference();
    if (muted.value == value) {
      await _applyPlayback();
      return;
    }
    muted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutePrefKey, value);
    await _applyPlayback();
  }

  static Future<void> toggleMuted() => setMuted(!isMuted);

  static Future<void> syncWithSession(bool gestoproActive) async {
    await loadMutePreference();
    _shouldPlay = gestoproActive;
    if (gestoproActive) {
      await _start();
    } else {
      await _stop();
    }
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await loadBundledMp3(_player, _assetPath);
      await _player.setLoopMode(LoopMode.one);
      _loaded = true;
      if (muted.value || !_shouldPlay) {
        await _player.setVolume(0);
        await _player.stop();
      } else {
        await _player.setVolume(ambientVolume);
      }
    } catch (_) {
      _loaded = false;
    } finally {
      _loading = false;
    }
  }

  static Future<void> _waitForLoading() async {
    while (_loading) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  /// Applica mute/play in base a [muted] e [_shouldPlay].
  static Future<void> _applyPlayback() async {
    await _waitForLoading();
    if (!_loaded) {
      if (_shouldPlay && !muted.value) {
        await _ensureLoaded();
      }
      if (!_loaded) return;
    }

    try {
      if (muted.value || !_shouldPlay) {
        await _player.setVolume(0);
        await _player.stop();
        return;
      }

      await _player.setVolume(ambientVolume);
      if (!_player.playing) {
        await _player.play();
      }
      // Se nel frattempo l'utente ha silenziato, ferma subito.
      if (muted.value || !_shouldPlay) {
        await _player.stop();
        await _player.setVolume(0);
      }
    } catch (_) {
      // no-op
    }
  }

  static Future<void> _start() async {
    if (!_shouldPlay || muted.value) return;
    await _ensureLoaded();
    await _applyPlayback();
  }

  static Future<void> _stop() async {
    try {
      await _player.stop();
      await _player.setVolume(0);
    } catch (_) {
      // no-op
    }
  }
}
