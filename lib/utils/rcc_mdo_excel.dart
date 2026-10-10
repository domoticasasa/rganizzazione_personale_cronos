import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';

import 'excel_web_safe.dart';
import 'rcc_mdo_destinations.dart';

double excelSerialDateUtc(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final epoch = DateTime.utc(1899, 12, 30);
  return d.difference(epoch).inMilliseconds / Duration.millisecondsPerDay;
}

Uint8List buildRccMdoExcelBytes({
  Uint8List? templateBytes,
  required int year,
  required int month,
  required List<Map<String, dynamic>> rows,
  String? multicardOverride,
  String? dtLabelOverride,
}) {
  final excel = templateBytes != null && templateBytes.isNotEmpty
      ? Excel.decodeBytes(templateBytes)
      : Excel.createExcel();
  final Sheet sheet;
  if (templateBytes != null && templateBytes.isNotEmpty) {
    final name = excel.tables.containsKey('Mod.RCC')
        ? 'Mod.RCC'
        : (excel.tables.keys.isNotEmpty ? excel.tables.keys.first : 'Mod.RCC');
    sheet = excel[name];
  } else {
    sheet = excelUseDefaultSheet(excel);
  }

  void cell(int row1, int col1, dynamic value) {
    sheet
        .cell(CellIndex.indexByColumnRow(
          rowIndex: row1 - 1,
          columnIndex: col1 - 1,
        ))
        .value = value;
  }

  final monthStart = DateTime(year, month, 1);
  final meseLabel = toBeginningOfSentenceCase(
        DateFormat('MMMM', 'it_IT').format(monthStart),
      );

  String pickSingle(String key) {
    final set = <String>{};
    for (final r in rows) {
      final v = (r[key] ?? '').toString().trim();
      if (v.isNotEmpty) set.add(v);
    }
    if (set.length == 1) return set.first;
    return '';
  }

  final multicard = (multicardOverride ?? '').trim().isNotEmpty
      ? (multicardOverride ?? '').trim()
      : pickSingle('n_carta_carburante');
  final dtLabel = (dtLabelOverride ?? '').trim();

  cell(4, 3, meseLabel);
  cell(4, 6, year);
  cell(4, 8, multicard.isEmpty ? 'N° Multicard: ...................' : 'N° Multicard: $multicard');
  if (dtLabel.isNotEmpty) cell(4, 13, dtLabel);

  var sorted = List<Map<String, dynamic>>.from(rows);
  sorted.sort((a, b) {
    final da = DateTime.tryParse((a['data_rifornimento'] ?? '').toString());
    final db = DateTime.tryParse((b['data_rifornimento'] ?? '').toString());
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });

  // Template body rows: 6..28 (eventuali mezzi extra su righe successive)
  var rr = 6;
  for (final r in sorted) {
    if (rr > 28) break;
    final destinations = parseMdoDestinationsFromRow(r);
    final chunks = destinations.isEmpty
        ? <List<MdoRifornimentoDest>>[
            [
              MdoRifornimentoDest(
                mezzo: (r['automezzo_mdo'] ?? '').toString().trim(),
                litri: _toDouble(r['litri']) ?? 0,
              ),
            ],
          ]
        : _chunkDestinations(destinations, 10);
    for (var ci = 0; ci < chunks.length; ci++) {
      if (rr > 28) break;
      final chunk = chunks[ci];
      final d = DateTime.tryParse((r['data_rifornimento'] ?? '').toString());
      if (d != null && ci == 0) {
        cell(rr, 2, excelSerialDateUtc(d));
      }
      final chunkLitri = chunk.fold<double>(0, (s, x) => s + x.litri);
      if (ci == 0) {
        cell(rr, 3, _toDouble(r['litri']) ?? chunkLitri);
        cell(rr, 4, _toDouble(r['euro']) ?? '');
      }
      final mezziTxt = chunk
          .map((x) => '${x.mezzo}${x.litri > 0 ? ' (${_fmtLitri(x.litri)} L)' : ''}')
          .join('; ');
      cell(rr, 5, mezziTxt.isEmpty ? (r['automezzo_mdo'] ?? '').toString() : mezziTxt);
      cell(rr, 6, (r['targa_matricola'] ?? '').toString());
      if (ci == 0) {
        cell(rr, 15, (r['cantiere'] ?? '').toString());
        cell(rr, 16, (r['nome_cognome'] ?? '').toString());
        cell(rr, 17, (r['firma_compilatore'] ?? '').toString());
      }
      rr++;
    }
  }

  // Footer
  final firmaDate = sorted.isNotEmpty
      ? DateTime.tryParse((sorted.last['data_rifornimento'] ?? '').toString())
      : null;
  if (firmaDate != null) {
    cell(29, 2, excelSerialDateUtc(firmaDate));
  }
  if (dtLabel.isNotEmpty) {
    cell(29, 6, dtLabel);
  }

  final encoded = excel.encode();
  return Uint8List.fromList(encoded!);
}

List<List<MdoRifornimentoDest>> _chunkDestinations(
  List<MdoRifornimentoDest> items,
  int size,
) {
  if (items.isEmpty) return const [];
  final out = <List<MdoRifornimentoDest>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

String _fmtLitri(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(s);
}