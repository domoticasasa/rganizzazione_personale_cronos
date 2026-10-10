import 'dart:typed_data';

import 'assenza_rfp03_browser_js_exception.dart';

Future<Uint8List> convertXlsxToPdfViaBrowserJs(Uint8List xlsxBytes) async =>
    throw AssenzaRfp03BrowserJsException(
      'Conversione ExcelTS disponibile solo su web.',
    );

/// No-op fuori da web.
void preloadRfp03PdfEngine() {}
