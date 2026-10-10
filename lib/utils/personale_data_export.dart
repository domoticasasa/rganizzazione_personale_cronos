import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'date_formatters.dart';
import 'excel_export_helper.dart';

/// Export CSV anagrafica dipendenti (Gestione Dipendenti).
abstract final class PersonaleDataExport {
  static const List<String> _headers = [
    'Cognome e Nome',
    'Email',
    'Matricola',
    'Ruolo in azienda',
    'N. tesserino',
    'Telefono',
    'Data nascita',
    'Data assunzione',
    'Camera default',
    'Attivo',
    'Login',
  ];

  static String _cell(String raw) {
    final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
    if (s.contains(';') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _yesNo(bool value) => value ? 'Sì' : 'No';

  static List<String> _rowValues(Map<String, dynamic> r) {
    final hasLogin = (r['user_id'] ?? '').toString().trim().isNotEmpty;
    return [
      (r['full_name'] ?? '').toString(),
      (r['email'] ?? '').toString(),
      (r['matricola'] ?? '').toString(),
      (r['ruolo_aziendale'] ?? '').toString(),
      (r['numero_tesserino'] ?? '').toString(),
      (r['telefono'] ?? '').toString(),
      formatDateDdMmYyyy(r['data_nascita']),
      formatDateDdMmYyyy(r['data_assunzione']),
      (r['camera_tipo_default'] ?? '').toString(),
      _yesNo((r['active'] ?? true) == true),
      _yesNo(hasLogin),
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

/// Salva CSV anagrafica dipendenti (righe già filtrate come in pagina).
Future<void> exportPersonaleDataCsv(
  BuildContext context, {
  required List<Map<String, dynamic>> personaleRows,
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

  if (personaleRows.isEmpty) {
    notify('Nessun dipendente da esportare.', error: true);
    return;
  }

  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: 'Gestione_dipendenti',
    bytes: PersonaleDataExport.csvBytes(personaleRows),
    extension: 'csv',
  );
  if (!ok) {
    notify('Export CSV annullato o non riuscito.', error: true);
    return;
  }

  final path = ExcelExportHelper.lastSavedPath;
  notify(
    'Export CSV completato (${personaleRows.length} righe)'
    '${path != null && path.isNotEmpty ? ' → $path' : ''}.',
  );
}
