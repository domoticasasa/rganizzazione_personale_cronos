import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/date_formatters.dart';
import '../utils/formazione_programmazione_dates.dart';
import 'formazione_dlgs_strutture_service.dart';

/// Tabella PDF elenco programmazione formazioni D.Lgs. (A4 orizzontale).
Future<Uint8List> buildProgrammazioneFormazioniPdfBytes({
  required List<Map<String, dynamic>> rows,
  required Map<String, Map<String, dynamic>> personaleById,
  bool employeeOnly = false,
}) {
  return _buildProgrammazionePdfBytes(
    rows: rows,
    personaleById: personaleById,
    employeeOnly: employeeOnly,
    reportTitle: 'CRONOS — Programmazione Formazioni',
    reportSubtitle: 'Corsi D.Lgs. 81/08 con data programmazione',
  );
}

/// Tabella PDF elenco programmazioni corsi RFI (A4 orizzontale).
Future<Uint8List> buildProgrammazioneFormazioniRfiPdfBytes({
  required List<Map<String, dynamic>> rows,
  required Map<String, Map<String, dynamic>> personaleById,
  bool employeeOnly = false,
}) {
  return _buildProgrammazionePdfBytes(
    rows: rows,
    personaleById: personaleById,
    employeeOnly: employeeOnly,
    reportTitle: 'CRONOS — Programmazioni corsi RFI',
    reportSubtitle: 'Corsi RFI con data programmazione (dal/al)',
  );
}

Future<Uint8List> _buildProgrammazionePdfBytes({
  required List<Map<String, dynamic>> rows,
  required Map<String, Map<String, dynamic>> personaleById,
  required bool employeeOnly,
  required String reportTitle,
  required String reportSubtitle,
}) {
  String s(dynamic v) => (v ?? '').toString().trim();
  String fmt(dynamic v) => formatDateDdMmYyyy(v);

  String clip(String text, {int max = 120}) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  final headers = <String>[
    'Data prog.',
    if (!employeeOnly) 'Scadenza',
    if (!employeeOnly) 'Dipendente',
    if (!employeeOnly) 'Matricola',
    'Corso',
    'Ente',
    'Attestato',
    if (employeeOnly) 'Scadenza',
    'ODA',
    'Orario',
    'Modalità',
    'Struttura / Link',
    'Note',
  ];

  final data = <List<String>>[];
  for (final r in rows) {
    final pid = s(r['personale_id']);
    final p = personaleById[pid];
    final prog = formatProgrammazioneDalAl(r['prima_data'], r['seconda_data']);
    if (employeeOnly) {
      data.add(<String>[
        prog.isEmpty ? fmt(r['prima_data']) : prog,
        clip(s(r['corso']), max: 48),
        clip(s(r['ente']), max: 32),
        fmt(r['data_attestato']),
        fmt(r['scadenza_attestato']),
        s(r['oda']),
        s(r['orario']),
        s(r['modalita']),
        clip(
          FormazioneDlgsStruttureService.displayLabel(r).isNotEmpty
              ? FormazioneDlgsStruttureService.displayLabel(r)
              : s(r['struttura_link']),
          max: 56,
        ),
        clip(s(r['note']), max: 80),
      ]);
    } else {
      data.add(<String>[
        prog.isEmpty ? fmt(r['prima_data']) : prog,
        fmt(r['scadenza_attestato']),
        clip(s(p?['full_name']), max: 40),
        s(p?['matricola']),
        clip(s(r['corso']), max: 48),
        clip(s(r['ente']), max: 32),
        fmt(r['data_attestato']),
        s(r['oda']),
        s(r['orario']),
        s(r['modalita']),
        clip(
          FormazioneDlgsStruttureService.displayLabel(r).isNotEmpty
              ? FormazioneDlgsStruttureService.displayLabel(r)
              : s(r['struttura_link']),
          max: 56,
        ),
        clip(s(r['note']), max: 80),
      ]);
    }
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
            reportTitle,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$reportSubtitle · $exportedAt · ${rows.length} corsi',
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
