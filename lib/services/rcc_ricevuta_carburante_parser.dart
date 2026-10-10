/// Dati estratti da screenshot / testo ricevuta carburante (app QT/ENI).
class RccRicevutaParsed {
  const RccRicevutaParsed({
    this.dataGgMmAaaa,
    this.numeroCarta,
    this.litri,
    this.euro,
    this.km,
    this.tipoCarburante,
    this.prodottoOriginale,
    this.note = const [],
  });

  final String? dataGgMmAaaa;
  final String? numeroCarta;
  final String? litri;
  final String? euro;
  final String? km;
  final String? tipoCarburante;
  final String? prodottoOriginale;
  final List<String> note;

  bool get hasAnyField =>
      (dataGgMmAaaa ?? '').isNotEmpty ||
      (numeroCarta ?? '').isNotEmpty ||
      (litri ?? '').isNotEmpty ||
      (euro ?? '').isNotEmpty ||
      (km ?? '').isNotEmpty ||
      (tipoCarburante ?? '').isNotEmpty;
}

abstract final class RccRicevutaCarburanteParser {
  RccRicevutaCarburanteParser._();

  /// Corregge errori tipici OCR prima del parsing.
  static String normalizeOcrText(String raw) {
    var t = raw;
    t = t.replaceAllMapped(
      RegExp(r'(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{4})'),
      (m) => '${m[1]}/${m[2]}/${m[3]}',
    );
    t = t.replaceAllMapped(
      RegExp(r'([lI|])(\d)/(\d{1,2})/(\d{4})'),
      (m) => '1${m[2]}/${m[3]}/${m[4]}',
    );
    t = t.replaceAllMapped(
      RegExp(r'(\d{1,2})/([oO])(\d)/(\d{4})'),
      (m) => '${m[1]}/0${m[3]}/${m[4]}',
    );
    t = _fixCardOcrDigits(t);
    return t;
  }

  static String _fixCardOcrDigits(String text) {
    var t = text.replaceAllMapped(
      RegExp(r'(?:^|[^\dA-Za-z])([7T][Iil1|][O0D]2[\dOolI| \-*xX#•●._]{6,36})'),
      (m) {
        final prefix = m[0]!.substring(0, m[0]!.length - m[1]!.length);
        return '$prefix${_cleanCardToken('7102${m[1]!.substring(4)}')}';
      },
    );
    return t.replaceAllMapped(
      RegExp(r'7102[\dOolI| \-*xX#•●._]{6,36}'),
      (m) => _cleanCardToken(m[0]!),
    );
  }

  static String _cleanCardToken(String raw) {
    var s = raw
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll('.', '*')
        .replaceAll(',', '*')
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('l', '1')
        .replaceAll('I', '1')
        .replaceAll('|', '1');
    s = s.replaceAll(RegExp(r'''[xX#•●"'`=+~°º]'''), '*');
    return s;
  }

  /// Multicard intera o parzialmente coperta (`71020******0648`).
  static bool isCartaMascherata(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return false;
    return RegExp(r'7102\d*\*+\d+').hasMatch(t.replaceAll(RegExp(r'\s'), ''));
  }

  /// Confronta carta completa e scontrino con Multicard censurata.
  static bool carteCompatibili(String a, String b) {
    final na = _normalizeCartaNumber(a);
    final nb = _normalizeCartaNumber(b);
    if (na == null || nb == null) return false;
    if (na == nb) return true;

    final da = na.replaceAll(RegExp(r'\D'), '');
    final db = nb.replaceAll(RegExp(r'\D'), '');
    if (da.isNotEmpty && da == db) return true;

    final maskA = isCartaMascherata(na);
    final maskB = isCartaMascherata(nb);
    if (maskA && !maskB) return _maskedMatchesFull(na, db);
    if (maskB && !maskA) return _maskedMatchesFull(nb, da);
    if (maskA && maskB) {
      return _maskPrefix(na) == _maskPrefix(nb) &&
          _maskSuffix(na) == _maskSuffix(nb);
    }

    const minSuffix = 8;
    if (da.length < minSuffix || db.length < minSuffix) return false;
    if (da.length > db.length && da.endsWith(db)) return true;
    if (db.length > da.length && db.endsWith(da)) return true;
    return false;
  }

  static String _maskPrefix(String masked) {
    final m = RegExp(r'^(7102\d*)\*+').firstMatch(masked);
    return (m?.group(1) ?? '').toLowerCase();
  }

  static String _maskSuffix(String masked) {
    final m = RegExp(r'\*+(\d+)$').firstMatch(masked);
    return m?.group(1) ?? '';
  }

  static bool _maskedMatchesFull(String masked, String fullDigits) {
    final prefix = _maskPrefix(masked);
    final suffix = _maskSuffix(masked);
    if (prefix.length < 4 || suffix.length < 3) return false;
    if (prefix.length + suffix.length < 8) return false;
    return fullDigits.startsWith(prefix) && fullDigits.endsWith(suffix);
  }

  static RccRicevutaParsed parse(String raw) {
    final text = normalizeOcrText(raw.replaceAll('\r', '\n'));
    final lines = _expandTwoColumnLines(
      text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
    );

    final note = <String>[];
    var data = _findLabeledValue(
      lines,
      labels: const ['data', 'data transazione', 'data rifornimento'],
    );
    data ??= _findDateInline(text);
    if (data != null) {
      data = _extractDatePart(data);
    }

    var carta = _normalizeCartaNumber(_findEniliveMulticard(lines));
    carta ??= _normalizeCartaNumber(
      _findLabeledValue(
        lines,
        labels: const [
          'carta',
          'n° carta',
          'numero carta',
          'scheda',
          'multicard',
        ],
        accept: _looksLikeCardToken,
      ),
    );
    carta ??= _normalizeCartaNumber(_findCartaNearScad(text, lines));
    carta ??= _normalizeCartaNumber(_findCartaInline(text));
    carta ??= _normalizeCartaNumber(_findMaskedCardNumber(text));
    carta ??= _normalizeCartaNumber(_findLongCardNumber(text));

    var litri = _findLabeledValue(
      lines,
      labels: const ['quantità', 'quantita', 'volume', 'litri'],
    );
    litri = _extractLitri(
      litri ??
          _findLitriInline(text) ??
          _findLitriScontrino(text) ??
          _findLitriFallback(text),
    );

    var euro = _findLabeledValue(
      lines,
      labels: const ['importo', 'totale', 'amount'],
    );
    euro ??= _findEuroInline(text) ??
        _findEuroScontrino(text) ??
        _findEuroFallback(text);
    euro = _normalizeDecimalIt(euro);

    var km = _findLabeledValue(
      lines,
      labels: const [
        'km percorsi',
        'km/ore',
        'chilometri',
        'odometro',
      ],
    );
    km ??= _findKmInline(text) ??
        _findKmScontrino(text) ??
        _findKmFallback(text);
    km = _digitsOnly(km);

    final prodotto = _findLabeledValue(
      lines,
      labels: const ['prodotto', 'tipo carburante', 'carburante'],
    );
    final tipo = mapProdottoToTipoRcc(prodotto ?? _guessProdottoFromText(text));

    if (carta == null) {
      note.add('Numero carta non rilevato.');
    } else if (isCartaMascherata(carta)) {
      note.add(
        'Multicard parzialmente coperta sullo scontrino: verifica il numero.',
      );
    }
    if (data == null) note.add('Data non rilevata.');
    if (litri == null) note.add('Litri non rilevati.');
    if (euro == null) note.add('Importo non rilevato.');

    if (tipo == null) note.add('Tipo carburante non rilevato.');

    return RccRicevutaParsed(
      dataGgMmAaaa: data,
      numeroCarta: carta,
      litri: litri,
      euro: euro,
      km: km,
      tipoCarburante: tipo,
      prodottoOriginale: prodotto,
      note: note,
    );
  }

  static String? mapProdottoToTipoRcc(String? raw) {
    final u = (raw ?? '').trim().toUpperCase();
    if (u.isEmpty) return null;
    if (u.contains('ADBLUE') || u.contains('AD BLUE')) return 'AdBlue';
    if (u.contains('HVO')) return 'HVO';
    if (u.contains('DIESEL') ||
        u.contains('GASOLIO') ||
        u.contains('GAS OIL')) {
      return 'Gasolio';
    }
    if (u.contains('BENZINA') ||
        u.contains('BENZSP') ||
        u.contains('BENZ SP') ||
        u.contains('BENZ5P') ||
        u.contains('UNLEADED') ||
        u.contains('SENZA PIOMBO') ||
        u.contains('NORMALE') ||
        u.contains('PETROL') ||
        u.contains('BENZ')) {
      return 'Benzina';
    }
    return null;
  }

  static List<String> _expandTwoColumnLines(List<String> lines) {
    final out = <String>[];
    for (final line in lines) {
      final parts = line.split(RegExp(r'\s{2,}|\t+'));
      if (parts.length == 2) {
        final left = parts[0].trim();
        final right = parts[1].trim();
        if (left.isNotEmpty && right.isNotEmpty && left.length <= 36) {
          out.add(left);
          out.add(right);
          continue;
        }
      }
      out.add(line);
    }
    return out;
  }

  static String? _findLabeledValue(
    List<String> lines, {
    required List<String> labels,
    bool Function(String value)? accept,
  }) {
    bool ok(String? v) {
      if (v == null) return false;
      final t = v.trim();
      if (t.isEmpty) return false;
      return accept == null || accept(t);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      for (final label in labels) {
        if (lower == label) {
          for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
            if (_isCardNoiseLine(lines[j])) continue;
            if (ok(lines[j])) return lines[j].trim();
          }
          continue;
        }
        final prefix = '$label:';
        final prefixSp = '$label :';
        if (lower.startsWith(prefix)) {
          final v = line.substring(prefix.length).trim();
          if (ok(v)) return v;
        }
        if (lower.startsWith(prefixSp)) {
          final v = line.substring(prefixSp.length).trim();
          if (ok(v)) return v;
        }
        final sameLine = RegExp(
          '^${RegExp.escape(label)}\\s+(.+)\$',
          caseSensitive: false,
        ).firstMatch(line);
        if (sameLine != null) {
          final v = sameLine.group(1)!.trim();
          if (ok(v)) return v;
          if (i + 1 < lines.length &&
              !_isCardNoiseLine(lines[i + 1]) &&
              ok(lines[i + 1])) {
            return lines[i + 1].trim();
          }
        }
        final twoCol = RegExp(
          '^${RegExp.escape(label)}\\s{2,}(.+)\$',
          caseSensitive: false,
        ).firstMatch(line);
        if (twoCol != null) {
          final v = twoCol.group(1)!.trim();
          if (ok(v)) return v;
        }
      }
    }
    return null;
  }

  static String? _findDateInline(String text) {
    final nearData = RegExp(
      r'data\s*[:\s]+(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (nearData != null) return nearData.group(1);
    return RegExp(r'(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4})')
        .firstMatch(text)
        ?.group(1);
  }

  static String? _findCartaInline(String text) {
    final nearCarta = RegExp(
      r'(?:n[°º.]?\s*)?(?:carta|multicard|routex)\s*[:\s]+([0-9*][0-9\s\-*xX•●.]{6,32})',
      caseSensitive: false,
    ).firstMatch(text);
    if (nearCarta != null) {
      return _normalizeCartaNumber(nearCarta.group(1));
    }
    return null;
  }

  /// Enilive: riga «MULTICARD ROUTEX» e sotto `71020******0648`.
  static String? _findEniliveMulticard(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_isMulticardLabel(lines[i])) continue;
      for (var j = i; j <= i + 3 && j < lines.length; j++) {
        if (_isCardNoiseLine(lines[j])) continue;
        final got = _normalizeCartaNumber(lines[j]);
        if (got != null) return got;
      }
    }
    return null;
  }

  static bool _isMulticardLabel(String line) {
    return RegExp(
      r'mult[il1]card|routex|route\s*x',
      caseSensitive: false,
    ).hasMatch(line);
  }

  /// Scontrino Enilive: PAN subito sopra «SCAD 07/31» (anche sulla stessa riga OCR).
  static String? _findCartaNearScad(String text, List<String> lines) {
    final near = RegExp(
      r'(7102[\dOolI|*xX#•●._, ]{4,24})\s*scad',
      caseSensitive: false,
    ).firstMatch(text);
    if (near != null) {
      final got = _normalizeCartaNumber(near.group(1));
      if (got != null) return got;
    }
    final digitsBeforeScad = RegExp(
      r'(7102\d{4,12})\D{0,12}scad',
      caseSensitive: false,
    ).firstMatch(text.replaceAll(RegExp(r'[\s\-*xX#•●._]'), ''));
    if (digitsBeforeScad != null) {
      final got = _normalizeCartaNumber(digitsBeforeScad.group(1));
      if (got != null) return got;
    }
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toLowerCase().contains('scad')) continue;
      final before = lines[i]
          .split(RegExp(r'scad', caseSensitive: false))
          .first;
      final fromSame = _normalizeCartaNumber(before);
      if (fromSame != null) return fromSame;
      for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
        if (_isCardNoiseLine(lines[j])) continue;
        final got = _normalizeCartaNumber(lines[j]);
        if (got != null) return got;
      }
    }
    return null;
  }

  static bool _isCardNoiseLine(String line) {
    if (RegExp(r'(^|[^0-9])7102').hasMatch(line)) return false;
    final l = line.toLowerCase();
    return l.contains('aid') ||
        l.contains('a000') ||
        l.contains('scad') ||
        l.contains('chip') ||
        l.contains('codice aut') ||
        l.contains('numero doc') ||
        l.contains('p.iva') ||
        l.contains('p.i.') ||
        l.contains('bolla') ||
        l.contains('transazione');
  }

  static bool _looksLikeCardToken(String raw) {
    if (_isCardNoiseLine(raw)) return false;
    final t = raw.toLowerCase();
    if (t.contains('routex') && !RegExp(r'7102').hasMatch(t)) return false;
    return _normalizeCartaNumber(raw) != null;
  }

  static String? _findLongCardNumber(String text) {
    for (final line in text.split(RegExp(r'\n+'))) {
      if (_isCardNoiseLine(line)) continue;
      final compact = line.replaceAll(RegExp(r'[\s\-]'), '');
      final m = RegExp(r'(7102\d{12,16})\b').firstMatch(compact);
      if (m != null) {
        final n = m.group(1)!;
        if (n.length >= 16 && n.length <= 19) return n;
      }
    }
    return null;
  }

  static String? _findMaskedCardNumber(String text) {
    for (final line in text.split(RegExp(r'\n+'))) {
      if (_isCardNoiseLine(line)) continue;
      final got = _normalizeCartaNumber(line);
      if (got != null && isCartaMascherata(got)) return got;
    }
    final compact = text
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll(RegExp(r'[xX#•●._]'), '*');
    final m = RegExp(r'(7102\d{0,8}\*{2,14}\d{3,8})').firstMatch(compact);
    if (m != null && !_aidContains7102(text, m.group(1)!)) {
      return m.group(1);
    }
    return null;
  }

  static bool _aidContains7102(String text, String candidate) {
    final digits = candidate.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 16) return false;
    final lower = text.toLowerCase();
    return lower.contains('aid') && lower.contains(digits);
  }

  /// Scarta AID EMV, date e frammenti OCR che non sono Multicard.
  static String? _normalizeCartaNumber(String? raw) {
    if (raw == null) return null;
    if (_isCardNoiseLine(raw)) return null;
    var t = raw
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll(RegExp(r'''[xX#•●._"'`,=+~°º]'''), '*');
    t = t.replaceAll(RegExp(r'^[^\d*]+'), '');
    if (RegExp(r'7102\d*\*+\d+').hasMatch(t)) {
      final m = RegExp(r'(7102\d{0,8}\*{2,14}\d{3,8})').firstMatch(t);
      if (m != null) return m.group(1);
    }
    final splitMask = RegExp(r'(7102\d{0,6})\*+(\d{3,6})').firstMatch(t);
    if (splitMask != null) {
      return '${splitMask.group(1)}******${splitMask.group(2)}';
    }
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7102') &&
        digits.length >= 16 &&
        digits.length <= 19) {
      return digits;
    }
    if (digits.startsWith('7102') && digits.length >= 8 && digits.length <= 14) {
      return _inferMaskedFromShort7102(digits);
    }
    final spaced = RegExp(r'(7102\d{1,6})\D+(\d{3,5})\b').firstMatch(raw);
    if (spaced != null) {
      return '${spaced.group(1)}******${spaced.group(2)}';
    }
    return null;
  }

  static String? _inferMaskedFromShort7102(String digits) {
    if (!digits.startsWith('7102')) return null;
    if (digits.length < 8) return null;
    var d = digits;
    // SCAD 07/31 spesso si attacca: 7102006480731
    if (d.length >= 12 &&
        (d.endsWith('0731') ||
            d.endsWith('0831') ||
            d.endsWith('0930') ||
            RegExp(r'0[1-9][0-3]\d$').hasMatch(d))) {
      d = d.substring(0, d.length - 4);
    }
    if (d.length < 8 || d.length > 12) return null;
    final prefixLen = d.length <= 9 ? 5 : 6;
    if (prefixLen + 3 > d.length) return null;
    final prefix = d.substring(0, prefixLen);
    final suffix = d.substring(d.length - 4);
    if (prefix.endsWith(suffix)) return null;
    return '$prefix******$suffix';
  }

  static String? _extractDatePart(String raw) {
    final m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(raw);
    if (m == null) return null;
    final d = m.group(1)!.padLeft(2, '0');
    final mo = m.group(2)!.padLeft(2, '0');
    var y = m.group(3)!;
    if (y.length == 2) y = '20$y';
    final year = int.tryParse(y);
    final month = int.tryParse(mo);
    final day = int.tryParse(d);
    if (year != null && month != null && day != null && month >= 1 && month <= 12) {
      final now = DateTime.now();
      final parsed = DateTime(year, month, day);
      final oneYearAgo = DateTime(now.year - 1, now.month, now.day);
      if (parsed.isBefore(oneYearAgo)) {
        var guessYear = now.year;
        var guess = DateTime(guessYear, month, day);
        if (guess.isAfter(now.add(const Duration(days: 1)))) {
          guessYear = now.year - 1;
          guess = DateTime(guessYear, month, day);
        }
        y = guessYear.toString();
      }
    }
    return '$d/$mo/$y';
  }

  static String? _extractLitri(String? raw) {
    if (raw == null) return null;
    final prefixed = RegExp(r'\bL(?:T|ITRI)?\s*([\d]+[.,]?\d*)', caseSensitive: false)
        .firstMatch(raw);
    if (prefixed != null) return _normalizeDecimalIt(prefixed.group(1));
    final m = RegExp(r'([\d]+[.,]?\d*)\s*L\b', caseSensitive: false)
        .firstMatch(raw);
    if (m != null) return _normalizeDecimalIt(m.group(1));
    return _normalizeDecimalIt(raw);
  }

  static String? _findLitriInline(String text) {
    final m = RegExp(
      r'(?:quantit[aà]|volume|litri)\s*[:\s]*([\d]+[.,]?\d*)\s*L',
      caseSensitive: false,
    ).firstMatch(text);
    return m != null ? _normalizeDecimalIt(m.group(1)) : null;
  }

  static String? _findLitriScontrino(String text) {
    final prefixed = RegExp(
      r'\bL(?:T|ITRI)?\s*([\d]+[.,]\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (prefixed != null) {
      final v = double.tryParse(prefixed.group(1)!.replaceAll(',', '.'));
      if (v != null && v >= 5 && v <= 600) {
        return _normalizeDecimalIt(prefixed.group(1));
      }
    }
    return null;
  }

  static String? _findEuroInline(String text) {
    final importoBlock = RegExp(
      r'importo\s*(?:[:\-]|\s)*(?:eur(?:o)?|€)?\s*([\d]+[.,]\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (importoBlock != null) {
      return _normalizeDecimalIt(importoBlock.group(1));
    }
    final euroSuffix = RegExp(
      r'([\d]+[.,]\d{2})\s*(?:€|euro)\b',
      caseSensitive: false,
    ).firstMatch(text);
    return euroSuffix != null ? _normalizeDecimalIt(euroSuffix.group(1)) : null;
  }

  static String? _findEuroScontrino(String text) {
    final importo = RegExp(
      r'(?:importo|totale|tot\.?)\s*(?:[:\-]|\s)*(?:eur(?:o)?|€)?\s*([\d]+[.,]\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (importo != null) return _normalizeDecimalIt(importo.group(1));
    return null;
  }

  static String? _findLitriFallback(String text) {
    for (final m in RegExp(r'(\d+[.,]\d+)\s*L\b', caseSensitive: false).allMatches(text)) {
      final raw = m.group(1);
      if (raw == null) continue;
      final v = double.tryParse(raw.replaceAll(',', '.'));
      if (v != null && v >= 5 && v <= 600) {
        return _normalizeDecimalIt(raw);
      }
    }
    return null;
  }

  static String? _findEuroFallback(String text) {
    final importo = RegExp(
      r'importo\s{1,}(?:eur(?:o)?|€)?\s*([\d]+[.,]\d{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (importo != null) return _normalizeDecimalIt(importo.group(1));
    String? best;
    var bestVal = -1.0;
    for (final m in RegExp(
      r'([\d]+[.,]\d{2})(?!\d)\s*(?:€|euro|eur)?',
      caseSensitive: false,
    ).allMatches(text)) {
      final raw = m.group(1);
      if (raw == null) continue;
      if (m.end < text.length && RegExp(r'\d').hasMatch(text[m.end])) {
        continue; // 1,990 prezzo unitario
      }
      final before = text.substring(0, m.start);
      if (RegExp(r'\bL\s*$', caseSensitive: false).hasMatch(before)) {
        continue; // litri "L 39,84"
      }
      final v = double.tryParse(raw.replaceAll(',', '.'));
      if (v == null || v < 8 || v > 9999) continue;
      if (v > bestVal) {
        bestVal = v;
        best = raw;
      }
    }
    return best != null ? _normalizeDecimalIt(best) : null;
  }

  static String? _findKmFallback(String text) {
    final near = RegExp(
      r'km\s*percorsi\s{2,}(\d{3,7})',
      caseSensitive: false,
    ).firstMatch(text);
    if (near != null) return near.group(1);
    return null;
  }

  static String? _findKmInline(String text) {
    final m = RegExp(
      r'km\s*percorsi\s*[:\s]*([\d.]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return m?.group(1);
  }

  static String? _findKmScontrino(String text) {
    final m = RegExp(
      r'\bkm\s*[:.\-]?\s*(\d{4,7})\b',
      caseSensitive: false,
    ).firstMatch(text);
    return m?.group(1);
  }

  static String? _guessProdottoFromText(String text) {
    final u = text.toUpperCase();
    if (u.contains('REGULAR UNLEADED') ||
        u.contains('SENZA PIOMBO') ||
        u.contains('BENZSP') ||
        u.contains('BENZ SP') ||
        u.contains('BENZ5P') ||
        u.contains('BENZINA') ||
        u.contains('BENZ') ||
        RegExp(r'2710\s*1245').hasMatch(u)) {
      return 'Regular Unleaded';
    }
    if (u.contains('HVO')) return 'HVO';
    if (u.contains('DIESEL') ||
        u.contains('GASOLIO') ||
        u.contains('GASOL') ||
        u.contains('GAS OIL')) {
      return 'Diesel';
    }
    if (u.contains('ADBLUE') || u.contains('AD BLUE')) return 'AdBlue';
    return null;
  }

  static String? _normalizeDecimalIt(String? raw) {
    if (raw == null) return null;
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'(?:eur(?:o)?|€)', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    final numMatch = RegExp(r'[\d]+[.,]\d{1,3}|\d+').firstMatch(t);
    if (numMatch != null) t = numMatch.group(0)!;
    if (t.isEmpty) return null;
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }
    final v = double.tryParse(t);
    if (v == null) return raw.trim();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String? _digitsOnly(String? raw) {
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'[^\d]'), '');
    return d.isEmpty ? null : d;
  }
}
