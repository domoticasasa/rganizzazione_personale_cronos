import 'dart:io';

String readGoogleMapsKeyFromWindow() => '';

String readGoogleMapsKeyFromEnvironment() {
  return (Platform.environment['GOOGLE_MAPS_API_KEY'] ?? '').trim();
}

String readGoogleMapsKeyFromLocalProperties() {
  try {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      final pubspec = File('${dir.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        final file = File('${dir.path}/android/local.properties');
        if (!file.existsSync()) return '';
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.startsWith('google.maps.api.key=')) {
            return trimmed.substring('google.maps.api.key='.length).trim();
          }
        }
        return '';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  } catch (_) {}
  return '';
}
