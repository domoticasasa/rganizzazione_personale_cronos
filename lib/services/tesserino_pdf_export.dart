import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../widgets/cronos_tesserino_card.dart';
import '../widgets/cronos_tesserino_style.dart';

/// Punti PDF (1 pt = 1/72") da millimetri.
double _mmToPt(double mm) => mm * 72 / 25.4;

/// ISO 216 A4: 210 mm × 297 mm.
const double _a4WidthMm = 210.0;
const double _a4HeightMm = 297.0;

PdfColor _cronBarPdf() => PdfColor(47 / 255, 82 / 255, 143 / 255);

pw.Widget _extraLine(
  double cardW,
  pw.Font bold,
  String text,
  int extraLineCount,
) {
  final fs = CronosTesserinoStyle.valueFontSizeForCount(cardW, extraLineCount);
  final pad = CronosTesserinoStyle.lineBottomPadding(hasExtraLine: true);
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: pad),
    child: pw.Text(
      text.trim(),
      maxLines: 2,
      style: pw.TextStyle(
        font: bold,
        fontSize: fs,
        height: extraLineCount > 2 ? 1.05 : 1.12,
      ),
    ),
  );
}

pw.Widget _dataLine(
  double cardW,
  pw.Font bold,
  String label,
  String rawVal, {
  required bool hasExtraLine,
  int extraLineCount = 0,
}) {
  final v = rawVal.trim().isEmpty ? '\u2014' : rawVal.trim();
  final count = extraLineCount > 0 ? extraLineCount : (hasExtraLine ? 1 : 0);
  final ls = count > 0
      ? CronosTesserinoStyle.labelFontSizeForCount(cardW, count)
      : CronosTesserinoStyle.labelFontSize(cardW, hasExtraLine: hasExtraLine);
  final vs = count > 0
      ? CronosTesserinoStyle.valueFontSizeForCount(cardW, count)
      : CronosTesserinoStyle.valueFontSize(cardW, hasExtraLine: hasExtraLine);
  final pad = CronosTesserinoStyle.lineBottomPadding(hasExtraLine: hasExtraLine);
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: pad),
    child: pw.RichText(
      maxLines: 2,
      text: pw.TextSpan(
        style: pw.TextStyle(
          font: bold,
          fontSize: ls,
          height: hasExtraLine ? 1.1 : 1.15,
        ),
        children: [
          pw.TextSpan(text: label),
          pw.TextSpan(
            text: v,
            style: pw.TextStyle(
              font: bold,
              fontSize: vs,
              height: hasExtraLine ? 1.12 : 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// PDF su **foglio A4** (210×297 mm): tesserino **85,60×53,98 mm** centrato (ISO ID-1), come in app.
Future<Uint8List> buildTesserinoPdfBytes({
  required CronosTesserinoViewData data,
  Uint8List? fotoBytes,
}) async {
  final extra = data.hasRigaExtra;
  final extraCount = data.extraLineCount;
  final cardW = _mmToPt(CronosTesserinoStyle.id1WidthMm);
  final cardH = _mmToPt(CronosTesserinoStyle.id1HeightMm);
  final sheetW = _mmToPt(_a4WidthMm);
  final sheetH = _mmToPt(_a4HeightMm);
  final headerH = cardW * CronosTesserinoStyle.id1HeaderHeightOverWidth;
  final barH = cardW * CronosTesserinoStyle.id1BottomBarHeightOverWidth;
  final labelFs = extraCount > 0
      ? CronosTesserinoStyle.labelFontSizeForCount(cardW, extraCount)
      : CronosTesserinoStyle.labelFontSize(cardW, hasExtraLine: extra);

  pw.MemoryImage? headerImg;
  for (final asset in [
    CronosTesserinoStyle.assetHeaderPng,
    CronosTesserinoStyle.assetHeaderFallback,
  ]) {
    try {
      final bd = await rootBundle.load(asset);
      headerImg = pw.MemoryImage(bd.buffer.asUint8List());
      break;
    } catch (_) {}
  }

  pw.ImageProvider? fotoImg;
  if (fotoBytes != null && fotoBytes.isNotEmpty) {
    try {
      fotoImg = pw.MemoryImage(fotoBytes);
    } catch (_) {}
  }

  final hb = pw.Font.helveticaBold();
  final hr = pw.Font.helvetica();

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(sheetW, sheetH, marginAll: 0),
      build: (context) {
        return pw.Container(
          width: sheetW,
          height: sheetH,
          color: PdfColors.white,
          child: pw.Center(
            child: pw.SizedBox(
              width: cardW,
              height: cardH,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.black, width: 0.75),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.SizedBox(
                      height: headerH,
                      width: cardW,
                      child: pw.Center(
                        child: headerImg != null
                            ? pw.SizedBox(
                                width:
                                    cardW * CronosTesserinoStyle.headerLogoScale,
                                height: headerH,
                                child: pw.Image(headerImg, fit: pw.BoxFit.contain),
                              )
                            : pw.Text(
                                'CRONOS',
                                style: pw.TextStyle(
                                  font: hb,
                                  fontSize: cardW *
                                      0.055 *
                                      CronosTesserinoStyle.headerLogoScale,
                                ),
                              ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Padding(
                        padding: pw.EdgeInsets.fromLTRB(
                          cardW * 0.028,
                          extra ? 1.5 : 2,
                          cardW * 0.022,
                          extra ? 1.5 : 2,
                        ),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              flex: 100,
                              child: pw.FittedBox(
                                fit: pw.BoxFit.scaleDown,
                                alignment: pw.Alignment.topLeft,
                                child: pw.SizedBox(
                                  width: cardW * 0.68,
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    mainAxisAlignment: pw.MainAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        CronosTesserinoStyle.via,
                                        style: pw.TextStyle(
                                          font: hb,
                                          fontSize: labelFs,
                                          height: extra ? 1.1 : 1.15,
                                        ),
                                      ),
                                      pw.Text(
                                        CronosTesserinoStyle.cf,
                                        style: pw.TextStyle(
                                          font: hb,
                                          fontSize: labelFs,
                                          height: extra ? 1.1 : 1.15,
                                        ),
                                      ),
                                      pw.SizedBox(
                                        height: CronosTesserinoStyle
                                            .blockGapBeforeAnagrafica(
                                          cardW,
                                          hasExtraLine: extra,
                                          extraLineCount: extraCount,
                                        ),
                                      ),
                                      _dataLine(
                                        cardW,
                                        hb,
                                        CronosTesserinoStyle.lblNome,
                                        data.nome,
                                        hasExtraLine: extra,
                                        extraLineCount: extraCount,
                                      ),
                                      _dataLine(
                                        cardW,
                                        hb,
                                        CronosTesserinoStyle.lblCognome,
                                        data.cognome,
                                        hasExtraLine: extra,
                                        extraLineCount: extraCount,
                                      ),
                                      _dataLine(
                                        cardW,
                                        hb,
                                        CronosTesserinoStyle.lblNato,
                                        data.natoIl,
                                        hasExtraLine: extra,
                                        extraLineCount: extraCount,
                                      ),
                                      _dataLine(
                                        cardW,
                                        hb,
                                        CronosTesserinoStyle.lblAssunto,
                                        data.assuntoDal,
                                        hasExtraLine: extra,
                                        extraLineCount: extraCount,
                                      ),
                                      _dataLine(
                                        cardW,
                                        hb,
                                        CronosTesserinoStyle.lblTess,
                                        data.numeroTesserino,
                                        hasExtraLine: extra,
                                        extraLineCount: extraCount,
                                      ),
                                      if (extra)
                                        for (final line in data.righeExtra)
                                          _extraLine(
                                            cardW,
                                            hb,
                                            line,
                                            extraCount,
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            pw.SizedBox(width: cardW * 0.018),
                            pw.SizedBox(
                              width: cardW * 0.26,
                              child: pw.Container(
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  border: pw.Border.all(
                                    color: PdfColors.black,
                                    width: 0.75,
                                  ),
                                ),
                                child: pw.AspectRatio(
                                  aspectRatio:
                                      CronosTesserinoStyle.photoAspectRatio,
                                  child: fotoImg != null
                                      ? pw.Image(fotoImg, fit: pw.BoxFit.cover)
                                      : pw.Center(
                                          child: pw.Text(
                                            '\u2014',
                                            style: pw.TextStyle(
                                              font: hr,
                                              fontSize: cardW *
                                                  0.08 *
                                                  CronosTesserinoStyle
                                                      .layoutScale(
                                                    hasExtraLine: extra,
                                                  ),
                                              color: PdfColors.grey600,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.Container(height: barH, color: _cronBarPdf()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  return doc.save();
}
