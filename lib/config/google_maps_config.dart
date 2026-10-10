import 'package:flutter/foundation.dart';

import 'google_maps_config_stub.dart'
    if (dart.library.io) 'google_maps_config_io.dart'
    if (dart.library.html) 'google_maps_config_web.dart';

/// Chiave API Google Maps (Maps SDK / JavaScript API).
///
/// Ordine di lettura:
/// 1. `--dart-define=GOOGLE_MAPS_API_KEY=...`
/// 2. Web: `window.CRONOS_GOOGLE_MAPS_API_KEY` in `web/index.html`
/// 3. variabile d'ambiente `GOOGLE_MAPS_API_KEY` (desktop)
/// 4. `google.maps.api.key` in `android/local.properties` (dev desktop/Android)
abstract final class GoogleMapsConfig {
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static String? _cachedResolved;

  static String get resolvedKey {
    if (_cachedResolved != null) return _cachedResolved!;
    final fromDefine = apiKey.trim();
    if (fromDefine.isNotEmpty) {
      _cachedResolved = fromDefine;
      return fromDefine;
    }
    if (kIsWeb) {
      final fromWindow = readGoogleMapsKeyFromWindow();
      if (fromWindow.isNotEmpty) {
        _cachedResolved = fromWindow;
        return fromWindow;
      }
    }
    if (!kIsWeb) {
      final fromEnv = readGoogleMapsKeyFromEnvironment();
      if (fromEnv.isNotEmpty) {
        _cachedResolved = fromEnv;
        return fromEnv;
      }
      final fromLocal = readGoogleMapsKeyFromLocalProperties();
      if (fromLocal.isNotEmpty) {
        _cachedResolved = fromLocal;
        return fromLocal;
      }
    }
    _cachedResolved = '';
    return '';
  }

  static bool get isConfigured {
    if (resolvedKey.isNotEmpty) return true;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      // Chiave nativa in AndroidManifest / Info.plist (GMSApiKey).
      return true;
    }
    return false;
  }
}
