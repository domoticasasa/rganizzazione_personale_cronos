import 'package:just_audio/just_audio.dart';

import '../utils/gestopro_audio_loader.dart';
import 'gestopro_splash_sound.dart';

AudioPlayer? _player;
bool _loaded = false;

Future<void> prepareSplashIntro() async {
  if (_loaded) return;
  try {
    _player ??= AudioPlayer();
    try {
      await loadBundledMp3(_player!, GestoproSplashSound.assetPath);
    } catch (_) {
      await _player!.setAsset(GestoproSplashSound.assetPath);
    }
    await _player!.setVolume(1.0);
    _loaded = true;
    debugSplashSound('preparato (just_audio)');
  } catch (e) {
    debugSplashSound('prepare fallito: $e');
  }
}

Future<void> playSplashIntro() async {
  await prepareSplashIntro();
  try {
    final player = _player;
    if (player == null) throw StateError('splash player missing');
    await player.seek(Duration.zero);
    await player.play();
    debugSplashSound('play ok (just_audio)');
  } catch (e) {
    debugSplashSound('play fallito: $e');
    rethrow;
  }
}

Future<void> stopSplashIntro() async {
  try {
    await _player?.stop();
  } catch (_) {}
}
