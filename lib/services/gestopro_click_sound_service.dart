import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../utils/gestopro_audio_loader.dart';

/// Click UI sci-fi per interazioni GESTOPRO.
abstract final class GestoproClickSoundService {
  GestoproClickSoundService._();

  static const _assetPath = 'assets/gestopro_click.mp3';
  static const double clickVolume = 0.55;
  static const _poolSize = 3;

  static final List<AudioPlayer> _players =
      List<AudioPlayer>.generate(_poolSize, (_) => AudioPlayer());
  static int _nextPlayer = 0;
  static bool _poolLoaded = false;
  static bool _poolLoading = false;

  static Future<void> preload() => _ensurePoolLoaded();

  static Future<void> play() async {
    await _ensurePoolLoaded();
    if (!_poolLoaded) return;
    try {
      final player = _players[_nextPlayer];
      _nextPlayer = (_nextPlayer + 1) % _poolSize;
      if (player.playing) {
        await player.stop();
      }
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (_) {
      _poolLoaded = false;
    }
  }

  static Future<void> _ensurePoolLoaded() async {
    if (_poolLoaded || _poolLoading) return;
    _poolLoading = true;
    try {
      for (final player in _players) {
        await loadBundledMp3(player, _assetPath);
        await player.setVolume(clickVolume);
      }
      _poolLoaded = true;
    } catch (_) {
      _poolLoaded = false;
    } finally {
      _poolLoading = false;
    }
  }
}
