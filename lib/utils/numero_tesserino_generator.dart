/// Regola numero tesserino: 6 lettere (cognome×3 + nome×3) + 5 cifre (SSNNN).
/// Esempio: Patti Giuseppe → **PATGIU** + **01001** (serie 01, progressivo 001).
/// Se esiste già PATGIU01001 per un altro record, il successivo omònimo è **PATGIU02001**.
library;

final RegExp _numeroTesserinoRe = RegExp(r'^([A-Z]{6})(\d{5})$');

/// Estrae fino a [count] lettere A–Z dal testo (senza accenti).
String tesserinoLetterChunk(String raw, int count) {
  if (count <= 0) return '';
  final buf = StringBuffer();
  final norm = raw
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-ZÀ-ÖØ-Þ]', caseSensitive: false), '');
  for (var i = 0; i < norm.length && buf.length < count; i++) {
    final ch = _asciiLetter(norm[i]);
    if (ch != null) buf.write(ch);
  }
  while (buf.length < count) {
    buf.write('X');
  }
  return buf.toString();
}

String? _asciiLetter(String ch) {
  const map = {
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ä': 'A',
    'Ã': 'A',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Ö': 'O',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ç': 'C',
    'Ñ': 'N',
  };
  if (map.containsKey(ch)) return map[ch];
  if (ch.length == 1 && ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) {
    return ch;
  }
  return null;
}

/// Prefisso da nome completo «COGNOME NOME …» (come in anagrafica CRONOS).
String tesserinoPrefixFromFullName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || (parts.length == 1 && parts.first.isEmpty)) {
    return 'XXXXXX';
  }
  if (parts.length == 1) {
    return '${tesserinoLetterChunk(parts.first, 3)}XXX';
  }
  final cognome = parts.first;
  final nome = parts.sublist(1).join(' ');
  return tesserinoLetterChunk(cognome, 3) + tesserinoLetterChunk(nome, 3);
}

/// Prefisso da cognome + nome separati.
String tesserinoPrefixFromParts({required String cognome, required String nome}) {
  return tesserinoLetterChunk(cognome, 3) + tesserinoLetterChunk(nome, 3);
}

/// Serie (2 cifre) e progressivo (3 cifre) da suffisso numerico o null se non valido.
({int serie, int seq})? parseTesserinoSuffix(String numero) {
  final m = _numeroTesserinoRe.firstMatch(numero.trim().toUpperCase());
  if (m == null) return null;
  final digits = m.group(2)!;
  return (serie: int.parse(digits.substring(0, 2)), seq: int.parse(digits.substring(2)));
}

/// Prossimo numero libero: incrementa la **serie** (01→02→…), progressivo sempre 001.
String nextNumeroTesserino({
  required String prefix,
  required Iterable<String> existingNumeri,
}) {
  final p = prefix.trim().toUpperCase();
  var maxSerie = 0;
  for (final raw in existingNumeri) {
    final code = raw.trim().toUpperCase();
    if (!code.startsWith(p)) continue;
    final parsed = parseTesserinoSuffix(code);
    if (parsed == null) continue;
    if (parsed.serie > maxSerie) maxSerie = parsed.serie;
  }
  final nextSerie = (maxSerie + 1).clamp(1, 99);
  return '$p${nextSerie.toString().padLeft(2, '0')}001';
}

bool isDuplicateTesserinoError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('personale_numero_tesserino_unique') ||
      s.contains('duplicate key') && s.contains('numero_tesserino');
}
