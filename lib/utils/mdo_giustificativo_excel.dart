import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../services/mdo_giustificativo_excel.dart';
import 'rcc_mdo_destinations.dart';

/// Righe dati (sotto intestazione riga 5, sopra «FIRMA D.T.» a riga 29).
const int kMdoGiuFirstDataRow = 6;
const int kMdoGiuLastDataRow = 28;

/// Riga firma DT (sotto: testi legali e logo — non modificare).
const int kMdoGiuFirmaRow = 29;

/// Riga intestazioni colonne mezzo (al posto di «Mezzo A..»).
const int kMdoGiuMezzoHeaderRow = 5;

/// Colonne mezzi nel template (max 10).
const List<String> kMdoGiuMezzoCols = [
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
];

const List<String> _kMdoGiuDataCols = [
  'B',
  'C',
  'D',
  ...kMdoGiuMezzoCols,
  'O',
  'P',
];

/// Ultimo export giustificativo MDO (desktop + Python).
class MdoGiustificativoExportInfo {
  MdoGiustificativoExportInfo({
    required this.pythonExecutable,
    required this.embeddedMediaCount,
  });

  final String pythonExecutable;
  final int embeddedMediaCount;
}

MdoGiustificativoExportInfo? lastMdoGiustificativoExportInfo;

String? _formatNum(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String _compilatoreName(Map<String, dynamic> r, Map<String, String>? names) {
  final uid = (r['user_uuid'] ?? '').toString().trim();
  if (uid.isNotEmpty && names != null) {
    final n = names[uid];
    if (n != null && n.isNotEmpty) return n;
  }
  return (r['nome_cognome'] ?? '').toString().trim();
}

String _dtLabelForExport(List<Map<String, dynamic>> rows, Map<String, String>? names) {
  final set = <String>{};
  for (final r in rows) {
    final id = (r['dt_user_uuid'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final n = names?[id];
    if (n != null && n.isNotEmpty) set.add(n);
  }
  if (set.length == 1) return set.first;
  return '';
}

String _pickSingle(List<Map<String, dynamic>> rows, String key) {
  final set = <String>{};
  for (final r in rows) {
    final v = (r[key] ?? '').toString().trim();
    if (v.isNotEmpty) set.add(v);
  }
  if (set.length == 1) return set.first;
  return '';
}

String _mezzoColumnKey(MdoRifornimentoDest d, Map<String, Map<String, dynamic>> mdoById) {
  final id = (d.mdoIdUuid ?? '').trim();
  if (id.isNotEmpty) return 'id:$id';
  return 'txt:${mdoMezzoNumeroDisplay(d, mdoById).trim().toLowerCase()}';
}

String _mezzoHeaderLabel(MdoRifornimentoDest d, Map<String, Map<String, dynamic>> mdoById) =>
    mdoMezzoNumeroDisplay(d, mdoById);

/// Mezzi distinti nel periodo → colonne E..N (max 10), ordine alfabetico per etichetta.
Map<String, String> _buildMezzoColumnMap(
  List<Map<String, dynamic>> rows,
  Map<String, Map<String, dynamic>> mdoById,
) {
  final labels = <String, String>{};
  for (final r in rows) {
    for (final d in parseMdoDestinationsFromRow(r)) {
      final key = _mezzoColumnKey(d, mdoById);
      if (key == 'txt:' || key == 'txt:—') continue;
      labels.putIfAbsent(key, () => _mezzoHeaderLabel(d, mdoById));
    }
  }
  final keys = labels.keys.toList()
    ..sort((a, b) => labels[a]!.toLowerCase().compareTo(labels[b]!.toLowerCase()));
  final colByKey = <String, String>{};
  for (var i = 0; i < keys.length && i < kMdoGiuMezzoCols.length; i++) {
    colByKey[keys[i]] = kMdoGiuMezzoCols[i];
  }
  return colByKey;
}

void _putLitriInCell(
  Map<String, String> payload,
  String cellRef,
  double litri,
) {
  final formatted = _formatNum(litri);
  if (formatted == null) return;
  final prev = payload[cellRef];
  if (prev != null && prev.isNotEmpty) {
    final a = double.tryParse(prev.replaceAll(',', '.')) ?? 0;
    final merged = a + litri;
    final m = _formatNum(merged);
    if (m != null) payload[cellRef] = m;
  } else {
    payload[cellRef] = formatted;
  }
}

/// Celle da compilare in [Giustificativo_Carburante_MDO.xlsx] (foglio Mod.RCC).
Map<String, String> buildMdoGiustificativoPayload({
  required int year,
  required int month,
  required List<Map<String, dynamic>> rows,
  Map<String, String>? userNamesByUuid,
  Map<String, Map<String, dynamic>> mdoById = const {},
}) {
  final payload = <String, String>{};
  final monthStart = DateTime(year, month, 1);
  final meseRaw = DateFormat('MMMM', 'it_IT').format(monthStart);
  final meseLabel = toBeginningOfSentenceCase(meseRaw);

  final multicard = _pickSingle(rows, 'n_carta_carburante');
  payload['C4'] = meseLabel;
  payload['F4'] = '$year';
  payload['H4'] = multicard.isEmpty
      ? 'N° Multicard:    ...................'
      : 'N° Multicard: $multicard';

  final dtHeader = _dtLabelForExport(rows, userNamesByUuid);
  if (dtHeader.isNotEmpty) {
    payload['L4'] = 'DT: $dtHeader';
  }

  for (var r = kMdoGiuFirstDataRow; r <= kMdoGiuLastDataRow; r++) {
    for (final col in _kMdoGiuDataCols) {
      payload['$col$r'] = '';
    }
  }
  for (final col in kMdoGiuMezzoCols) {
    payload['$col$kMdoGiuMezzoHeaderRow'] = '';
  }

  final df = DateFormat('dd/MM/yyyy');
  var sorted = List<Map<String, dynamic>>.from(rows);
  sorted.sort((a, b) {
    final da = DateTime.tryParse((a['data_rifornimento'] ?? '').toString());
    final db = DateTime.tryParse((b['data_rifornimento'] ?? '').toString());
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    final byDate = da.compareTo(db);
    if (byDate != 0) return byDate;
    return (a['id_uuid'] ?? '').toString().compareTo((b['id_uuid'] ?? '').toString());
  });

  final colByMezzoKey = _buildMezzoColumnMap(sorted, mdoById);
  final labelByKey = <String, String>{};
  for (final r in sorted) {
    for (final d in parseMdoDestinationsFromRow(r)) {
      final key = _mezzoColumnKey(d, mdoById);
      labelByKey.putIfAbsent(key, () => _mezzoHeaderLabel(d, mdoById));
    }
  }
  for (final entry in colByMezzoKey.entries) {
    final label = labelByKey[entry.key];
    if (label != null && label.isNotEmpty) {
      payload['${entry.value}$kMdoGiuMezzoHeaderRow'] = label;
    }
  }

  var excelRow = kMdoGiuFirstDataRow;
  for (final r in sorted) {
    if (excelRow > kMdoGiuLastDataRow) break;
    final rawD = (r['data_rifornimento'] ?? '').toString();
    final d = DateTime.tryParse(rawD);
    payload['B$excelRow'] = d != null ? df.format(d) : rawD;
    final litri = _formatNum(r['litri']);
    if (litri != null) payload['C$excelRow'] = litri;
    final euro = _formatNum(r['euro']);
    if (euro != null) payload['D$excelRow'] = euro;
    payload['O$excelRow'] = (r['cantiere'] ?? '').toString();
    payload['P$excelRow'] = _compilatoreName(r, userNamesByUuid);

    for (final dest in parseMdoDestinationsFromRow(r)) {
      final col = colByMezzoKey[_mezzoColumnKey(dest, mdoById)];
      if (col == null || dest.litri <= 0) continue;
      _putLitriInCell(payload, '$col$excelRow', dest.litri);
    }
    excelRow++;
  }

  if (dtHeader.isNotEmpty) {
    payload['F$kMdoGiuFirmaRow'] = dtHeader;
  }
  if (sorted.isNotEmpty) {
    final lastD = DateTime.tryParse(
      (sorted.last['data_rifornimento'] ?? '').toString(),
    );
    if (lastD != null) {
      payload['C$kMdoGiuFirmaRow'] = df.format(lastD);
    }
  }

  return payload;
}

Future<Uint8List> buildMdoGiustificativoExcelBytes({
  required int year,
  required int month,
  required List<Map<String, dynamic>> rows,
  Map<String, String>? userNamesByUuid,
  Map<String, Map<String, dynamic>> mdoById = const {},
}) async {
  final payload = buildMdoGiustificativoPayload(
    year: year,
    month: month,
    rows: rows,
    userNamesByUuid: userNamesByUuid,
    mdoById: mdoById,
  );
  final bytes = await MdoGiustificativoExcel.fill(payload);
  final diag = MdoGiustificativoExcel.lastDiagnostics;
  if (diag != null) {
    lastMdoGiustificativoExportInfo = MdoGiustificativoExportInfo(
      pythonExecutable: diag.pythonExecutable,
      embeddedMediaCount: diag.embeddedMediaCount,
    );
  } else {
    lastMdoGiustificativoExportInfo = null;
  }
  return bytes;
}
