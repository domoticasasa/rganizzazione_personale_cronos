import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';

import '../services/buoni_pasto_service.dart';
import 'excel_export_helper.dart';

/// Export CSV registrazioni buoni pasto.
abstract final class BuoniPastoExport {
  static const List<String> _headers = [
    'Data',
    'Ora',
    'Dipendente',
    'Ristorante',
    'Tipo pasto',
  ];

  static String _cell(String raw) {
    final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
    if (s.contains(';') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static List<String> _rowValues(Map<String, dynamic> r) {
    final registratoAt = DateTime.tryParse(
      (r['registrato_at'] ?? '').toString(),
    );
    final dataPasto = (r['data_pasto'] ?? '').toString();
    final data = dataPasto.length >= 10
        ? '${dataPasto.substring(8, 10)}/${dataPasto.substring(5, 7)}/${dataPasto.substring(0, 4)}'
        : dataPasto;
    final ora = registratoAt != null
        ? '${registratoAt.hour.toString().padLeft(2, '0')}:${registratoAt.minute.toString().padLeft(2, '0')}'
        : '';
    final structure = r['structures'];
    final nomeRistorante = structure is Map
        ? (structure['name'] ?? '').toString()
        : (r['structure_name'] ?? '').toString();
    return [
      data,
      ora,
      (r['dipendente_nome'] ?? '').toString(),
      nomeRistorante,
      (r['tipo_pasto'] ?? '').toString(),
    ];
  }

  static String buildCsv(List<Map<String, dynamic>> rows) {
    final buf = StringBuffer();
    buf.writeln(_headers.map(_cell).join(';'));
    for (final r in rows) {
      buf.writeln(_rowValues(r).map(_cell).join(';'));
    }
    return buf.toString();
  }

  static Uint8List csvBytes(List<Map<String, dynamic>> rows) {
    const bom = [0xEF, 0xBB, 0xBF];
    return Uint8List.fromList([...bom, ...utf8.encode(buildCsv(rows))]);
  }

  static Uint8List xlsxBytes(List<Map<String, dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];
    sheet.appendRow(_headers);
    for (final r in rows) {
      sheet.appendRow(_rowValues(r));
    }
    return Uint8List.fromList(excel.encode()!);
  }

  static List<String> _presenzeHeaders(BuoniPastoPresenzeReport report) {
    final headers = <String>['Dipendente', 'Matricola', 'Totale pasti'];
    for (final g in report.giorni) {
      headers.add(
        '${g.day.toString().padLeft(2, '0')}/${g.month.toString().padLeft(2, '0')}',
      );
    }
    return headers;
  }

  static List<List<String>> _presenzeRows(BuoniPastoPresenzeReport report) {
    return report.dipendenti.map((dip) {
      final row = <String>[
        dip.nome,
        dip.matricola ?? '',
        '${dip.countPastiIn(report.giorni)}',
      ];
      for (final g in report.giorni) {
        final key =
            '${g.year.toString().padLeft(4, '0')}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';
        final cell = dip.pastiPerGiorno[key] ?? const BuoniPastoGiornoPasti();
        row.add(cell.riepilogo);
      }
      return row;
    }).toList(growable: false);
  }

  static String buildPresenzeCsv(BuoniPastoPresenzeReport report) {
    final buf = StringBuffer();
    buf.writeln(_presenzeHeaders(report).map(_cell).join(';'));
    for (final row in _presenzeRows(report)) {
      buf.writeln(row.map(_cell).join(';'));
    }
    return buf.toString();
  }

  static Uint8List presenzeCsvBytes(BuoniPastoPresenzeReport report) {
    const bom = [0xEF, 0xBB, 0xBF];
    return Uint8List.fromList([
      ...bom,
      ...utf8.encode(buildPresenzeCsv(report)),
    ]);
  }

  static Uint8List presenzeXlsxBytes(BuoniPastoPresenzeReport report) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];
    sheet.appendRow(_presenzeHeaders(report));
    for (final row in _presenzeRows(report)) {
      sheet.appendRow(row);
    }
    sheet.appendRow(const []);
    sheet.appendRow(const ['Legenda']);
    sheet.appendRow(const ['P', 'Pranzo']);
    sheet.appendRow(const ['C', 'Cena']);
    sheet.appendRow(const ['P+C', 'Pranzo e cena']);
    sheet.appendRow(const ['—', 'Nessun pasto']);
    return Uint8List.fromList(excel.encode()!);
  }
}

Future<void> exportBuoniPastoPresenzeExcel(
  BuildContext context, {
  required BuoniPastoPresenzeReport report,
  String pageName = 'Buoni_pasto_presenze',
}) async {
  if (report.dipendenti.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessun dipendente da esportare.')),
    );
    return;
  }
  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: pageName,
    bytes: BuoniPastoExport.presenzeXlsxBytes(report),
    extension: 'xlsx',
    openFile: true,
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export Excel annullato o non riuscito.')),
    );
    return;
  }
  final path = ExcelExportHelper.lastSavedPath;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Export Excel completato (${report.dipendenti.length} dipendenti)'
        '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
      ),
    ),
  );
}

Future<void> exportBuoniPastoPresenzeCsv(
  BuildContext context, {
  required BuoniPastoPresenzeReport report,
  String pageName = 'Buoni_pasto_presenze',
}) async {
  if (report.dipendenti.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessun dipendente da esportare.')),
    );
    return;
  }
  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: pageName,
    bytes: BuoniPastoExport.presenzeCsvBytes(report),
    extension: 'csv',
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export CSV annullato o non riuscito.')),
    );
    return;
  }
  final path = ExcelExportHelper.lastSavedPath;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Export presenze completato (${report.dipendenti.length} dipendenti)'
        '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
      ),
    ),
  );
}

Future<void> exportBuoniPastoExcel(
  BuildContext context, {
  required List<Map<String, dynamic>> rows,
  String pageName = 'Buoni_pasto',
}) async {
  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessuna registrazione da esportare.')),
    );
    return;
  }
  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: pageName,
    bytes: BuoniPastoExport.xlsxBytes(rows),
    extension: 'xlsx',
    openFile: true,
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export Excel annullato o non riuscito.')),
    );
    return;
  }
  final path = ExcelExportHelper.lastSavedPath;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Export Excel completato (${rows.length} righe)'
        '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
      ),
    ),
  );
}

Future<void> exportBuoniPastoCsv(
  BuildContext context, {
  required List<Map<String, dynamic>> rows,
  String pageName = 'Buoni_pasto',
}) async {
  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessuna registrazione da esportare.')),
    );
    return;
  }
  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: pageName,
    bytes: BuoniPastoExport.csvBytes(rows),
    extension: 'csv',
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export CSV annullato o non riuscito.')),
    );
    return;
  }
  final path = ExcelExportHelper.lastSavedPath;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Export CSV completato (${rows.length} righe)'
        '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
      ),
    ),
  );
}
