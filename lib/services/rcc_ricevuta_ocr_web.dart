import 'package:flutter/foundation.dart';

import 'rcc_ricevuta_carburante_parser.dart';
import 'rcc_ricevuta_ocr_best.dart';
import 'rcc_ricevuta_tesseract_web.dart';

abstract final class RccRicevutaOcrPlatform {
  RccRicevutaOcrPlatform._();

  static bool get isSupported => true;

  static Future<void> warmup() => RccRicevutaTesseractWeb.preloadEngine();

  static Future<String?> recognizeFromPath(String path) async => null;

  static Future<String?> recognizeFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      return recognizeBestRicevutaText(bytes, _recognizeOnce);
    } finally {
      await RccRicevutaTesseractWeb.disposeWorker();
    }
  }

  static Future<RccRicevutaParsed?> recognizeParsedFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      return recognizeBestRicevutaParsed(bytes, _recognizeOnce);
    } finally {
      await RccRicevutaTesseractWeb.disposeWorker();
    }
  }

  static Future<String?> _recognizeOnce(
    Uint8List bytes, {
    RicevutaOcrPass? pass,
  }) async {
    final cardFocus = pass?.cardFocus == true;
    try {
      return RccRicevutaTesseractWeb.recognizeBytes(
        bytes,
        language: 'ita',
        pageSegMode: cardFocus ? 7 : 4,
        contrastFilter: cardFocus
            ? 'grayscale(100%) contrast(190%)'
            : 'grayscale(100%) contrast(155%)',
        charWhitelist: cardFocus ? '0123456789*Xx ' : '',
        scaleMaxEdge: cardFocus ? 1000 : 1100,
        scaleMinWidth: cardFocus ? 640 : 720,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RccRicevutaOcrPlatform web: $e\n$st');
      }
      return null;
    }
  }
}
