// ignore: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'rcc_ricevuta_tesseract_js.dart';

/// OCR Tesseract.js per scontrini / ricevute QT-ENI.
abstract final class RccRicevutaTesseractWeb {
  RccRicevutaTesseractWeb._();

  static bool _tesseractLoaded = false;
  static Completer<void>? _loading;
  static TesseractWorker? _worker;
  static String? _workerLang;

  static Future<void> preloadEngine() async {
    await _ensureTesseractLoaded();
    await _workerForLanguage('ita');
  }

  static Future<void> disposeWorker() async {
    final w = _worker;
    _worker = null;
    _workerLang = null;
    if (w != null) {
      try {
        await w.terminate().toDart;
      } catch (_) {}
    }
  }

  static Future<String?> recognizeBytes(
    Uint8List bytes, {
    String language = 'ita',
    int pageSegMode = 4,
    double scaleMinWidth = 720,
    double scaleMaxEdge = 1100,
    String contrastFilter = 'grayscale(100%) contrast(155%)',
    double? cropTopFraction,
    String charWhitelist = '',
  }) async {
    try {
      await _ensureTesseractLoaded();
      final blob = web.Blob([bytes.toJS].toJS);
      final url = web.URL.createObjectURL(blob);
      try {
        final img = web.HTMLImageElement()..src = url;
        await _waitImageLoad(img);

        final cropTop = cropTopFraction == null
            ? 0
            : (img.naturalHeight * cropTopFraction).round();
        final srcW = img.naturalWidth;
        final srcH = img.naturalHeight - cropTop;
        if (srcW <= 0 || srcH <= 0) return null;

        var scale = 1.0;
        final maxEdge = math.max(srcW, srcH);
        if (maxEdge > scaleMaxEdge) {
          scale = scaleMaxEdge / maxEdge;
        } else if (srcW < scaleMinWidth) {
          scale = scaleMinWidth / srcW;
        }
        final outW = math.max(1, (srcW * scale).round());
        final outH = math.max(1, (srcH * scale).round());

        final canvas =
            web.document.createElement('canvas') as web.HTMLCanvasElement;
        canvas.width = outW;
        canvas.height = outH;
        final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
        ctx.filter = contrastFilter;
        ctx.drawImage(
          img,
          0,
          cropTop.toDouble(),
          srcW.toDouble(),
          srcH.toDouble(),
          0,
          0,
          outW.toDouble(),
          outH.toDouble(),
        );

        final worker = await _workerForLanguage(language);
        final params = JSObject();
        params.setProperty('tessedit_pageseg_mode'.toJS, '$pageSegMode'.toJS);
        params.setProperty('tessedit_char_whitelist'.toJS, charWhitelist.toJS);
        params.setProperty('preserve_interword_spaces'.toJS, '1'.toJS);
        await worker.setParameters(params).toDart;
        final result =
            await worker.recognize(canvas as JSAny).toDart as TesseractResult;
        final text = result.data.text.toDart.trim();
        return text.isEmpty ? null : text;
      } finally {
        web.URL.revokeObjectURL(url);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RccRicevutaTesseractWeb: $e\n$st');
      }
      return null;
    }
  }

  static Future<TesseractWorker> _workerForLanguage(String language) async {
    if (_worker != null && _workerLang == language) return _worker!;
    await disposeWorker();
    _worker = await createWorker(language.toJS).toDart as TesseractWorker;
    _workerLang = language;
    return _worker!;
  }

  static Future<void> _ensureTesseractLoaded() async {
    if (_tesseractLoaded) return;
    if (_loading != null) return _loading!.future;

    _loading = Completer<void>();
    final document = web.window.document;
    const id = 'rcc-tesseract-js';
    final existing = document.getElementById(id) as web.HTMLScriptElement?;
    if (existing != null) {
      if (existing.getAttribute('data-loaded') == '1') {
        _tesseractLoaded = true;
        _loading!.complete();
        _loading = null;
        return;
      }
      existing.addEventListener(
        'load',
        ((web.Event _) {
          existing.setAttribute('data-loaded', '1');
          _tesseractLoaded = true;
          if (!(_loading?.isCompleted ?? true)) _loading!.complete();
          _loading = null;
        }).toJS,
      );
      return _loading!.future;
    }

    final script = document.createElement('script') as web.HTMLScriptElement;
    script.id = id;
    script.src =
        'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js';
    script.type = 'text/javascript';
    script.crossOrigin = 'anonymous';
    script.onload = ((web.Event _) {
      script.setAttribute('data-loaded', '1');
      _tesseractLoaded = true;
      if (!(_loading?.isCompleted ?? true)) _loading!.complete();
      _loading = null;
    }).toJS;
    script.onerror = ((web.Event _) {
      if (!(_loading?.isCompleted ?? true)) {
        _loading!.completeError('Tesseract.js non caricato');
      }
      _loading = null;
    }).toJS;
    document.head!.appendChild(script);
    return _loading!.future;
  }

  static Future<void> _waitImageLoad(web.HTMLImageElement img) {
    final completer = Completer<void>();
    img.onload = ((web.Event _) => completer.complete()).toJS;
    img.onerror = ((web.Event _) {
      completer.completeError('Immagine non caricata');
    }).toJS;
    return completer.future;
  }
}
