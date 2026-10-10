export 'rcc_ricevuta_ocr_stub.dart'
    if (dart.library.html) 'rcc_ricevuta_ocr_web.dart'
    if (dart.library.io) 'rcc_ricevuta_ocr_mobile.dart';
