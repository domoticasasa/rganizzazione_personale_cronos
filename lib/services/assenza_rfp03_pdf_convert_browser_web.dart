// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:flutter/services.dart';

import 'assenza_rfp03_browser_js_exception.dart';

const _scriptElementId = 'cronos-rfp03-excel-to-pdf-v10';
const _assetPath = 'assets/rfp03_excel_to_pdf.js';

@JS('cronosExcelToPdfReady')
external JSPromise<JSAny?> _cronosExcelToPdfReady();

@JS('cronosExcelToPdf')
external JSPromise<JSUint8Array> _cronosExcelToPdf(JSUint8Array xlsxBytes);

@JS('cronosExcelToPdfLastError')
external String _cronosExcelToPdfLastError();


Future<void> _ensureRfp03PdfScriptLoaded() async {
  try {
    await _cronosExcelToPdfReady().toDart;
    return;
  } catch (_) {}

  if (html.document.getElementById(_scriptElementId) == null) {
    final js = await rootBundle.loadString(_assetPath);
    final script = html.ScriptElement()
      ..id = _scriptElementId
      ..type = 'text/javascript'
      ..text = js;
    html.document.head!.append(script);
  }

  for (var i = 0; i < 100; i++) {
    try {
      await _cronosExcelToPdfReady().toDart;
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  throw AssenzaRfp03BrowserJsException(
    'Modulo ExcelTS non inizializzato nel browser.',
  );
}

String _normalizeJsError(Object e) {
  final msg = e.toString();
  if (msg.contains('NoSuchMethodError') &&
      msg.contains('cronosExcelToPdf')) {
    return 'Modulo ExcelTS non disponibile nel browser.';
  }
  return msg;
}

Future<Uint8List> convertXlsxToPdfViaBrowserJs(Uint8List xlsxBytes) async {
  if (xlsxBytes.isEmpty) {
    throw AssenzaRfp03BrowserJsException('File Excel vuoto.');
  }

  await _ensureRfp03PdfScriptLoaded();

  var lastJsError = '';

  for (var i = 0; i < 180; i++) {
    try {
      await _cronosExcelToPdfReady().toDart;
      break;
    } catch (e) {
      lastJsError = _normalizeJsError(e);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (i == 179) {
      throw AssenzaRfp03BrowserJsException(
        lastJsError.isEmpty
            ? 'ExcelTS non caricato (timeout 90 s). Verifica la connessione internet.'
            : lastJsError,
      );
    }
  }

  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final jsPdf = await _cronosExcelToPdf(xlsxBytes.toJS).toDart;
      final pdf = jsPdf.toDart;
      if (pdf.isNotEmpty) return pdf;
      lastJsError = 'PDF vuoto da ExcelTS';
    } catch (e) {
      lastJsError = _normalizeJsError(e);
      try {
        final fromJs = _cronosExcelToPdfLastError().trim();
        if (fromJs.isNotEmpty) lastJsError = fromJs;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  throw AssenzaRfp03BrowserJsException(
    lastJsError.isEmpty ? 'Conversione ExcelTS fallita.' : lastJsError,
  );
}

/// Precarica ExcelTS in background (primo export PDF più rapido).
void preloadRfp03PdfEngine() {
  unawaited(_ensureRfp03PdfScriptLoaded());
}
