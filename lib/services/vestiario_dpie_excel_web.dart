import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';
import 'template_xlsx_zip_fill.dart';

/// Compila [Mod.DPIE_00.xlsx] su web preservando layout, immagini e XML del template.
class VestiarioDpieExcel {
  VestiarioDpieExcel._();

  static const _sheetName = 'CONS DPI EST';

  static Future<Uint8List> fill(Map<String, String> payload) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.modDpie);
    final templateBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError('Template Mod.DPIE_00.xlsx non disponibile negli asset.');
    }

    return TemplateXlsxZipFill.fill(
      templateBytes: templateBytes,
      sheetName: _sheetName,
      payload: payload,
      allowCell: allowVestiarioDpieCell,
    );
  }
}

/// Celle compilabili nel modulo DPI (allineato a [admin_vestiario_page]).
bool allowVestiarioDpieCell(String cell) {
  if (cell == 'I12' || cell == 'E53') return true;
  if (RegExp(r'^Q(?:1[5-9]|2\d|30)$').hasMatch(cell)) return true;
  if (RegExp(r'^R(?:1[5-9]|2\d|30)$').hasMatch(cell)) return true;
  return false;
}
