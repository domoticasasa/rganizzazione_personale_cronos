import 'dart:typed_data';

import 'rcc_mod04_excel_types.dart';

/// Su web l'export giustificativo MDO richiede l'app desktop.
class MdoGiustificativoExcel {
  MdoGiustificativoExcel._();

  static RccMod04FillDiagnostics? get lastDiagnostics => null;

  static Future<Uint8List> fill(Map<String, String> _) async {
    throw UnsupportedError(
      'Export Giustificativo Carburante MDO: usa l\'app desktop (Windows) con Python installato.',
    );
  }
}
