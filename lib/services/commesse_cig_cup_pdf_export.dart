import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Testo compatibile con Helvetica (WinAnsi) nel package pdf.
String pdfWinAnsiText(String text) {
  var t = text;
  const replacements = <String, String>{
    '\u2014': '-', // em dash
    '\u2013': '-', // en dash
    '\u2212': '-',
    '\u2010': '-',
    '\u2011': '-',
    '\u2018': "'",
    '\u2019': "'",
    '\u201C': '"',
    '\u201D': '"',
    '\u2026': '...',
    '\u00B7': '-',
    '\u00AB': '"',
    '\u00BB': '"',
    '\u00A0': ' ',
  };
  for (final e in replacements.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  return t;
}

/// Tabella PDF elenco commesse CIG/CUP (A4 orizzontale).
Future<Uint8List> buildCommesseCigCupPdfBytes({
  required List<Map<String, dynamic>> rows,
  String? searchFilter,
}) {
  String s(dynamic v) => pdfWinAnsiText((v ?? '').toString().trim());

  String cell(dynamic v) {
    final t = s(v);
    return t.isEmpty ? '-' : t;
  }

  String clip(String text, {int max = 80}) {
    final t = pdfWinAnsiText(text.trim());
    if (t.length <= max) return t;
    return '${t.substring(0, max - 3)}...';
  }

  const headers = <String>[
    'Commessa',
    'CIG',
    'CIG derivato',
    'CUP',
    'Cliente',
  ];

  final data = <List<String>>[];
  for (final r in rows) {
    data.add(<String>[
      clip(cell(r['commessa_code']), max: 24),
      clip(cell(r['cig']), max: 28),
      clip(cell(r['cig_derivato']), max: 36),
      clip(cell(r['cup']), max: 28),
      clip(cell(r['cliente']), max: 32),
    ]);
  }

  final now = DateTime.now();
  final exportedAt =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final filterNote = pdfWinAnsiText((searchFilter ?? '').trim());
  final subtitle = filterNote.isEmpty
      ? 'Elenco commesse - $exportedAt - ${rows.length} righe'
      : 'Elenco commesse - filtro "$filterNote" - $exportedAt - ${rows.length} righe';

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CRONOS - Commesse CIG / CUP',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            subtitle,
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
            fontSize: 8,
          ),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFB8CEA9),
          ),
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.25),
        ),
      ],
    ),
  );

  return doc.save();
}
