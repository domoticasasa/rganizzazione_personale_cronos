import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';
import 'rcc_mod04_excel_types.dart';
import 'template_xlsx_zip_fill.dart';

/// Compila [Mod.RCC_04.xlsx] su web preservando layout e immagini del template.
class RccMod04Excel {
  RccMod04Excel._();

  static RccMod04FillDiagnostics? get lastDiagnostics => null;

  static Future<Uint8List> fill(Map<String, String> payload) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.modRcc04);
    final templateBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError('Template Mod.RCC_04.xlsx non disponibile negli asset.');
    }

    return TemplateXlsxZipFill.fill(
      templateBytes: templateBytes,
      sheetName: 'Mod.RCC',
      payload: payload,
      allowCell: allowRccMod04Cell,
    );
  }
}

/// Filtro celle Mod.RCC_04 (allineato a Python desktop).
bool allowRccMod04Cell(String cell) {
  const header = {'D2', 'D3', 'C4', 'H4', 'H36'};
  if (header.contains(cell)) return true;
  return RegExp(r'^[A-H](?:[6-9]|[12][0-9]|3[0-5])$').hasMatch(cell);
}
