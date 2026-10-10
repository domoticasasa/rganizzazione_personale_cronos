import 'dart:typed_data';

import 'package:excel/excel.dart';

class PosMdoFerroviariImportRow {
  final String codifica;
  final String targaMatricola;
  final String descrizione;
  final String? proprietaNoleggio;

  const PosMdoFerroviariImportRow({
    required this.codifica,
    required this.targaMatricola,
    required this.descrizione,
    this.proprietaNoleggio,
  });
}

class PosMdoFerroviariImportParseResult {
  final DateTime? dataUltimoAggiornamento;
  final List<PosMdoFerroviariImportRow> righe;
  final String? avviso;

  const PosMdoFerroviariImportParseResult({
    required this.righe,
    this.dataUltimoAggiornamento,
    this.avviso,
  });
}

abstract final class PosMdoFerroviariImportParser {
  PosMdoFerroviariImportParser._();

  static final _dataListaRe = RegExp(
    r'data\s*:\s*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})',
    caseSensitive: false,
  );

  static Future<PosMdoFerroviariImportParseResult> parseFile({
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

  static PosMdoFerroviariImportParseResult _parseExcel(Uint8List bytes) {
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
    int? descrizioneCol;
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
          if (t.contains('TARGA') || t.contains('MATRICOLA') || t.contains('IDENTIFICAZ')) {
            targaCol = c;
          }
          if (t.contains('DESCRIZIONE')) descrizioneCol = c;
          if (t.contains('PROPRIET') || t.contains('NOLEGGIO')) proprietaCol = c;
        }
        if (codificaCol != null && (targaCol != null || descrizioneCol != null)) {
          dataStartRow = r + 1;
          break;
        }
      }
    }

    codificaCol ??= 0;
    targaCol ??= 1;
    descrizioneCol ??= 2;
    proprietaCol ??= 3;

    final righe = <PosMdoFerroviariImportRow>[];
    for (var r = dataStartRow; r < sheet.maxRows; r++) {
      final codifica = _cellText(sheet, r, codificaCol);
      final targa = _cellText(sheet, r, targaCol);
      final descrizione = _cellText(sheet, r, descrizioneCol);
      final proprieta = _cellText(sheet, r, proprietaCol);
      if (codifica.isEmpty && targa.isEmpty && descrizione.isEmpty) continue;
      if (codifica.toUpperCase().contains('CODIFICA')) continue;
      righe.add(
        PosMdoFerroviariImportRow(
          codifica: codifica,
          targaMatricola: targa,
          descrizione: descrizione,
          proprietaNoleggio: proprieta.isEmpty ? null : proprieta,
        ),
      );
    }

    return PosMdoFerroviariImportParseResult(
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
    sheet.appendRow(<Object?>['POS ALLEGATO 02.3']);
    sheet.appendRow(<Object?>[
      'Oggetto: descrizione commessa / cantiere (facoltativo)',
    ]);
    sheet.appendRow(<Object?>["MEZZI D'OPERA FERROVIARI"]);
    sheet.appendRow(<Object?>[null]);
    sheet.appendRow(<Object?>[
      'Codifica',
      'Targa/ Matricola/ Codice identificazione',
      'Descrizione',
      'PROPRIETA/NOLEGGIO.',
    ]);
    sheet.appendRow(<Object?>[
      'A21',
      'IT-RFI 161636-3',
      'AUTOSCALA',
      'PROPRIETA',
    ]);
    sheet.appendRow(<Object?>[
      'A23',
      'IT-RFI 261881-3',
      'SCALA MOTORIZZATA',
      'PROPRIETA',
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
