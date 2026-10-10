// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;

String readGoogleMapsKeyFromEnvironment() => '';

String readGoogleMapsKeyFromLocalProperties() => '';

/// Chiave impostata in [web/index.html] → `window.CRONOS_GOOGLE_MAPS_API_KEY`.
String readGoogleMapsKeyFromWindow() {
  try {
    return (js.context['CRONOS_GOOGLE_MAPS_API_KEY']?.toString() ?? '').trim();
  } catch (_) {
    return '';
  }
}
