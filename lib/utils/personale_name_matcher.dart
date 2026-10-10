/// Abbinamento nome/cognome da import (senza terzo nome) con anagrafica personale.
abstract final class PersonaleNameMatcher {
  PersonaleNameMatcher._();

  static String normalize(String raw) {
    var s = raw.trim().toLowerCase();
    const map = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
      'œ': 'oe',
      'æ': 'ae',
    };
    for (final e in map.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    s = s.replaceAll(RegExp(r"[^a-z0-9\s']"), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static List<String> tokens(String raw) {
    final n = normalize(raw);
    if (n.isEmpty) return const [];
    return n.split(' ').where((t) => t.length >= 2).toList(growable: false);
  }

  /// Ogni token dell'import deve comparire nei token anagrafica (consente terzo nome in DB).
  static bool importMatchesFullName({
    required String cognomeImport,
    required String nomeImport,
    required String fullNameDb,
  }) {
    final imp = <String>{
      ...tokens(cognomeImport),
      ...tokens(nomeImport),
    };
    if (imp.isEmpty) return false;
    final db = tokens(fullNameDb);
    if (db.isEmpty) return false;

    bool tokenHit(String t) {
      for (final d in db) {
        if (d == t) return true;
        if (t.length >= 4 && d.startsWith(t)) return true;
        if (d.length >= 4 && t.startsWith(d)) return true;
      }
      return false;
    }

    return imp.every(tokenHit);
  }

  static String? findBestPersonaleId({
    required String cognomeImport,
    required String nomeImport,
    required Map<String, String> personaleById,
  }) {
    final candidates = <String>[];
    for (final entry in personaleById.entries) {
      if (importMatchesFullName(
        cognomeImport: cognomeImport,
        nomeImport: nomeImport,
        fullNameDb: entry.value,
      )) {
        candidates.add(entry.key);
      }
    }
    if (candidates.length == 1) return candidates.first;
    if (candidates.length > 1) {
      final imp = normalize('$cognomeImport $nomeImport');
      String? best;
      var bestScore = -1;
      for (final id in candidates) {
        final db = normalize(personaleById[id] ?? '');
        var score = 0;
        if (db == imp) score += 100;
        if (db.contains(imp) || imp.contains(db)) score += 50;
        for (final t in tokens('$cognomeImport $nomeImport')) {
          if (db.split(' ').contains(t)) score += 10;
        }
        if (score > bestScore) {
          bestScore = score;
          best = id;
        }
      }
      return best;
    }
    return null;
  }

  /// Nominativo dislocazione (es. `DAVI' FILIPPO`, `D'ALBENZI CRISTIAN`) → id personale.
  static String? findPersonaleIdByNominativoDislocazione(
    String nominativo,
    Map<String, String> personaleById,
  ) {
    final t = nominativo.trim();
    if (t.isEmpty || personaleById.isEmpty) return null;

    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final nome = parts.last;
      final cognome = parts.sublist(0, parts.length - 1).join(' ');
      final id = findBestPersonaleId(
        cognomeImport: cognome,
        nomeImport: nome,
        personaleById: personaleById,
      );
      if (id != null) return id;
    }

    final norm = normalize(t);
    for (final entry in personaleById.entries) {
      if (normalize(entry.value) == norm) return entry.key;
    }

    final imp = tokens(t);
    if (imp.isNotEmpty) {
      final hits = <String>[];
      for (final entry in personaleById.entries) {
        final db = tokens(entry.value);
        if (db.isEmpty) continue;
        if (imp.every((tok) {
          return db.any((d) => d == tok || (tok.length >= 3 && d.startsWith(tok)) || (d.length >= 3 && tok.startsWith(d)));
        })) {
          hits.add(entry.key);
        }
      }
      if (hits.length == 1) return hits.first;
    }

    if (parts.length == 1) {
      return findBestPersonaleId(
        cognomeImport: parts.first,
        nomeImport: parts.first,
        personaleById: personaleById,
      );
    }
    return null;
  }
}
