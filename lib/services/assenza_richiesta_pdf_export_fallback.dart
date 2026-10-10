import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'assenza_rfp03_excel_export_common.dart';
import 'rfp03_template_media.dart';
import 'xlsx_filled_sheet_reader.dart';
import '../utils/date_formatters.dart';

String _s(dynamic v) => (v ?? '').toString().trim();

const _headerBlue = PdfColor.fromInt(0xFF2F5496);
const _introBlue = PdfColor.fromInt(0xFFD6E4F6);
const _accentRed = PdfColor.fromInt(0xFFC00000);
const _gridBorder = PdfColor.fromInt(0xFF808080);
const _gridHeaderBg = PdfColor.fromInt(0xFFF2F2F2);

pw.TextStyle _style({
  double size = 9,
  bool bold = false,
  PdfColor? color,
}) =>
    pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );

/// PDF Mod.RFP_03 con logo, note, firme e footer (immagini dal template Excel).
Future<Uint8List> buildAssenzaRichiestaPdfFallbackBytes({
  required Map<String, dynamic> row,
  required String dipendenteLabel,
  required String dtLabel,
  required String approvatoreAdminLabel,
  String? adminComment,
  Uint8List? filledXlsxBytes,
}) async {
  final images = await loadRfp03TemplateImages();
  final payload = buildRfp03Payload(
    row: row,
    approvatoreAdminLabel: approvatoreAdminLabel,
    dtLabel: dtLabel,
    adminComment: adminComment,
  );

  Map<String, String> cells = Map<String, String>.from(payload);
  if (filledXlsxBytes != null && filledXlsxBytes.isNotEmpty) {
    try {
      final fromXlsx = readXlsxSheetCellValues(filledXlsxBytes);
      for (final key in payload.keys) {
        if (key.startsWith('__')) continue;
        final v = fromXlsx[key];
        if (v != null && v.trim().isNotEmpty) cells[key] = v.trim();
      }
    } catch (_) {
      cells = Map<String, String>.from(payload);
    }
  }

  String cell(String ref, [String fallback = '']) =>
      xlsxCell(cells, ref, payload[ref] ?? fallback);

  final periodoDal = cell('O18', formatDateDdMmYyyy(_s(row['data_dal'])));
  final periodoAl = cell(
    'R18',
    formatDateDdMmYyyy(
      _s(row['prolungato_fino_al']).isNotEmpty
          ? _s(row['prolungato_fino_al'])
          : _s(row['data_al']),
    ),
  );
  final dataDisplay = cell(
    'F16',
    formatDateDdMmYyyy(_s(row['data_dal'])),
  );
  final giorni = cell('L18', cell('O16', '1'));
  final ore = cell('C18');
  final dalleOre = cell('F18', rfp03FormatTime(row['ora_inizio']));
  final alleOre = cell('I18', rfp03FormatTime(row['ora_fine']));
  final nomeDip = cell('D49', dipendenteLabel);
  final tipoRaw = _s(row['tipo_assenza']).toUpperCase();
  final isFerie = tipoRaw == 'FERIE';
  final isPermesso = tipoRaw == 'PERMESSO';
  final isRetribuito = isFerie ||
      isPermesso ||
      cell('D37').contains('\u2713') ||
      cell('D37').toUpperCase() == 'X';
  final isAltro = !isRetribuito;
  final altroSpec = () {
    final raw = cell('E40');
    if (raw.isEmpty) return rfp03TipoLabel(tipoRaw);
    return raw.replaceFirst(RegExp(r'^Altro\s*\(specificare\)\s*:?\s*'), '');
  }();
  final dataRichiestaLabel =
      cell('C44', 'Data richiesta: $dataDisplay');
  final noteText = () {
    final raw = cell('D46').trim();
    if (raw.isNotEmpty) return raw;
    return (payload['D46'] ?? '').trim();
  }();

  final logo = pw.MemoryImage(images.headerLogo);
  final footerStrip = pw.MemoryImage(images.footerStrip);
  final firmaImg = pw.MemoryImage(images.firmaDatore);
  final certImgs =
      images.footerCertLogos.map(pw.MemoryImage.new).toList(growable: false);

  final footerLines = <String>[];
  if (filledXlsxBytes != null && filledXlsxBytes.isNotEmpty) {
    try {
      final fromXlsx = readXlsxSheetCellValues(filledXlsxBytes);
      for (var r = 52; r <= 61; r++) {
        final v = fromXlsx['B$r'];
        if (v != null && v.trim().isNotEmpty) footerLines.add(v.trim());
      }
    } catch (_) {}
  }
  if (footerLines.isEmpty) {
    footerLines.addAll(const [
      'Cronos Sistemi Ferroviari S.p.A. unipersonale',
      'Sede Legale: Viale della Musica, 41 – 00144 Roma Tel. 06 5920901',
      'Unità Locale SV/1: Via Cortemilia, 71 – 17014 Cairo Montenotte (SV)',
      'Unità Locale AG/1: C.da Iniro – 92024 Canicattì (AG)',
      'Unità Locale NA/1: Via Nuova Agnano, 11 – 80125 Napoli (NA)',
      'e-mail: info@cronosrail.com – PEC: cronosrail@legalmail.it – www.cronosrail.com',
      'Società per Azioni – Capitale Sociale: 1.200.000,00 € I.V. – P.IVA 14383401008',
    ]);
  }

  final introText = cell(
    'B13',
    'Il Sottoscritto $nomeDip chiede autorizzazione a usufruire di:',
  );

  pw.Widget gridCell(
    String text, {
    bool header = false,
    bool center = false,
    bool bold = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      color: header ? _gridHeaderBg : null,
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: _style(size: header ? 7 : 8.5, bold: header || bold),
      ),
    );
  }

  pw.Widget tipoVoce(bool selected, String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 16,
            child: pw.Text(
              selected ? '\u2713' : '',
              style: _style(size: 11, bold: true, color: _accentRed),
            ),
          ),
          pw.Expanded(child: pw.Text(label, style: _style(size: 9))),
        ],
      ),
    );
  }

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(16, 10, 16, 10),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // LOGO CRONOS (era assente con ExcelTS)
            pw.Image(logo, height: 56, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              color: _headerBlue,
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Richiesta Ferie - Permessi',
                style: _style(size: 13, bold: true, color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              color: _introBlue,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: pw.Text(introText, style: _style(size: 10)),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: _gridBorder, width: 0.45),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.1),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(children: [
                  gridCell('DATA:', bold: true, center: true),
                  gridCell(dataDisplay, center: true, bold: true),
                  gridCell('N° GIORNI:', bold: true, center: true),
                  gridCell(giorni, center: true, bold: true),
                ]),
              ],
            ),
            pw.Table(
              border: pw.TableBorder.all(color: _gridBorder, width: 0.45),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.9),
                1: pw.FlexColumnWidth(1.05),
                2: pw.FlexColumnWidth(1.05),
                3: pw.FlexColumnWidth(0.95),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(1.1),
              },
              children: [
                pw.TableRow(children: [
                  gridCell('N° ORE', header: true, center: true),
                  gridCell('Dalle ORE', header: true, center: true),
                  gridCell('Alle ORE', header: true, center: true),
                  gridCell('N° GIORNI', header: true, center: true),
                  gridCell('Dal GIORNO', header: true, center: true),
                  gridCell('Al GIORNO', header: true, center: true),
                ]),
                pw.TableRow(children: [
                  gridCell(ore, center: true),
                  gridCell(dalleOre, center: true),
                  gridCell(alleOre, center: true),
                  gridCell(giorni, center: true, bold: true),
                  gridCell(periodoDal, center: true, bold: true),
                  gridCell(periodoAl, center: true, bold: true),
                ]),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text('Di:', style: _style(bold: true, size: 10)),
            pw.SizedBox(height: 3),
            tipoVoce(
              isRetribuito,
              'Ferie - Permesso Retribuito - Ex-Festività Soppresse',
            ),
            tipoVoce(false, 'Permesso non Retribuito'),
            tipoVoce(false, 'Licenza Matrimoniale'),
            tipoVoce(
              isAltro,
              isAltro && altroSpec.isNotEmpty
                  ? 'Altro (specificare): $altroSpec'
                  : 'Altro (specificare)',
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              dataRichiestaLabel,
              style: _style(bold: true, size: 9.5, color: _accentRed),
            ),
            pw.SizedBox(height: 8),
            // NOTE + FIRME (parte centrale/bassa che mancava)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        constraints: const pw.BoxConstraints(minHeight: 68),
                        padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 6),
                        decoration: pw.BoxDecoration(
                          border:
                              pw.Border.all(color: _gridBorder, width: 0.45),
                        ),
                        child: pw.Text(
                          noteText.isEmpty ? 'Note:' : noteText,
                          style: _style(size: 8.5),
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Text('Il Richiedente:', style: _style(bold: true)),
                      pw.SizedBox(height: 20),
                      pw.Container(height: 0.6, color: _gridBorder),
                      pw.SizedBox(height: 3),
                      pw.Text(nomeDip, style: _style(size: 9, bold: true)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Per accettazione',
                        style: _style(bold: true, size: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Image(
                        firmaImg,
                        width: 148,
                        height: 80,
                        fit: pw.BoxFit.contain,
                      ),
                      pw.Container(height: 0.6, color: _gridBorder),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        kRfp03DatoreLavoroNome,
                        style: _style(size: 8, bold: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            // FOOTER: testo azienda + loghi certificazioni
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: footerLines
                        .map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 1.2),
                            child: pw.Text(line, style: _style(size: 5.8)),
                          ),
                        )
                        .toList(),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Image(
                        footerStrip,
                        height: 42,
                        fit: pw.BoxFit.contain,
                      ),
                      if (certImgs.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Wrap(
                          alignment: pw.WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            for (final img in certImgs)
                              pw.Image(img, height: 22, fit: pw.BoxFit.contain),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// PDF da file Excel Mod.RFP_03 gia compilato (stessi dati dell'export Excel).
Future<Uint8List> buildAssenzaRichiestaPdfFromFilledXlsx({
  required Uint8List filledXlsxBytes,
  required Map<String, dynamic> row,
  required String dipendenteLabel,
  required String dtLabel,
  required String approvatoreAdminLabel,
  String? adminComment,
}) {
  return buildAssenzaRichiestaPdfFallbackBytes(
    row: row,
    dipendenteLabel: dipendenteLabel,
    dtLabel: dtLabel,
    approvatoreAdminLabel: approvatoreAdminLabel,
    adminComment: adminComment,
    filledXlsxBytes: filledXlsxBytes,
  );
}
