import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../services/rcc_mod04_excel.dart';

/// Ultimo export Mod.RCC (solo desktop con Python).
class RccMod04ExportInfo {
  RccMod04ExportInfo({
    required this.pythonExecutable,
    required this.embeddedMediaCount,
  });

  final String pythonExecutable;
  final int embeddedMediaCount;
}

RccMod04ExportInfo? lastRccMod04ExportInfo;

/// Righe tabella dati (sotto intestazione riga 5, sopra riga «FIRMA D.T.» a riga 36).
const int kRccMod04FirstDataRow = 6;
const int kRccMod04LastDataRow = 35;

/// Riga piè di pagina con etichetta firma DT (non azzerare: sotto ci sono logo/certificazioni).
const int kRccMod04FirmaDtRow = 36;

/// Colonna «NOME E COGNOME» del Mod.RCC = compilatore del rifornimento, non il DT.
String _compilatoreNameForRow(Map<String, dynamic> r, Map<String, String>? names) {
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

String? _formatLitriEuro(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Celle da compilare nel template [Mod.RCC_04.xlsx] (riferimenti A1, es. `D2`, `A6`).
Map<String, String> buildRccMod04Payload({
  required int year,
  required int month,
  required List<Map<String, dynamic>> rows,
  String? automezzoOverride,
  String? targaOverride,
  Map<String, String>? userNamesByUuid,
}) {
  final payload = <String, String>{};

  final monthStart = DateTime(year, month, 1);
  final meseRaw = DateFormat('MMMM yyyy', 'it_IT').format(monthStart);
  final meseLabel = toBeginningOfSentenceCase(meseRaw);

  String pickAutomezzo() {
    final o = (automezzoOverride ?? '').trim();
    if (o.isNotEmpty) return o;
    final set = <String>{};
    for (final r in rows) {
      final t = (r['automezzo_mdo'] ?? '').toString().trim();
      if (t.isNotEmpty) set.add(t);
    }
    if (set.length == 1) return set.first;
    return '';
  }

  String pickTarga() {
    final o = (targaOverride ?? '').trim();
    if (o.isNotEmpty) return o;
    final set = <String>{};
    for (final r in rows) {
      final t = (r['targa_matricola'] ?? '').toString().trim();
      if (t.isNotEmpty) set.add(t);
    }
    if (set.length == 1) return set.first;
    return '';
  }

  final auto = pickAutomezzo();
  final targa = pickTarga();

  payload['D2'] = auto.isEmpty ? 'AUTOMEZZO: ' : 'AUTOMEZZO: $auto';
  payload['D3'] = targa.isEmpty ? 'TARGA: ' : 'TARGA: $targa';
  payload['C4'] = meseLabel;
  payload['H4'] = '$year';

  // Solo righe dati: non toccare riga 36+ (FIRMA D.T., logo, testi legali).
  const dataCols = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  for (var r = kRccMod04FirstDataRow; r <= kRccMod04LastDataRow; r++) {
    for (final col in dataCols) {
      payload['$col$r'] = '';
    }
  }

  final dtFirma = _dtLabelForExport(rows, userNamesByUuid);
  if (dtFirma.isNotEmpty) {
    payload['H$kRccMod04FirmaDtRow'] = dtFirma;
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

  var excelRow = kRccMod04FirstDataRow;
  for (final r in sorted) {
    if (excelRow > kRccMod04LastDataRow) break;
    final rawD = (r['data_rifornimento'] ?? '').toString();
    final d = DateTime.tryParse(rawD);
    payload['A$excelRow'] = d != null ? df.format(d) : rawD;
    payload['B$excelRow'] = (r['n_carta_carburante'] ?? '').toString();
    payload['C$excelRow'] = (r['km_ore'] ?? '').toString();
    final litri = _formatLitriEuro(r['litri']);
    if (litri != null) payload['D$excelRow'] = litri;
    final euro = _formatLitriEuro(r['euro']);
    if (euro != null) payload['E$excelRow'] = euro;
    payload['F$excelRow'] = (r['tipo_carburante'] ?? '').toString();
    payload['G$excelRow'] = (r['cantiere'] ?? '').toString();
    payload['H$excelRow'] = _compilatoreNameForRow(r, userNamesByUuid);
    excelRow++;
  }

  return payload;
}

/// Compila il file Excel originale [Mod.RCC_04.xlsx] (non crea un nuovo workbook).
Future<Uint8List> buildRccMod04ExcelBytes({
  required int year,
  required int month,
  required List<Map<String, dynamic>> rows,
  String? automezzoOverride,
  String? targaOverride,
  Map<String, String>? userNamesByUuid,
}) async {
  final payload = buildRccMod04Payload(
    year: year,
    month: month,
    rows: rows,
    automezzoOverride: automezzoOverride,
    targaOverride: targaOverride,
    userNamesByUuid: userNamesByUuid,
  );
  final bytes = await RccMod04Excel.fill(payload);
  final diag = RccMod04Excel.lastDiagnostics;
  if (diag != null) {
    lastRccMod04ExportInfo = RccMod04ExportInfo(
      pythonExecutable: diag.pythonExecutable,
      embeddedMediaCount: diag.embeddedMediaCount,
    );
  } else {
    lastRccMod04ExportInfo = null;
  }
  return bytes;
}
