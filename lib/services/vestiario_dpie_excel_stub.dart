import 'dart:typed_data';

/// Su web / piattaforme senza `dart:io` la generazione Excel non è disponibile.
class VestiarioDpieExcel {
  VestiarioDpieExcel._();

  static Future<Uint8List> fill(Map<String, String> _) async {
    throw UnsupportedError(
      'Il modulo Excel si genera dall’app desktop (Windows/macOS/Linux) con Python installato.',
    );
  }
}
