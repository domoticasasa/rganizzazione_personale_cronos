const String buoniPastoQrPrefix = 'CRONOS-BP:';
const String buoniPastoQrQueryParam = 'bp';

/// Origine stampata sul QR: la fotocamera del telefono apre questo sito.
const String kBuonoPastoQrPublicOrigin = 'https://www.gestopro360.it';

String encodeBuoniPastoQrPayload(String token) {
  final t = token.trim();
  if (t.isEmpty) return '';
  if (t.toUpperCase().startsWith(buoniPastoQrPrefix)) return t;
  return '$buoniPastoQrPrefix$t';
}

/// Payload stampato sul QR: URL HTTPS così la fotocamera nativa apre GESTOPRO360.
String encodeBuoniPastoQrPrintPayload(String token) {
  final t = parseBuoniPastoQrToken(token);
  if (t == null || t.isEmpty) return '';
  return '$kBuonoPastoQrPublicOrigin/?$buoniPastoQrQueryParam=$t';
}

/// Estrae il token da URL `?bp=`, prefisso `CRONOS-BP:` o token nudo.
String? parseBuoniPastoQrToken(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  final fromUri = _tokenFromUriLike(s);
  if (fromUri != null) return fromUri;

  return _stripCronosPrefix(s);
}

String? parseBuoniPastoQrTokenFromUri(Uri uri) {
  final fromQuery = _stripCronosPrefix(
    uri.queryParameters[buoniPastoQrQueryParam]?.trim() ?? '',
  );
  if (fromQuery != null) return fromQuery;

  final frag = uri.fragment.trim();
  if (frag.isEmpty) return null;
  return _tokenFromUriLike(frag);
}

String? _tokenFromUriLike(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null) {
    final q = uri.queryParameters[buoniPastoQrQueryParam]?.trim();
    final fromQ = _stripCronosPrefix(q ?? '');
    if (fromQ != null) return fromQ;

    final frag = uri.fragment.trim();
    if (frag.isNotEmpty) {
      final fragQuery = frag.contains('?')
          ? frag.substring(frag.indexOf('?') + 1)
          : frag;
      final bp =
          Uri.splitQueryString(fragQuery)[buoniPastoQrQueryParam]?.trim();
      final fromFrag = _stripCronosPrefix(bp ?? '');
      if (fromFrag != null) return fromFrag;
    }
  }

  final match = RegExp(
    r'[?&#]bp=([^&#]+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match != null) {
    return _stripCronosPrefix(Uri.decodeQueryComponent(match.group(1)!.trim()));
  }
  return null;
}

String? _stripCronosPrefix(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  final upper = s.toUpperCase();
  if (upper.startsWith(buoniPastoQrPrefix.toUpperCase())) {
    s = s.substring(buoniPastoQrPrefix.length).trim();
  }
  return s.isEmpty ? null : s;
}

/// Tipo pasto da ora locale (mirror logica SQL Europe/Rome lato client per anteprima).
String tipoPastoFromHour(int hour) {
  if (hour < 17) return 'pranzo';
  return 'cena';
}

String tipoPastoLabel(String tipo) {
  switch (tipo.toLowerCase()) {
    case 'pranzo':
      return 'Pranzo';
    case 'cena':
      return 'Cena';
    default:
      return tipo;
  }
}
