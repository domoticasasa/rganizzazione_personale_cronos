import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../utils/excel_template_assets.dart';
import 'template_excel_python_fill.dart';

/// Compila [Mod.DPIE_00.xlsx] (foglio CONS DPI EST) via Python + openpyxl.
/// Non usa il pacchetto Dart `excel` su desktop: preserva immagini e celle unite.
class VestiarioDpieExcel {
  VestiarioDpieExcel._();

  static const _pyScript = r'''
import json
import sys
import zipfile
from openpyxl import load_workbook
from openpyxl.utils.cell import coordinate_to_tuple

template_path = sys.argv[1]
payload_path = sys.argv[2]
output_path = sys.argv[3]

with open(payload_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

with zipfile.ZipFile(template_path) as z_in:
    template_media = [n for n in z_in.namelist() if n.startswith("xl/media/")]

wb = load_workbook(template_path)
ws = wb["CONS DPI EST"] if "CONS DPI EST" in wb.sheetnames else wb[wb.sheetnames[0]]

def _anchor_for_merged(ref):
    row, col = coordinate_to_tuple(ref)
    for rng in ws.merged_cells.ranges:
        if rng.min_row <= row <= rng.max_row and rng.min_col <= col <= rng.max_col:
            return ws.cell(row=rng.min_row, column=rng.min_col).coordinate
    return ref

for ref, value in payload.items():
    cell = ref.strip().upper()
    if not cell:
        continue
    target = _anchor_for_merged(cell)
    if value is None or (isinstance(value, str) and value == ""):
        ws[target].value = None
    else:
        ws[target] = value

wb.save(output_path)

with zipfile.ZipFile(output_path) as z_out:
    out_media = [n for n in z_out.namelist() if n.startswith("xl/media/")]

min_expected = max(1, len(template_media) - 1)
if len(out_media) < min_expected:
    print(
        f"ERRORE: immagini nel file esportato={len(out_media)}, "
        f"nel template={len(template_media)}. "
        "py -3 -m pip install --upgrade openpyxl",
        file=sys.stderr,
    )
    sys.exit(2)

print(f"MEDIA_OK:{len(out_media)}")
''';

  static Future<Uint8List> fill(Map<String, String> payload) async {
    final tempDir = await Directory.systemTemp.createTemp('vestiario_');
    try {
      final templatePath = await ExcelTemplateAssets.materialize(
        tempDir,
        ExcelTemplateAssets.modDpie,
        'Mod.DPIE_00.xlsx',
      );
      final templateBytes = await File(templatePath).readAsBytes();
      final templateMedia =
          TemplateExcelPythonFill.countXlsxMedia(Uint8List.fromList(templateBytes));
      final minMedia = math.max(1, templateMedia - 1);

      final (bytes, _) = await TemplateExcelPythonFill.fill(
        tempDir: tempDir,
        templatePath: templatePath,
        pyScript: _pyScript,
        payload: payload,
        tempFilePrefix: 'fill_vestiario_dpie',
        minEmbeddedMedia: minMedia,
      );
      return bytes;
    } catch (e) {
      throw Exception(
        'Export modulo vestiario/DPI estivo non riuscito.\n'
        '$e',
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
