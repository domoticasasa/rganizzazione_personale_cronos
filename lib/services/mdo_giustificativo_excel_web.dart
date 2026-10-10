import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';
import 'rcc_mod04_excel_types.dart';
import 'template_xlsx_zip_fill.dart';

/// Compila [Giustificativo_Carburante_MDO.xlsx] su web preservando layout e immagini del template.
class MdoGiustificativoExcel {
  MdoGiustificativoExcel._();

  static RccMod04FillDiagnostics? get lastDiagnostics => null;

  static Future<Uint8List> fill(Map<String, String> payload) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.giustificativoCarburanteMdo);
    final templateBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError(
        'Template Giustificativo_Carburante_MDO.xlsx non disponibile negli asset.',
      );
    }

    return TemplateXlsxZipFill.fill(
      templateBytes: templateBytes,
      sheetName: 'Mod.RCC',
      payload: payload,
      allowCell: allowMdoGiustificativoCell,
    );
  }
}
