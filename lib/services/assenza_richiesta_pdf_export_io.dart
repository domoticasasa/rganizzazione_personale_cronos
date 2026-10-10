import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'assenza_rfp03_excel_export.dart';
import 'assenza_rfp03_pdf_convert_service.dart';
import 'assenza_richiesta_pdf_export_fallback.dart';

Future<bool> _convertExcelToPdfWithPowerShell({
  required String xlsxPath,
  required String pdfPath,
}) async {
  if (!Platform.isWindows) return false;
  final script = r'''
param(
  [Parameter(Mandatory=$true)][string]$XlsxPath,
  [Parameter(Mandatory=$true)][string]$PdfPath
)

$ErrorActionPreference = "Stop"
$excel = $null
$wb = $null
try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $wb = $excel.Workbooks.Open($XlsxPath)
  $xlTypePDF = 0
  $wb.ExportAsFixedFormat($xlTypePDF, $PdfPath)
  $wb.Close($false)
  $excel.Quit()
}
finally {
  if ($wb -ne $null) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wb) | Out-Null }
  if ($excel -ne $null) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
''';
  final psFile = File(
    p.join(Directory.systemTemp.path, 'cronos_rfp03_export_pdf.ps1'),
  );
  await psFile.writeAsString(script, flush: true);
  final proc = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      psFile.path,
      '-XlsxPath',
      xlsxPath,
      '-PdfPath',
      pdfPath,
    ],
    runInShell: true,
  );
  return proc.exitCode == 0 &&
      File(pdfPath).existsSync() &&
      File(pdfPath).lengthSync() > 0;
}

/// Desktop: PDF dal Mod.RFP_03.xlsx via Excel COM, poi Gotenberg.
/// Nessun layout ricostruito: deve essere l'Excel convertito.
Future<Uint8List> buildAssenzaRichiestaPdfBytes({
  required Map<String, dynamic> row,
  required String dipendenteLabel,
  required String dtLabel,
  required String approvatoreAdminLabel,
  String? adminComment,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('assenza_rfp03_pdf_');
  try {
    final xlsxBytes = await buildAssenzaRfp03ExcelBytes(
      row: row,
      approvatoreAdminLabel: approvatoreAdminLabel,
      dtLabel: dtLabel,
      adminComment: adminComment,
      compactForPdf: false,
    );
    if (xlsxBytes.isEmpty) {
      throw AssenzaRfp03PdfConversionException(
        'Mod.RFP_03.xlsx vuoto: impossibile generare il PDF.',
      );
    }

    final xlsxFile = File(p.join(tempDir.path, 'mod_rfp03.xlsx'));
    final pdfFile = File(p.join(tempDir.path, 'mod_rfp03.pdf'));
    await xlsxFile.writeAsBytes(xlsxBytes, flush: true);

    // 1) Excel desktop: export PDF nativo = identico al foglio.
    final ok = await _convertExcelToPdfWithPowerShell(
      xlsxPath: xlsxFile.path,
      pdfPath: pdfFile.path,
    );
    if (ok) {
      return Uint8List.fromList(await pdfFile.readAsBytes());
    }

    // 2) Gotenberg / ExcelTS.
    try {
      return await convertXlsxToPdfIdentico(xlsxBytes);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('RFP03 PDF conversione Office fallita: $e');
      }
    }

    return buildAssenzaRichiestaPdfFallbackBytes(
      row: row,
      dipendenteLabel: dipendenteLabel,
      dtLabel: dtLabel,
      approvatoreAdminLabel: approvatoreAdminLabel,
      adminComment: adminComment,
      filledXlsxBytes: xlsxBytes,
    );
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
