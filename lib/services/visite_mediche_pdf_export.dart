import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/date_formatters.dart';

/// Tabella PDF elenco visite mediche programmate (A4 orizzontale).
Future<Uint8List> buildVisiteMedichePdfBytes({
  required List<Map<String, dynamic>> rows,
  required Map<String, Map<String, dynamic>> personaleById,
  bool employeeOnly = false,
}) {
  String s(dynamic v) => (v ?? '').toString().trim();

  String clip(String text, {int max = 120}) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  String dipendente(Map<String, dynamic> r) {
    final nome = s(r['dipendente_nome']);
    if (nome.isNotEmpty) return nome;
    final pid = s(r['personale_id_uuid']);
    return s(personaleById[pid]?['full_name']);
  }

  String matricola(Map<String, dynamic> r) {
    final pid = s(r['personale_id_uuid']);
    return s(personaleById[pid]?['matricola']);
  }

  final headers = <String>[
    'Data e ora',
    if (!employeeOnly) 'Dipendente',
    if (!employeeOnly) 'Matricola',
    'Luogo / struttura',
    'Link',
    'Note',
  ];

  final data = <List<String>>[];
  for (final r in rows) {
    final dt = formatDateTimeItFromSupabase(r['data_visita']);
    data.add(<String>[
      dt.isEmpty ? '—' : dt,
      if (!employeeOnly) clip(dipendente(r), max: 40),
      if (!employeeOnly) s(matricola(r)),
      clip(s(r['luogo_struttura']), max: 48),
      clip(s(r['link']), max: 56),
      clip(s(r['note']), max: 80),
    ]);
  }

  final now = DateTime.now();
  final exportedAt =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CRONOS — Programmazione visite mediche',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Elenco visite programmate · $exportedAt · ${rows.length} visite',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Pagina ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data,
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 7,
          ),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFB8CEA9),
          ),
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.25),
        ),
      ],
    ),
  );

  return doc.save();
}
