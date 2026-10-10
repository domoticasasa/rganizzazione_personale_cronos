import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Suono di conferma per feedback positivi (snackbar verde).
class ConfirmSoundService {
  ConfirmSoundService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _loaded = false;
  static bool _loading = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await _player.setAsset('assets/Conferma.mp3');
      _loaded = true;
    } catch (_) {
      _loaded = false;
    } finally {
      _loading = false;
    }
  }

  static Future<void> play() async {
    await _ensureLoaded();
    if (!_loaded) return;
    try {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } catch (_) {
      // no-op
    }
  }
}
