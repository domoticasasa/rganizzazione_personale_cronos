import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/gps_coords_input_row.dart';
import 'excel_export_helper.dart';
import 'mdo_gps_coords.dart';

/// Export CSV commesse (Gestione Dati → tab Commesse).
abstract final class CommesseDataExport {
  static const List<String> _headers = [
    'Nome',
    'CIG',
    'CIG derivato',
    'CUP',
    'Cliente',
    'PM',
    'DT',
    'DT 2',
    'GPS',
    'Attiva',
  ];

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String _cell(String raw) {
    final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
    if (s.contains(';') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _yesNo(bool value) => value ? 'Sì' : 'No';

  static String _gpsCell(Map<String, dynamic> r) {
    final coords = mdoGpsCoordsFromRow(r);
    if (coords == null) return '';
    return GpsCoordsInputRow.formatCoords(coords.$1, coords.$2);
  }

  static List<String> _rowValues(Map<String, dynamic> r) {
    return [
      _s(r['nome']),
      _s(r['cig']),
      _s(r['cig_derivato']),
      _s(r['cup']),
      _s(r['cliente']),
      _s(r['pm']),
      _s(r['dt']),
      _s(r['dt2']),
      _gpsCell(r),
      _yesNo((r['active'] ?? false) == true),
    ];
  }

  /// CSV con separatore `;` (Excel italiano) e BOM UTF-8.
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
}

/// Salva CSV di tutte le commesse caricate in pagina.
Future<void> exportCommesseDataCsv(
  BuildContext context, {
  required List<Map<String, dynamic>> commesseRows,
  void Function(String message, {bool error})? messenger,
}) async {
  void notify(String msg, {bool error = false}) {
    if (messenger != null) {
      messenger(msg, error: error);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  if (commesseRows.isEmpty) {
    notify('Nessuna commessa da esportare.', error: true);
    return;
  }

  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: 'Commesse',
    bytes: CommesseDataExport.csvBytes(commesseRows),
    extension: 'csv',
  );
  if (!ok) {
    notify('Export CSV annullato o non riuscito.', error: true);
    return;
  }

  final path = ExcelExportHelper.lastSavedPath;
  notify(
    'Export CSV completato (${commesseRows.length} righe)'
    '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
  );
}
