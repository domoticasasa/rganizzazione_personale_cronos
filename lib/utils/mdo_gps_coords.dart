import 'package:http/http.dart' as http;

/// Coordinate GPS da colonne numeriche o testo `posizione_gps` (es. "GPS: 41.9, 12.5").
(double, double)? mdoGpsCoordsFromRow(Map<String, dynamic> row) {
  final latRaw = row['latitudine'];
  final lonRaw = row['longitudine'];
  final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
  final lon = lonRaw is num ? lonRaw.toDouble() : double.tryParse('$lonRaw');
  if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
    return (lat, lon);
  }
  return mdoGpsCoordsFromText((row['posizione_gps'] ?? '').toString());
}

/// Normalizza testo incollato da Google Maps (anche su due righe).
String normalizeGpsCoordsText(String text) {
  return text
      .replaceAll('GPS:', '')
      .replaceAll(RegExp(r'[()\[\]]'), ' ')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

(double, double)? mdoGpsCoordsFromText(String text) {
  final cleaned = normalizeGpsCoordsText(text);
  if (cleaned.isEmpty) return null;

  final patterns = <RegExp>[
    RegExp(r'(-?\d+(?:\.\d+)?)\s*[,;]\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(cleaned);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) continue;
    if (lat.abs() > 90 || lon.abs() > 180) continue;
    return (lat, lon);
  }
  return null;
}

/// Coordinate da link Google Maps, risolvendo anche gli short link
/// (`maps.app.goo.gl`, `goo.gl/maps`) seguendo il redirect all'URL completo.
/// Su web il redirect può essere bloccato da CORS: in quel caso restituisce
/// solo ciò che è estraibile dal link così com'è.
Future<(double, double)?> mdoResolveGpsFromMapsLink(String? url) async {
  final text = (url ?? '').trim();
  if (text.isEmpty) return null;

  final direct = mdoGpsCoordsFromMapsLink(text);
  if (direct != null) return direct;

  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || !_isShortMapsLink(uri)) return null;

  if (_shortLinkCache.containsKey(text)) return _shortLinkCache[text];

  (double, double)? resolved;
  try {
    final expanded = await _expandShortUrl(uri);
    if (expanded != null) resolved = mdoGpsCoordsFromMapsLink(expanded);
  } catch (_) {
    resolved = null;
  }
  _shortLinkCache[text] = resolved;
  return resolved;
}

final Map<String, (double, double)?> _shortLinkCache =
    <String, (double, double)?>{};

bool _isShortMapsLink(Uri uri) {
  final host = uri.host.toLowerCase();
  return host.contains('goo.gl') || host == 'g.co' || host.endsWith('.g.co');
}

/// Segue i redirect (max 5) e ritorna il primo URL che contiene coordinate,
/// altrimenti l'URL finale.
Future<String?> _expandShortUrl(Uri uri) async {
  final client = http.Client();
  try {
    var current = uri;
    for (var i = 0; i < 5; i++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; CronosApp/1.0)';
      final response = await client.send(request);
      await response.stream.drain<void>();
      final location = response.headers['location'];
      final isRedirect = response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null &&
          location.isNotEmpty;
      if (!isRedirect) {
        return current.toString();
      }
      current = current.resolve(location);
      if (mdoGpsCoordsFromMapsLink(current.toString()) != null) {
        return current.toString();
      }
    }
    return current.toString();
  } finally {
    client.close();
  }
}

/// Coordinate da link Google Maps (`structures.maps_link` o testo incollato).
(double, double)? mdoGpsCoordsFromMapsLink(String? url) {
  final text = (url ?? '').trim();
  if (text.isEmpty) return null;

  final fromText = mdoGpsCoordsFromText(text);
  if (fromText != null) return fromText;

  final atMatch = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(text);
  if (atMatch != null) {
    final lat = double.tryParse(atMatch.group(1)!);
    final lon = double.tryParse(atMatch.group(2)!);
    if (lat != null &&
        lon != null &&
        lat.abs() <= 90 &&
        lon.abs() <= 180) {
      return (lat, lon);
    }
  }

  final uri = Uri.tryParse(text);
  if (uri != null) {
    for (final key in const ['query', 'q', 'll', 'center']) {
      final value = uri.queryParameters[key];
      if (value == null || value.trim().isEmpty) continue;
      final coords = mdoGpsCoordsFromText(value);
      if (coords != null) return coords;
    }
  }
  return null;
}

/// Testo canonico per DB / UI: `lat, lon`.
String formatGpsCoordsText(double lat, double lon) =>
    '${lat.toStringAsFixed(8)}, ${lon.toStringAsFixed(8)}';

/// MDO ferroviari tipo A: sigla `matricola_interna` che inizia con "A" (es. A31).
bool isMdoTipoA(Map<String, dynamic> row) {
  final sigla = (row['matricola_interna'] ?? '').toString().trim().toUpperCase();
  if (sigla.isEmpty) return false;
  return RegExp(r'^A\d').hasMatch(sigla);
}
