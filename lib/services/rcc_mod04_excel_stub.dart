import 'dart:typed_data';

import 'rcc_mod04_excel_types.dart';

/// Su web la compilazione Mod.RCC richiede l'app desktop.
class RccMod04Excel {
  RccMod04Excel._();

  static RccMod04FillDiagnostics? get lastDiagnostics => null;

  static Future<Uint8List> fill(Map<String, String> _) async {
    throw UnsupportedError(
      'Export Mod.RCC_04: usa l\'app desktop (Windows) con Python installato.',
    );
  }
}
