
import 'package:flutter/foundation.dart';

import 'assenza_rfp03_excel_export_web.dart';
import 'assenza_rfp03_pdf_convert_service.dart';

/// Web: PDF **solo** dalla conversione del Mod.RFP_03.xlsx
/// (stessa struttura dell'export Excel: 5 blocchi DATA, footer, ecc.).
/// Non usa il layout package:pdf ricostruito (struttura diversa).
Future<Uint8List> buildAssenzaRichiestaPdfBytes({
  required Map<String, dynamic> row,
  required String dipendenteLabel,
  required String dtLabel,
  required String approvatoreAdminLabel,
  String? adminComment,
}) async {
  final filledXlsx = await buildAssenzaRfp03ExcelBytes(
    row: row,
    approvatoreAdminLabel: approvatoreAdminLabel,
    dtLabel: dtLabel,
    adminComment: adminComment,
    compactForPdf: false,
  );
  if (filledXlsx.isEmpty) {
    throw AssenzaRfp03PdfConversionException(
      'Mod.RFP_03.xlsx vuoto: impossibile generare il PDF.',
    );
  }
  if (kDebugMode) {
    // ignore: avoid_print
    print('RFP03 PDF: converto xlsx (${filledXlsx.length} byte) → PDF Excel');
  }
  return convertXlsxToPdfIdentico(filledXlsx);
}
