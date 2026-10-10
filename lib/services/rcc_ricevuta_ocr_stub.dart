import 'dart:typed_data';

import 'rcc_ricevuta_carburante_parser.dart';

abstract final class RccRicevutaOcrPlatform {
  RccRicevutaOcrPlatform._();

  static bool get isSupported => false;

  static Future<void> warmup() async {}

  static Future<String?> recognizeFromPath(String path) async => null;

  static Future<String?> recognizeFromBytes(
    Uint8List bytes,
    String fileName,
  ) async =>
      null;

  static Future<RccRicevutaParsed?> recognizeParsedFromBytes(
    Uint8List bytes,
    String fileName,
  ) async =>
      null;
}
