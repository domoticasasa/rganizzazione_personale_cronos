import 'package:flutter/foundation.dart';

import 'gestopro_splash_sound_io.dart'
    if (dart.library.html) 'gestopro_splash_sound_web.dart' as impl;

/// Audio intro splash GESTOPRO (web: HTML Audio; desktop/mobile: just_audio).
abstract final class GestoproSplashSound {
  GestoproSplashSound._();

  static const assetPath = 'assets/gestopro_splash_intro.mp3';

  static Future<void> prepare() => impl.prepareSplashIntro();

  static Future<void> play() => impl.playSplashIntro();

  static Future<void> stop() => impl.stopSplashIntro();
}

void debugSplashSound(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('>>> Splash audio: $message');
  }
}
