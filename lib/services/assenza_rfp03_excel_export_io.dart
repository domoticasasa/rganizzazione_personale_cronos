import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'assenza_rfp03_excel_export_common.dart';
import 'assenza_rfp03_excel_template_fill.dart';
import 'template_excel_python_fill.dart';
import '../utils/excel_template_assets.dart';

const String _pyScript = r'''
import json
import sys
from openpyxl import load_workbook
from openpyxl.styles import Alignment
from openpyxl.utils.cell import coordinate_to_tuple, get_column_letter

template_path = sys.argv[1]
payload_path = sys.argv[2]
output_path = sys.argv[3]

with open(payload_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

wb = load_workbook(template_path)
ws = wb["Mod.RFP"] if "Mod.RFP" in wb.sheetnames else wb[wb.sheetnames[0]]

merge_anchor = {}
for rng in ws.merged_cells.ranges:
    min_col, min_row, max_col, max_row = rng.bounds
    anchor = f"{get_column_letter(min_col)}{min_row}"
    for rr in range(min_row, max_row + 1):
        for cc in range(min_col, max_col + 1):
            merge_anchor[f"{get_column_letter(cc)}{rr}"] = anchor

note_cell = None
for ref, value in payload.items():
    cell_ref = str(ref).strip().upper()
    if not cell_ref or cell_ref.startswith("__"):
        continue
    target_ref = merge_anchor.get(cell_ref, cell_ref)
    if target_ref != cell_ref:
        cell_ref = target_ref
    if value is None or str(value) == "":
        ws[cell_ref].value = None
    else:
        # Sempre testo: evita che ExcelTS/LibreOffice taglino «10» in «1».
        ws[cell_ref].value = str(value)
        if cell_ref == "D46" or str(value).startswith("Note:"):
            note_cell = cell_ref

# Note sistema: wrap + altezza riga in base alla lunghezza (niente testo tagliato).
if note_cell:
    text = str(ws[note_cell].value or "")
    ws[note_cell].alignment = Alignment(wrap_text=True, vertical="top", horizontal="left")
    # Conta anche i newline espliciti; ~42 caratteri per riga nell'area D–M.
    lines = 0
    for part in text.splitlines() or [text]:
        lines += max(1, (len(part) // 42) + (1 if len(part) % 42 else 0) if part else 1)
    lines = max(2, lines)
    ws.row_dimensions[46].height = max(72, min(160, 18 * lines + 12))

# PDF: nasconde blocchi DATA 2–5 (righe 20–35) per una sola pagina.
compact_for_pdf = bool(payload.get("__compact_for_pdf__"))
if compact_for_pdf:
    empty_value_cells = [
        "F20", "O20", "C22", "F22", "I22", "L22", "O22", "R22",
        "F24", "O24", "C26", "F26", "I26", "L26", "O26", "R26",
        "F28", "O28", "C30", "F30", "I30", "L30", "O30", "R30",
        "F32", "O32", "C34", "F34", "I34", "L34", "O34", "R34",
    ]
    for ref in empty_value_cells:
        target = merge_anchor.get(ref, ref)
        ws[target].value = None
    for r in range(20, 36):
        ws.row_dimensions[r].hidden = True
        ws.row_dimensions[r].height = 0

try:
    ws.sheet_view.view = "normal"
    ws.sheet_view.showGridLines = False
except Exception:
    pass

wb.save(output_path)
''';

Future<Uint8List> buildAssenzaRfp03ExcelBytes({
  required Map<String, dynamic> row,
  required String approvatoreAdminLabel,
  required String dtLabel,
  String? adminComment,
  bool compactForPdf = false,
}) async {
  final payload = buildRfp03Payload(
    row: row,
    approvatoreAdminLabel: approvatoreAdminLabel,
    dtLabel: dtLabel,
    adminComment: adminComment,
  );
  if (compactForPdf) {
    payload['__compact_for_pdf__'] = '1';
  }

  final tempDir = await Directory.systemTemp.createTemp('assenza_rfp03_');
  try {
    try {
      final templatePath = await ExcelTemplateAssets.materialize(
        tempDir,
        ExcelTemplateAssets.modRfp03,
        'Mod.RFP_03.xlsx',
      );
      final (bytes, _) = await TemplateExcelPythonFill.fill(
        tempDir: tempDir,
        templatePath: p.normalize(templatePath),
        pyScript: _pyScript,
        payload: payload,
        tempFilePrefix: 'fill_rfp03',
        minEmbeddedMedia: 0,
      );
      return bytes;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('RFP03 Python fill fallito: $e');
      }
      try {
        return await AssenzaRfp03ExcelTemplateFill.fill(
          payload,
          compactForPdf: compactForPdf,
        );
      } catch (e2) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('RFP03 zip fill fallito: $e2');
        }
        return buildAssenzaRfp03ExcelFallbackBytes(
          row: row,
          approvatoreAdminLabel: approvatoreAdminLabel,
          dtLabel: dtLabel,
          adminComment: adminComment,
        );
      }
    }
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
