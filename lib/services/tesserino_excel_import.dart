import 'package:excel/excel.dart';

import '../utils/tesserino_helpers.dart';

class TesserinoExcelRow {
  final String nome;
  final String cognome;
  final DateTime? dataNascita;
  final DateTime? dataAssunzione;
  final String numeroTesserino;

  const TesserinoExcelRow({
    required this.nome,
    required this.cognome,
    required this.dataNascita,
    required this.dataAssunzione,
    required this.numeroTesserino,
  });
}

String _cellStr(Data? d) {
  if (d == null) return '';
  final v = d.value;
  if (v == null) return '';
  if (v is String) return v.trim();
  if (v is int) return v.toString();
  if (v is double) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }
  if (v is DateTime) return v.toIso8601String();
  return v.toString().trim();
}

DateTime? _cellDate(Data? d) {
  if (d == null) return null;
  final v = d.value;
  if (v is DateTime) {
    return DateTime(v.year, v.month, v.day);
  }
  if (v is int) {
    return excelSerialToDateTime(v);
  }
  if (v is double) {
    return excelSerialToDateTime(v);
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty || s.startsWith('#')) return null;
    final asNum = num.tryParse(s);
    if (asNum != null) return excelSerialToDateTime(asNum);
  }
  return null;
}

/// Legge righe dal foglio `tes.xlsx` (intestazioni: nome, Cognome, Data nascita, …).
List<TesserinoExcelRow> parseTesseriniExcelBytes(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) return const [];
  final sheet = excel.tables[excel.tables.keys.first]!;
  final rows = sheet.rows;
  if (rows.isEmpty) return const [];

  final headerCells = rows.first;
  final header = <String, int>{};
  for (var i = 0; i < headerCells.length; i++) {
    final h = _cellStr(headerCells[i]).toLowerCase();
    if (h.isEmpty) continue;
    if (h == 'nome') header['nome'] = i;
    if (h == 'cognome') header['cognome'] = i;
    if (h.contains('nascita')) header['nascita'] = i;
    if (h.contains('assunzione')) header['assunzione'] = i;
    if (h.contains('tesserino')) header['tesserino'] = i;
  }

  int req(String k) {
    final i = header[k];
    if (i == null) throw FormatException('Colonna mancante nel file: $k');
    return i;
  }

  // Consenti fogli senza colonna Foto
  final iNome = req('nome');
  final iCognome = req('cognome');
  final iNascita = req('nascita');
  final iAssunzione = req('assunzione');
  final iTess = req('tesserino');

  final out = <TesserinoExcelRow>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.isEmpty) continue;
    String gv(int i) => i < row.length ? _cellStr(row[i]) : '';

    final nome = gv(iNome);
    final cognome = gv(iCognome);
    final tess = gv(iTess);
    if (nome.isEmpty && cognome.isEmpty && tess.isEmpty) continue;

    final dn = iNascita < row.length ? _cellDate(row[iNascita]) : null;
    final da = iAssunzione < row.length ? _cellDate(row[iAssunzione]) : null;

    out.add(TesserinoExcelRow(
      nome: nome,
      cognome: cognome,
      dataNascita: dn,
      dataAssunzione: da,
      numeroTesserino: tess,
    ));
  }
  return out;
}
