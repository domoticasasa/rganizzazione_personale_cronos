
import 'package:flutter/foundation.dart';

import 'assenza_rfp03_excel_export_common.dart';
import 'assenza_rfp03_excel_template_fill.dart';

Future<Uint8List> buildAssenzaRfp03ExcelBytes({
  required Map<String, dynamic> row,
  required String approvatoreAdminLabel,
  required String dtLabel,
  String? adminComment,
  bool compactForPdf = false,
}) async {
  final payload = buildRfp03Payload(
    row: row,
    approvatoreAdminLabel: approvatoreAdminLabel,
    dtLabel: dtLabel,
    adminComment: adminComment,
  );
  try {
    return await AssenzaRfp03ExcelTemplateFill.fill(
      payload,
      compactForPdf: compactForPdf,
    );
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('RFP03 template zip fill fallito, uso fallback tabellare: $e');
    }
    return buildAssenzaRfp03ExcelFallbackBytes(
      row: row,
      approvatoreAdminLabel: approvatoreAdminLabel,
      dtLabel: dtLabel,
      adminComment: adminComment,
    );
  }
}
