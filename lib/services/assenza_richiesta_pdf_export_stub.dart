import 'dart:typed_data';

import 'assenza_rfp03_pdf_convert_service.dart';

Future<Uint8List> buildAssenzaRichiestaPdfBytes({
  required Map<String, dynamic> row,
  required String dipendenteLabel,
  required String dtLabel,
  required String approvatoreAdminLabel,
  String? adminComment,
}) async {
  throw AssenzaRfp03PdfConversionException(
    'Export PDF Mod.RFP_03 non supportato su questa piattaforma. '
    'Usa web o Windows con Excel.',
  );
}
