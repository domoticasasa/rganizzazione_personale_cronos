const String viaggiMezziQrPrefix = 'CRONOS-VM:';
const String viaggiMezziQrQueryParam = 'vm';

/// Origine stampata sul QR: la fotocamera del telefono apre questo sito.
const String kViaggioMezzoQrPublicOrigin = 'https://www.gestopro360.it';

/// Payload inviato alle RPC (`CRONOS-VM:{token}`).
String encodeViaggiMezziQrPayload(String token) {
  final t = token.trim();
  if (t.isEmpty) return '';
  if (t.toUpperCase().startsWith(viaggiMezziQrPrefix)) return t;
  return '$viaggiMezziQrPrefix$t';
}

/// Payload stampato sul QR: URL HTTPS così la fotocamera nativa apre GESTOPRO360.
String encodeViaggiMezziQrPrintPayload(String token) {
  final t = parseViaggiMezziQrToken(token);
  if (t == null || t.isEmpty) return '';
  return '$kViaggioMezzoQrPublicOrigin/?$viaggiMezziQrQueryParam=$t';
}

/// Estrae il token da URL `?vm=`, prefisso `CRONOS-VM:` o token nudo.
String? parseViaggiMezziQrToken(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  final fromUri = _tokenFromUriLike(s);
  if (fromUri != null) return fromUri;

  return _stripCronosPrefix(s);
}

String? parseViaggiMezziQrTokenFromUri(Uri uri) {
  final fromQuery = _stripCronosPrefix(
    uri.queryParameters[viaggiMezziQrQueryParam]?.trim() ?? '',
  );
  if (fromQuery != null) return fromQuery;

  final frag = uri.fragment.trim();
  if (frag.isEmpty) return null;
  return _tokenFromUriLike(frag);
}

String? _tokenFromUriLike(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null) {
    final q = uri.queryParameters[viaggiMezziQrQueryParam]?.trim();
    final fromQ = _stripCronosPrefix(q ?? '');
    if (fromQ != null) return fromQ;

    final frag = uri.fragment.trim();
    if (frag.isNotEmpty) {
      final fragQuery = frag.contains('?')
          ? frag.substring(frag.indexOf('?') + 1)
          : frag;
      final vm = Uri.splitQueryString(fragQuery)[viaggiMezziQrQueryParam]?.trim();
      final fromFrag = _stripCronosPrefix(vm ?? '');
      if (fromFrag != null) return fromFrag;
    }
  }

  final match = RegExp(
    r'[?&#]vm=([^&#]+)',
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
  if (upper.startsWith(viaggiMezziQrPrefix.toUpperCase())) {
    s = s.substring(viaggiMezziQrPrefix.length).trim();
  }
  return s.isEmpty ? null : s;
}

String mezzoLabelFromParts({
  required String targa,
  String? marca,
  String? modello,
}) {
  final t = targa.trim();
  final det = [
    if ((marca ?? '').trim().isNotEmpty) marca!.trim(),
    if ((modello ?? '').trim().isNotEmpty) modello!.trim(),
  ].join(' ');
  if (det.isEmpty) return t.isEmpty ? 'Mezzo' : t;
  return t.isEmpty ? det : '$t · $det';
}
