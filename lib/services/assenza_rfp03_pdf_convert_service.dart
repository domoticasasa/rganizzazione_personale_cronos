import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assenza_rfp03_browser_js_exception.dart';
import 'assenza_rfp03_pdf_convert_browser.dart';

/// PDF identico al template: conversione xlsx→PDF via LibreOffice (Gotenberg).
class AssenzaRfp03PdfConversionException implements Exception {
  AssenzaRfp03PdfConversionException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Uint8List?> _invokePdfFunction(
  String functionName,
  Uint8List xlsxBytes, {
  String fileName = 'Mod.RFP_03.xlsx',
  void Function(String details)? onError,
}) async {
  if (xlsxBytes.isEmpty) return null;
  try {
    final res = await Supabase.instance.client.functions.invoke(
      functionName,
      body: <String, dynamic>{
        'fileBase64': base64Encode(xlsxBytes),
        'fileName': fileName,
      },
    );
    final data = res.data;
    if (data is Map) {
      final err = (data['error'] ?? '').toString().trim();
      if (err.isNotEmpty) {
        final details = (data['details'] ?? '').toString().trim();
        onError?.call(details.isEmpty ? err : '$err — $details');
        return null;
      }
      if (res.status == 200) {
        final b64 = (data['pdfBase64'] ?? '').toString();
        if (b64.isNotEmpty) return base64Decode(b64);
      }
    }
    onError?.call('HTTP ${res.status}');
    return null;
  } catch (e) {
    onError?.call(e.toString());
    return null;
  }
}

/// Converte xlsx compilato in PDF (LibreOffice via Gotenberg).
Future<Uint8List?> convertXlsxToPdfViaGotenberg(
  Uint8List xlsxBytes, {
  String fileName = 'Mod.RFP_03.xlsx',
  void Function(String details)? onError,
}) =>
    _invokePdfFunction(
      'convert-office-pdf',
      xlsxBytes,
      fileName: fileName,
      onError: onError,
    );

bool _looksLikePdf(Uint8List bytes) {
  if (bytes.length < 5) return false;
  return bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}

/// PDF = conversione del Mod.RFP_03.xlsx (stessa struttura dell'Excel).
/// Preferisce sempre ExcelTS/Gotenberg: mai un layout ricostruito.
Future<Uint8List> convertXlsxToPdfIdentico(Uint8List xlsxBytes) async {
  String? jsError;
  String? gotenbergError;
  Uint8List? excelTsPdf;

  if (kIsWeb) {
    try {
      final pdf = await convertXlsxToPdfViaBrowserJs(xlsxBytes);
      if (_looksLikePdf(pdf) && pdf.length > 2000) {
        excelTsPdf = pdf;
        // Con immagini tipicamente >40KB; sotto = struttura Excel ma media assenti.
        if (pdf.length >= 40000) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('RFP03 PDF: ExcelTS completo (${pdf.length} byte)');
          }
          return pdf;
        }
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'RFP03 PDF: ExcelTS struttura ok ma piccolo (${pdf.length} byte) — '
            'provo Gotenberg, altrimenti uso comunque ExcelTS',
          );
        }
      } else {
        jsError = 'ExcelTS PDF non valido (${pdf.length} byte).';
      }
    } on AssenzaRfp03BrowserJsException catch (e) {
      jsError = e.message;
      if (kDebugMode) {
        // ignore: avoid_print
        print('RFP03 PDF: ExcelTS errore: $jsError');
      }
    } catch (e) {
      jsError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('RFP03 PDF: ExcelTS errore: $jsError');
      }
    }
  }

  final pdf = await convertXlsxToPdfViaGotenberg(
    xlsxBytes,
    onError: (d) => gotenbergError = d,
  );
  if (pdf != null && _looksLikePdf(pdf) && pdf.isNotEmpty) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('RFP03 PDF: Gotenberg ok (${pdf.length} byte)');
    }
    return pdf;
  }

  // Meglio la struttura Excel (anche senza tutte le immagini) del layout finto.
  if (excelTsPdf != null && excelTsPdf.isNotEmpty) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        'RFP03 PDF: uso ExcelTS (${excelTsPdf.length} byte) — '
        'stessa struttura del Mod.RFP_03',
      );
    }
    return excelTsPdf;
  }

  final parts = <String>[];
  if (jsError != null && jsError.isNotEmpty) {
    parts.add('Browser/ExcelTS: $jsError');
  }
  if (gotenbergError != null && gotenbergError!.isNotEmpty) {
    if (gotenbergError!.contains('GOTENBERG_URL not configured')) {
      parts.add(
        'Gotenberg non configurato (secret GOTENBERG_URL su Supabase).',
      );
    } else {
      parts.add('Gotenberg: $gotenbergError');
    }
  }
  if (parts.isEmpty) {
    parts.add('Nessun convertitore Office disponibile.');
  }

  throw AssenzaRfp03PdfConversionException(
    'Impossibile convertire Mod.RFP_03.xlsx in PDF. ${parts.join(' ')}',
  );
}
