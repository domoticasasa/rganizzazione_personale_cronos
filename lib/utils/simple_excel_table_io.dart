import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Genera un foglio Excel con intestazioni e righe di esempio.
abstract final class SimpleExcelTableIo {
  SimpleExcelTableIo._();

  static Uint8List buildTemplate({
    required String sheetName,
    required List<String> headers,
    List<List<Object?>> exampleRows = const [],
    String? titleRow,
  }) {
    final excel = Excel.createExcel();
    // excel.rename(sheetName) fallisce in excel 2.1.0; il tab resta "Sheet1".
    assert(sheetName.trim().isNotEmpty);
    final sheet = excel[excel.tables.keys.first];
    if (titleRow != null && titleRow.trim().isNotEmpty) {
      sheet.appendRow(<Object?>[titleRow]);
      sheet.appendRow(<Object?>[null]);
    }
    sheet.appendRow(List<Object?>.from(headers));
    for (final row in exampleRows) {
      sheet.appendRow(List<Object?>.from(row));
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Impossibile generare il modello Excel.');
    }
    return Uint8List.fromList(encoded);
  }

  /// Legge la prima riga non vuota come intestazione; le successive come dati.
  static List<Map<String, String>> parseTable(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return const [];
    for (final sheet in excel.tables.values) {
      final parsed = _parseSheetRows(sheet.rows);
      if (parsed.isNotEmpty) return parsed;
    }
    return const [];
  }

  static List<Map<String, String>> _parseSheetRows(List<List<Data?>> rows) {
    if (rows.isEmpty) return const [];

    var headerIndex = -1;
    List<String> headers = const [];
    for (var i = 0; i < rows.length; i++) {
      final cells = rows[i];
      final texts = <String>[];
      for (final c in cells) {
        texts.add(_cellStr(c));
      }
      if (texts.any((t) => t.trim().isNotEmpty)) {
        headers = texts.map((t) => t.trim()).toList();
        headerIndex = i;
        break;
      }
    }
    if (headerIndex < 0 || headers.isEmpty) return const [];

    final out = <Map<String, String>>[];
    for (var r = headerIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      final map = <String, String>{};
      var hasValue = false;
      for (var c = 0; c < headers.length; c++) {
        final key = headers[c].trim();
        if (key.isEmpty) continue;
        final val = c < row.length ? _cellStr(row[c]) : '';
        if (val.trim().isNotEmpty) hasValue = true;
        map[key] = val.trim();
      }
      if (hasValue) out.add(map);
    }
    return out;
  }

  static String _cellStr(Data? d) {
    if (d == null) return '';
    final v = d.value;
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is int) return v.toString();
    if (v is double) {
      if (v == v.roundToDouble()) return v.round().toString();
      return v.toString();
    }
    if (v is DateTime) {
      return '${v.day.toString().padLeft(2, '0')}/'
          '${v.month.toString().padLeft(2, '0')}/${v.year}';
    }
    return v.toString().trim();
  }

  static String? rowValue(Map<String, String> row, List<String> keys) {
    final lower = {for (final e in row.entries) e.key.toLowerCase(): e.value};
    for (final k in keys) {
      final v = lower[k.toLowerCase()];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static bool parseBool(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    return s == 'SI' || s == 'S' || s == 'TRUE' || s == '1' || s == 'X';
  }
}
