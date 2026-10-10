import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Riga transazione dal file fatturazione QT (Europet / rete carburante).
class QtCarburanteTrxRow {
  final int rigaExcel;
  final String numeroCarta;
  final String prodotto;
  final DateTime dataTransazione;
  final double volume;
  final double importo;
  final String? fileSorgente;

  const QtCarburanteTrxRow({
    required this.rigaExcel,
    required this.numeroCarta,
    required this.prodotto,
    required this.dataTransazione,
    required this.volume,
    required this.importo,
    this.fileSorgente,
  });

  String get isoData =>
      '${dataTransazione.year}-${dataTransazione.month.toString().padLeft(2, '0')}-${dataTransazione.day.toString().padLeft(2, '0')}';

  String get cartaNorm => normCarta(numeroCarta);

  /// Solo cifre (QT e RCC possono avere formattazioni diverse).
  static String normCarta(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) return digits;
    return raw.replaceAll(RegExp(r'\s+'), '').trim();
  }
}

class QtCarburanteParseResult {
  final String? nomeFoglio;
  final List<QtCarburanteTrxRow> righe;
  final String? avviso;
  final String? fileName;

  const QtCarburanteParseResult({
    required this.righe,
    this.nomeFoglio,
    this.avviso,
    this.fileName,
  });
}

class QtCarburanteMergedParseResult {
  final List<QtCarburanteTrxRow> righe;
  final List<String> fileNames;
  final String? avviso;

  const QtCarburanteMergedParseResult({
    required this.righe,
    required this.fileNames,
    this.avviso,
  });
}

/// Mese di riferimento dedotto dalle date transazione nel file QT.
class QtCarburanteMeseRiferimento {
  const QtCarburanteMeseRiferimento({
    required this.anno,
    required this.mese,
  });

  final int anno;
  final int mese;
}

abstract final class QtCarburanteFatturazioneParser {
  QtCarburanteFatturazioneParser._();

  static const _colCarta = 'numero carta';
  static const _colProdotto = 'prodotto';
  static const _colData = 'data transazione';
  static const _colVolume = 'volume';
  static const _colImporto = 'importo';

  static Future<QtCarburanteParseResult> parseFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.xlsx') && !lower.endsWith('.xls')) {
      throw const FormatException('Formato non supportato. Usa un file .xlsx');
    }
    return _parseExcel(bytes, fileName: fileName);
  }

  static QtCarburanteParseResult _parseExcel(
    Uint8List bytes, {
    required String fileName,
  }) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('File Excel senza fogli');
    }
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;
    if (sheet.maxRows == 0) {
      throw const FormatException('Foglio Excel vuoto');
    }

    final headerRow = _findHeaderRow(sheet);
    if (headerRow == null) {
      throw const FormatException(
        'Intestazioni non trovate. Servono: Numero Carta, Prodotto, '
        'Data Transazione, Volume, Importo.',
      );
    }

    final headers = _rowTexts(sheet, headerRow);
    final idxCarta = _colIndex(headers, _colCarta);
    final idxProdotto = _colIndex(headers, _colProdotto);
    final idxData = _colIndex(headers, _colData);
    final idxVolume = _colIndex(headers, _colVolume);
    final idxImporto = _colIndex(headers, _colImporto);

    if (idxCarta == null ||
        idxProdotto == null ||
        idxData == null ||
        idxVolume == null ||
        idxImporto == null) {
      throw const FormatException(
        'Colonne mancanti. Servono: Numero Carta, Prodotto, '
        'Data Transazione, Volume, Importo.',
      );
    }

    final righe = <QtCarburanteTrxRow>[];
    var skipped = 0;
    for (var r = headerRow + 1; r < sheet.maxRows; r++) {
      final carta = _cellStr(sheet, r, idxCarta);
      if (carta.isEmpty) {
        skipped++;
        continue;
      }
      final data = _cellDate(sheet, r, idxData);
      final volume = _cellDouble(sheet, r, idxVolume);
      final importo = _cellDouble(sheet, r, idxImporto);
      if (data == null || volume == null || importo == null) {
        skipped++;
        continue;
      }
      righe.add(
        QtCarburanteTrxRow(
          rigaExcel: r + 1,
          numeroCarta: carta,
          prodotto: _cellStr(sheet, r, idxProdotto),
          dataTransazione: data,
          volume: volume,
          importo: importo,
          fileSorgente: fileName,
        ),
      );
    }

    if (righe.isEmpty) {
      throw const FormatException('Nessuna transazione valida nel file.');
    }

    String? avviso;
    if (skipped > 0) {
      avviso = '$skipped righe saltate (dati incompleti o carta vuota).';
    }

    return QtCarburanteParseResult(
      nomeFoglio: sheetName,
      righe: righe,
      avviso: avviso,
      fileName: fileName,
    );
  }

  /// Unisce 1–2 (o più) file QT evitando righe duplicate identiche.
  static QtCarburanteMergedParseResult mergeParsed(
    List<QtCarburanteParseResult> parts,
  ) {
    if (parts.isEmpty) {
      throw ArgumentError('Nessun file da unire.');
    }
    final merged = <QtCarburanteTrxRow>[];
    final seen = <String>{};
    final fileNames = <String>[];
    final avvisi = <String>[];
    var dupes = 0;

    for (final part in parts) {
      final name = (part.fileName ?? '').trim();
      if (name.isNotEmpty && !fileNames.contains(name)) {
        fileNames.add(name);
      }
      if (part.avviso != null && part.avviso!.trim().isNotEmpty) {
        avvisi.add(part.avviso!.trim());
      }
      for (final r in part.righe) {
        final key = _dedupeKey(r);
        if (seen.contains(key)) {
          dupes++;
          continue;
        }
        seen.add(key);
        merged.add(r);
      }
    }

    if (merged.isEmpty) {
      throw const FormatException('Nessuna transazione valida nei file selezionati.');
    }

    final buf = StringBuffer();
    if (parts.length > 1) {
      buf.write('Uniti ${parts.length} file (${merged.length} transazioni');
      if (dupes > 0) buf.write(', $dupes duplicate escluse');
      buf.write(').');
    }
    if (avvisi.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(avvisi.join('\n'));
    }

    return QtCarburanteMergedParseResult(
      righe: merged,
      fileNames: fileNames,
      avviso: buf.isEmpty ? null : buf.toString(),
    );
  }

  /// Restituisce anno/mese se tutte le transazioni appartengono allo stesso mese.
  static QtCarburanteMeseRiferimento? detectMeseRiferimento(
    List<QtCarburanteTrxRow> righe,
  ) {
    if (righe.isEmpty) return null;
    int? anno;
    int? mese;
    for (final r in righe) {
      final y = r.dataTransazione.year;
      final m = r.dataTransazione.month;
      if (anno == null) {
        anno = y;
        mese = m;
      } else if (anno != y || mese != m) {
        return null;
      }
    }
    return QtCarburanteMeseRiferimento(anno: anno!, mese: mese!);
  }

  /// Etichette mm/yyyy distinte presenti nelle transazioni.
  static List<String> mesiDistintiLabel(List<QtCarburanteTrxRow> righe) {
    final keys = <String>{};
    for (final r in righe) {
      final d = r.dataTransazione;
      keys.add(
        '${d.month.toString().padLeft(2, '0')}/${d.year}',
      );
    }
    final out = keys.toList(growable: false)..sort();
    return out;
  }

  static String dedupeKey(QtCarburanteTrxRow r) => _dedupeKey(r);

  static String _dedupeKey(QtCarburanteTrxRow r) =>
      '${r.cartaNorm}|${r.isoData}|${_normKey(r.prodotto)}|'
      '${r.volume.toStringAsFixed(3)}|${r.importo.toStringAsFixed(2)}';

  static String _normKey(String s) => s.trim().toUpperCase();

  static int? _findHeaderRow(Sheet sheet) {
    final limit = sheet.maxRows < 30 ? sheet.maxRows : 30;
    for (var r = 0; r < limit; r++) {
      final texts = _rowTexts(sheet, r)
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();
      if (texts.contains(_colCarta) &&
          texts.contains(_colData) &&
          texts.contains(_colVolume) &&
          texts.contains(_colImporto)) {
        return r;
      }
    }
    return null;
  }

  static List<String> _rowTexts(Sheet sheet, int row) {
    final out = <String>[];
    final maxCol = _columnCount(sheet, 40);
    for (var c = 0; c < maxCol; c++) {
      out.add(_cellStr(sheet, row, c));
    }
    return out;
  }

  static int _columnCount(Sheet sheet, int maxScanRows) {
    var max = 0;
    final limit = sheet.maxRows < maxScanRows ? sheet.maxRows : maxScanRows;
    for (var r = 0; r < limit; r++) {
      final row = sheet.row(r);
      if (row.length > max) max = row.length;
    }
    return max > 0 ? max : 24;
  }

  static int? _colIndex(List<String> headers, String needle) {
    final n = needle.trim().toLowerCase();
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].trim().toLowerCase() == n) return i;
    }
    return null;
  }

  static String _cellStr(Sheet sheet, int row, int col) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    return v.toString().trim();
  }

  static double? _cellDouble(Sheet sheet, int row, int col) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static DateTime? _cellDate(Sheet sheet, int row, int col) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is num) {
      final base = DateTime.utc(1899, 12, 30);
      final d = base.add(Duration(milliseconds: (v.toDouble() * 86400000).round()));
      return DateTime(d.year, d.month, d.day);
    }
    final text = _cellStr(sheet, row, col);
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(text);
    if (m != null) {
      final d = int.tryParse(m.group(1) ?? '');
      final mo = int.tryParse(m.group(2) ?? '');
      var y = int.tryParse(m.group(3) ?? '');
      if (d != null && mo != null && y != null) {
        if (y < 100) y += 2000;
        return DateTime(y, mo, d);
      }
    }
    return null;
  }
}