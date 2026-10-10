import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Template Excel nella cartella [assets/] (stesso livello di logo.png).
abstract final class ExcelTemplateAssets {
  static const modDpi3c = 'assets/Mod.DPI3C_00.xlsx';
  static const modDpie = 'assets/Mod.DPIE_00.xlsx';
  static const modRcc04 = 'assets/Mod.RCC_04.xlsx';
  static const modRfp03 = 'assets/Mod.RFP_03.xlsx';
  static const giustificativoCarburanteMdo =
      'assets/Giustificativo_Carburante_MDO.xlsx';
  static const programmaImpegnoPersonale =
      'assets/Programma_impegno_personale_mod.xlsx';
  static const logoPng = 'assets/logo.png';

  static Future<String> materialize(
    Directory tempDir,
    String assetPath,
    String destFileName,
  ) async {
    final bd = await rootBundle.load(assetPath);
    final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (bytes.isEmpty) {
      throw StateError('Asset vuoto: $assetPath');
    }
    final out = p.join(tempDir.path, destFileName);
    await File(out).writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Percorso file logo per lo script Python, o stringa vuota se assente.
  static Future<String> materializeLogoOrEmpty(Directory tempDir) async {
    try {
      return await materialize(tempDir, logoPng, 'app_logo_temp.png');
    } catch (_) {
      return '';
    }
  }
}
