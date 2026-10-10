import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

class PosMaestranzeImportRow {
  final String cognome;
  final String nome;
  final DateTime? idoneitaSanitaria;
  final String? mansione;

  const PosMaestranzeImportRow({
    required this.cognome,
    required this.nome,
    this.idoneitaSanitaria,
    this.mansione,
  });
}

class PosMaestranzeImportParseResult {
  final DateTime? dataUltimoAggiornamento;
  final List<PosMaestranzeImportRow> righe;
  final String? avviso;

  const PosMaestranzeImportParseResult({
    required this.righe,
    this.dataUltimoAggiornamento,
    this.avviso,
  });
}

abstract final class PosMaestranzeImportParser {
  PosMaestranzeImportParser._();

  static final _dateRe = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})');
  static final _dataListaRe = RegExp(
    r'data\s*:\s*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})',
    caseSensitive: false,
  );

  static Future<PosMaestranzeImportParseResult> parseFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.docx')) {
      return _parseDocx(bytes);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return _parseExcel(bytes);
    }
    throw FormatException('Formato non supportato. Usa .xlsx o .docx');
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

  /// Solo la riga «Data: dd/mm/yyyy» dell'intestazione (logo), non date idoneità in tabella.
  static DateTime? _extractDataListaFromText(String text) {
    final lista = _dataListaRe.firstMatch(text);
    if (lista != null) return _parseDateMatch(lista);
    return null;
  }

  static String _paragraphText(XmlElement paragraph, String w) {
    final buf = StringBuffer();
    for (final t in paragraph.findAllElements('t', namespace: w)) {
      buf.write(t.innerText);
    }
    return buf.toString().trim();
  }

  /// Data lista: paragrafi sopra la prima tabella (sotto logo CRONOS).
  static DateTime? _extractDataListaFromDocx(XmlDocument doc) {
    const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final bodies = doc.findAllElements('body', namespace: w);
    if (bodies.isEmpty) return null;

    for (final body in bodies) {
      for (final element in body.childElements) {
        final local = element.name.local;
        if (local == 'tbl') break;
        if (local == 'p') {
          final d = _extractDataListaFromText(_paragraphText(element, w));
          if (d != null) return d;
        }
      }
    }

    // Fallback: tutti i paragrafi prima della prima tabella nel documento.
    XmlElement? firstTable;
    for (final tbl in doc.findAllElements('tbl', namespace: w)) {
      firstTable = tbl;
      break;
    }
    if (firstTable == null) return null;

    for (final p in doc.findAllElements('p', namespace: w)) {
      if (_elementIsBefore(p, firstTable)) {
        final d = _extractDataListaFromText(_paragraphText(p, w));
        if (d != null) return d;
      }
    }
    return null;
  }

  static bool _elementIsBefore(XmlElement a, XmlElement b) {
    if (identical(a, b)) return false;
    for (final n in b.precedingElements) {
      if (identical(n, a)) return true;
    }
    return false;
  }

  static DateTime? _extractDateFromCell(String cell) {
    final m = _dateRe.firstMatch(cell);
    if (m == null) return null;
    return _parseDateMatch(m);
  }

  static String? _extractMansioneFromCell(String cell) {
    final m = _dateRe.firstMatch(cell);
    if (m == null) return cell.trim().isEmpty ? null : cell.trim();
    final after = cell.substring(m.end).trim();
    return after.isEmpty ? null : after;
  }

  static bool _isHeaderRow(List<String> cells) {
    final joined = cells.join(' ').toUpperCase();
    return joined.contains('COGNOME') && joined.contains('NOME');
  }

  static bool _looksLikeDataRow(List<String> cells) {
    if (cells.length < 2) return false;
    final c0 = cells[0].trim();
    final c1 = cells[1].trim();
    if (c0.isEmpty || c1.isEmpty) return false;
    if (c0.toUpperCase().contains('COGNOME')) return false;
    if (RegExp(r'^\d+$').hasMatch(c0) && RegExp(r'^\d+$').hasMatch(c1)) return false;
    return true;
  }

  static PosMaestranzeImportParseResult _parseDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) {
      throw const FormatException('DOCX non valido (manca document.xml)');
    }
    final xmlStr = String.fromCharCodes(entry.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);
    final dataLista = _extractDataListaFromDocx(doc);
    const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final tableRows = <List<String>>[];

    for (final tr in doc.findAllElements('tr', namespace: w)) {
      final cells = <String>[];
      for (final tc in tr.findElements('tc', namespace: w)) {
        final buf = StringBuffer();
        for (final t in tc.findAllElements('t', namespace: w)) {
          buf.write(t.innerText);
        }
        cells.add(buf.toString().trim());
      }
      if (cells.any((c) => c.trim().isNotEmpty)) {
        tableRows.add(cells);
      }
    }

    final righe = <PosMaestranzeImportRow>[];
    for (final cells in tableRows) {
      if (_isHeaderRow(cells)) continue;
      if (!_looksLikeDataRow(cells)) continue;
      final cognome = cells[0].trim();
      final nome = cells[1].trim();
      final cell2 = cells.length > 2 ? cells[2] : '';
      righe.add(
        PosMaestranzeImportRow(
          cognome: cognome,
          nome: nome,
          idoneitaSanitaria: _extractDateFromCell(cell2),
          mansione: cells.length > 3
              ? cells[3].trim().isEmpty
                  ? _extractMansioneFromCell(cell2)
                  : cells[3].trim()
              : _extractMansioneFromCell(cell2),
        ),
      );
    }

    return PosMaestranzeImportParseResult(
      dataUltimoAggiornamento: dataLista,
      righe: righe,
      avviso: righe.isEmpty ? 'Nessuna riga dipendente trovata nel documento.' : null,
    );
  }

  static PosMaestranzeImportParseResult _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('Foglio Excel vuoto');
    }
    final sheet = excel.tables.values.first;
    if (sheet.maxRows == 0) {
      throw const FormatException('Foglio Excel senza dati');
    }
    final colCount = _columnCount(sheet, 40);

    DateTime? dataLista;
    int? cognomeCol;
    int? nomeCol;
    int? idoneitaCol;
    int? mansioneCol;
    var dataStartRow = 0;

    for (var r = 0; r < sheet.maxRows && r < 30; r++) {
      final rowTexts = <String>[];
      for (var c = 0; c < colCount; c++) {
        rowTexts.add(_cellText(sheet, r, c));
      }
      final joined = rowTexts.join(' ');
      final explicitLista = _extractDataListaFromText(joined);
      if (explicitLista != null) dataLista = explicitLista;

      if (cognomeCol == null) {
        for (var c = 0; c < rowTexts.length; c++) {
          final t = rowTexts[c].toUpperCase();
          if (t.contains('COGNOME')) cognomeCol = c;
          if (t == 'NOME' || t.startsWith('NOME ')) nomeCol = c;
          if (t.contains('IDONEITA')) idoneitaCol = c;
          if (t.contains('MANSIONE')) mansioneCol = c;
        }
        if (cognomeCol != null && nomeCol != null) {
          dataStartRow = r + 1;
          break;
        }
      }
    }

    cognomeCol ??= 0;
    nomeCol ??= 1;
    idoneitaCol ??= 2;
    mansioneCol ??= 3;

    final righe = <PosMaestranzeImportRow>[];
    for (var r = dataStartRow; r < sheet.maxRows; r++) {
      final cognome = _cellText(sheet, r, cognomeCol);
      final nome = _cellText(sheet, r, nomeCol);
      if (cognome.isEmpty && nome.isEmpty) continue;
      if (cognome.toUpperCase().contains('COGNOME')) continue;
      final idCell = _cellText(sheet, r, idoneitaCol);
      final manCell = _cellText(sheet, r, mansioneCol);
      righe.add(
        PosMaestranzeImportRow(
          cognome: cognome,
          nome: nome,
          idoneitaSanitaria: _extractDateFromCell(idCell),
          mansione: manCell.isEmpty ? _extractMansioneFromCell(idCell) : manCell,
        ),
      );
    }

    return PosMaestranzeImportParseResult(
      dataUltimoAggiornamento: dataLista,
      righe: righe,
      avviso: righe.isEmpty ? 'Nessuna riga dipendente trovata nel foglio.' : null,
    );
  }

  static int _columnCount(Sheet sheet, int maxScanRows) {
    var max = 0;
    final limit = sheet.maxRows < maxScanRows ? sheet.maxRows : maxScanRows;
    for (var r = 0; r < limit; r++) {
      final row = sheet.row(r);
      if (row.length > max) max = row.length;
    }
    return max > 0 ? max : 16;
  }

  static String _cellText(Sheet sheet, int row, int col) {
    final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value;
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
    }
    return v.toString().trim();
  }

  /// Modello Excel compatibile con l'import POS (stessa struttura dell'allegato maestranze).
  static Uint8List buildTemplateExcelBytes() {
    final now = DateTime.now();
    final dataStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final excel = Excel.createExcel();
    final sheet = excel.tables.values.first;
    sheet.appendRow(<Object?>[null]);
    sheet.appendRow(<Object?>['Data: $dataStr']);
    sheet.appendRow(<Object?>['POS ALLEGATO 01']);
    sheet.appendRow(<Object?>[
      'Oggetto: descrizione commessa / cantiere (facoltativo)',
    ]);
    sheet.appendRow(<Object?>['ELENCO MAESTRANZE']);
    sheet.appendRow(<Object?>[null]);
    sheet.appendRow(<Object?>[
      'COGNOME',
      'NOME',
      "IDONEITA' SANITARIA (SCADENZA)",
      'MANSIONE',
      'NOMINE E PROCURE D.T.',
      'NOMINE ADDETTO EMERGENZE',
      'NOMINE ADDETTO PRIMO SOCC.',
      'NOMINE PES/PAV/PEI',
      'INCARICO PREPOSTO AI LAVORI',
      'CONSEGNA DPI e DPI 3° CAT.',
      'PERSONALE A DISTACCO',
    ]);
    sheet.appendRow(<Object?>[
      'Rossi',
      'Mario',
      '31/12/2027',
      'Autista',
      null,
      null,
      'X',
      'X',
      null,
      null,
      'X',
      null,
    ]);
    sheet.appendRow(<Object?>[
      'Verdi',
      'Luigi',
      '15/06/2027',
      'Installatore impianti',
      null,
      'X',
      'X',
      'X',
      'X',
      'X',
      null,
    ]);
    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Impossibile generare il modello Excel.');
    }
    return Uint8List.fromList(encoded);
  }
}
