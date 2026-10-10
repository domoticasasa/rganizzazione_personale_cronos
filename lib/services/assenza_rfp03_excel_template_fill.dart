import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';
import 'template_xlsx_zip_fill.dart';

/// Compila Mod.RFP_03.xlsx dagli asset (web e fallback senza Python).
class AssenzaRfp03ExcelTemplateFill {
  AssenzaRfp03ExcelTemplateFill._();

  /// Altezza riga note (D46:M46) in base alla lunghezza del testo.
  static Map<int, double>? _noteRowHeights(Map<String, String> payload) {
    final note = (payload['D46'] ?? '').trim();
    if (note.isEmpty) return null;
    // ~42 caratteri utili nella fascia D–M; minimo 2 righe (~72pt come template).
    var lines = 0;
    for (final part in note.split(RegExp(r'\r?\n'))) {
      lines += math.max(1, (part.length / 42).ceil());
    }
    lines = math.max(2, lines);
    final height = math.min(160.0, math.max(72.0, 18.0 * lines + 12));
    return {46: height};
  }

  static Future<Uint8List> fill(
    Map<String, String> payload, {
    /// Mantenuto per compatibilità API; non altera più le righe (rompe le immagini).
    bool compactForPdf = false,
  }) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.modRfp03);
    final templateBytes =
        bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError('Template Mod.RFP_03.xlsx non disponibile negli asset.');
    }
    // compactForPdf non nasconde più righe: logo/firma/footer restano ancorati.
    return TemplateXlsxZipFill.fill(
      templateBytes: templateBytes,
      sheetName: 'Mod.RFP',
      payload: payload,
      hideGridLinesForPdf: true,
      forceTextValues: true,
      rowHeights: _noteRowHeights(payload),
    );
  }
}
