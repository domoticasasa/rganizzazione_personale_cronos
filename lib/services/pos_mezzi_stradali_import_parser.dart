import 'dart:typed_data';

import 'package:excel/excel.dart';

class PosMezziStradaliImportRow {
  final String codifica;
  final String targa;
  final String modello;
  final String definizioneClasse;
  final String? proprietaNoleggio;

  const PosMezziStradaliImportRow({
    required this.codifica,
    required this.targa,
    required this.modello,
    required this.definizioneClasse,
    this.proprietaNoleggio,
  });
}

class PosMezziStradaliImportParseResult {
  final DateTime? dataUltimoAggiornamento;
  final List<PosMezziStradaliImportRow> righe;
  final String? avviso;

  const PosMezziStradaliImportParseResult({
    required this.righe,
    this.dataUltimoAggiornamento,
    this.avviso,
  });
}

abstract final class PosMezziStradaliImportParser {
  PosMezziStradaliImportParser._();

  static final _dataListaRe = RegExp(
    r'data\s*:\s*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})',
    caseSensitive: false,
  );

  static Future<PosMezziStradaliImportParseResult> parseFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.xlsx') && !lower.endsWith('.xls')) {
      throw FormatException('Formato non supportato. Usa .xlsx');
    }
    return _parseExcel(bytes);
  }

  static DateTime? _parseDateMatch(RegExpMatch m) {
    final d = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    var y = int.tryParse(m.group(3) ?? '');
    if (d == null || mo == null || y == null) return null;
    if (y < 100) y += 2000;
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }

  static DateTime? _extractDataListaFromText(String text) {
    final m = _dataListaRe.firstMatch(text);
    if (m == null) return null;
    return _parseDateMatch(m);
  }

  static PosMezziStradaliImportParseResult _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('Foglio Excel vuoto');
    }
    final sheet = excel.tables.values.first;
    if (sheet.maxRows == 0) {
      throw const FormatException('Foglio Excel senza dati');
    }
    final colCount = _columnCount(sheet, 30);

    DateTime? dataLista;
    int? codificaCol;
    int? targaCol;
    int? modelloCol;
    int? tipologiaCol;
    int? proprietaCol;
    var dataStartRow = 0;

    for (var r = 0; r < sheet.maxRows && r < 30; r++) {
      final rowTexts = <String>[];
      for (var c = 0; c < colCount; c++) {
        rowTexts.add(_cellText(sheet, r, c));
      }
      final joined = rowTexts.join(' ');
      final explicitLista = _extractDataListaFromText(joined);
      if (explicitLista != null) dataLista = explicitLista;

      if (codificaCol == null) {
        for (var c = 0; c < rowTexts.length; c++) {
          final t = rowTexts[c].toUpperCase();
          if (t.contains('CODIFICA')) codificaCol = c;
          if (t == 'TARGA' || t.startsWith('TARGA')) targaCol = c;
          if (t.contains('MODELLO')) modelloCol = c;
          if (t.contains('DEFINIZIONE') || t.contains('CLASSE')) tipologiaCol = c;
          if (t.contains('PROPRIET') || t.contains('NOLEGGIO')) proprietaCol = c;
        }
        if (codificaCol != null && targaCol != null) {
          dataStartRow = r + 1;
          break;
        }
      }
    }

    codificaCol ??= 0;
    targaCol ??= 1;
    modelloCol ??= 2;
    tipologiaCol ??= 3;
    proprietaCol ??= 4;

    final righe = <PosMezziStradaliImportRow>[];
    for (var r = dataStartRow; r < sheet.maxRows; r++) {
      final codifica = _cellText(sheet, r, codificaCol);
      final targa = _cellText(sheet, r, targaCol);
      final modello = _cellText(sheet, r, modelloCol);
      final tipologia = _cellText(sheet, r, tipologiaCol);
      final proprieta = _cellText(sheet, r, proprietaCol);
      if (codifica.isEmpty && targa.isEmpty && modello.isEmpty) continue;
      if (codifica.toUpperCase().contains('CODIFICA')) continue;
      righe.add(
        PosMezziStradaliImportRow(
          codifica: codifica,
          targa: targa,
          modello: modello,
          definizioneClasse: tipologia,
          proprietaNoleggio: proprieta.isEmpty ? null : proprieta,
        ),
      );
    }

    return PosMezziStradaliImportParseResult(
      dataUltimoAggiornamento: dataLista,
      righe: righe,
      avviso: righe.isEmpty ? 'Nessun mezzo trovato nel foglio.' : null,
    );
  }

  static Uint8List buildTemplateExcelBytes() {
    final now = DateTime.now();
    final dataStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final excel = Excel.createExcel();
    final sheet = excel.tables.values.first;
    sheet.appendRow(<Object?>[null]);
    sheet.appendRow(<Object?>['Data: $dataStr']);
    sheet.appendRow(<Object?>['POS ALLEGATO 02.1']);
    sheet.appendRow(<Object?>[
      'Oggetto: descrizione commessa / cantiere (facoltativo)',
    ]);
    sheet.appendRow(<Object?>['MEZZI STRADALI']);
    sheet.appendRow(<Object?>[null]);
    sheet.appendRow(<Object?>[
      'Codifica',
      'Targa',
      'Modello',
      'Definizione Classe Mezzo',
      "PROPRIETA'/NOLEGGIO.",
    ]);
    sheet.appendRow(<Object?>[
      'N07',
      'FZ811NS',
      'FIAT TIPO',
      'AUTOVETTURA',
      'NOLEGGIO',
    ]);
    sheet.appendRow(<Object?>[
      'N33',
      'GE516MF',
      'FORD TRANSIT',
      'AUTOCARRO',
      'NOLEGGIO',
    ]);
    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Impossibile generare il modello Excel.');
    }
    return Uint8List.fromList(encoded);
  }

  static int _columnCount(Sheet sheet, int maxScanRows) {
    var max = 0;
    final limit = sheet.maxRows < maxScanRows ? sheet.maxRows : maxScanRows;
    for (var r = 0; r < limit; r++) {
      final row = sheet.row(r);
      if (row.length > max) max = row.length;
    }
    return max > 0 ? max : 8;
  }

  static String _cellText(Sheet sheet, int row, int col) {
    final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value;
    if (v == null) return '';
    return v.toString().trim();
  }
}
