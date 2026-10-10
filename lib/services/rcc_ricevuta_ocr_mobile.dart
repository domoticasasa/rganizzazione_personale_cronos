import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'rcc_ricevuta_carburante_parser.dart';
import 'rcc_ricevuta_ocr_best.dart';
import 'rcc_ricevuta_ocr_io.dart'
    if (dart.library.html) 'rcc_ricevuta_ocr_io_stub.dart' as io;

abstract final class RccRicevutaOcrPlatform {
  RccRicevutaOcrPlatform._();

  static bool get isSupported => io.isOcrSupported;

  static Future<void> warmup() async {}

  static TextRecognizer? _recognizer;

  static Future<String?> recognizeFromPath(String path) async {
    if (!isSupported) return null;
    final bytes = await File(path).readAsBytes();
    return recognizeFromBytes(bytes, p.basename(path));
  }

  static Future<String?> recognizeFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!isSupported) return null;
    return recognizeBestRicevutaText(bytes, _recognizeOnce);
  }

  static Future<RccRicevutaParsed?> recognizeParsedFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!isSupported) return null;
    try {
      return recognizeBestRicevutaParsed(bytes, _recognizeOnce);
    } finally {
      await _recognizer?.close();
      _recognizer = null;
    }
  }

  static Future<String?> _recognizeOnce(
    Uint8List bytes, {
    RicevutaOcrPass? pass,
  }) async {
    try {
      final suffix = pass?.cardFocus == true ? 'card' : 'full';
      final dir = await getTemporaryDirectory();
      final path = await io.writeTempImage(
        dir.path,
        'rcc_ricevuta_${suffix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes,
      );
      return _recognizeWithMlKit(path);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _recognizeWithMlKit(String path) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(path);
      final text = await _recognizer!.processImage(input);
      final out = text.text.trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}
