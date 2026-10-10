import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS()
@staticInterop
class JsQrResult {}

extension JsQrResultExt on JsQrResult {
  @JS('data')
  external String? get data;
}

@JS('jsQR')
external JsQrResult? _jsQR(
  JSAny data,
  int width,
  int height,
);

/// Scanner QR per browser (getUserMedia + jsQR), senza mobile_scanner.
class BuoniPastoWebQrScanner extends StatefulWidget {
  const BuoniPastoWebQrScanner({
    super.key,
    required this.onDetect,
    this.height = 320,
    this.autoStart = false,
  });

  final ValueChanged<String> onDetect;
  final double height;
  final bool autoStart;

  @override
  State<BuoniPastoWebQrScanner> createState() => _BuoniPastoWebQrScannerState();
}

class _BuoniPastoWebQrScannerState extends State<BuoniPastoWebQrScanner> {
  static Completer<void>? _jsQrLoader;
  static int _viewCounter = 0;

  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  web.MediaStream? _stream;
  String? _viewType;
  Timer? _scanTimer;
  bool _starting = false;
  bool _scanning = false;
  bool _handled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_activateCamera());
      });
    }
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  Future<void> _ensureJsQr() async {
    if (_jsQrAvailable()) return;
    if (_jsQrLoader != null) {
      await _jsQrLoader!.future;
      return;
    }
    _jsQrLoader = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = 'js/jsQR.min.js'
      ..async = true;
    script.onLoad.listen((_) {
      if (!(_jsQrLoader?.isCompleted ?? true)) {
        _jsQrLoader!.complete();
      }
    });
    script.onError.listen((_) {
      if (!(_jsQrLoader?.isCompleted ?? true)) {
        _jsQrLoader!.completeError(
          StateError('Impossibile caricare la libreria di scansione QR.'),
        );
      }
    });
    web.document.head?.appendChild(script);
    await _jsQrLoader!.future;
  }

  bool _jsQrAvailable() {
    final jsQr = globalContext['jsQR'];
    return jsQr != null && !jsQr.isUndefinedOrNull;
  }

  Future<web.MediaStream> _openCameraStream() async {
    final mediaDevices = web.window.navigator.mediaDevices;
    if (mediaDevices.isUndefinedOrNull) {
      throw StateError('Fotocamera non supportata da questo browser.');
    }

    final capabilities = mediaDevices.getSupportedConstraints();
    final supportsFacing =
        !capabilities.isUndefinedOrNull && capabilities.facingMode;

    if (supportsFacing) {
      try {
        return await mediaDevices
            .getUserMedia(
              web.MediaStreamConstraints(
                video: web.MediaTrackConstraintSet(facingMode: 'environment'.toJS),
              ),
            )
            .toDart;
      } catch (_) {
        // Prova fotocamera frontale o default.
      }
      try {
        return await mediaDevices
            .getUserMedia(
              web.MediaStreamConstraints(
                video: web.MediaTrackConstraintSet(facingMode: 'user'.toJS),
              ),
            )
            .toDart;
      } catch (_) {
        // Fallback generico sotto.
      }
    }

    return mediaDevices
        .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
        .toDart;
  }

  Future<void> _activateCamera() async {
    if (_starting || _scanning) return;
    setState(() {
      _starting = true;
      _error = null;
      _handled = false;
    });

    try {
      await _ensureJsQr();
      final stream = await _openCameraStream();
      _stream = stream;

      _viewCounter += 1;
      final viewType = 'buoni-pasto-qr-$_viewCounter';
      final video = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true');
      video.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover';
      video.srcObject = stream;
      unawaited(video.play().toDart);

      final container = web.HTMLDivElement();
      container.style
        ..width = '100%'
        ..height = '100%';
      container.append(video);

      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (_) => container,
      );

      _video = video;
      _viewType = viewType;
      _canvas = web.HTMLCanvasElement();
      _scanTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _scanFrame(),
      );

      if (!mounted) return;
      setState(() {
        _scanning = true;
        _starting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = _mapCameraError(e);
      });
    }
  }

  String _mapCameraError(Object e) {
    final msg = e.toString();
    if (msg.contains('NotAllowedError')) {
      return 'Permesso fotocamera negato o bloccato.\n'
          'In Chrome: tocca il lucchetto nell\'indirizzo → Autorizzazioni → '
          'Fotocamera → Consenti, oppure "Reimposta le autorizzazioni" e riprova.';
    }
    if (msg.contains('NotFoundError') || msg.contains('NotReadableError')) {
      return 'Fotocamera non disponibile su questo dispositivo.';
    }
    if (msg.contains('NotSupportedError') || msg.contains('SecurityError')) {
      return 'Fotocamera non disponibile. Usa HTTPS e un browser aggiornato.';
    }
    return 'Errore fotocamera: $e';
  }

  void _scanFrame() {
    if (_handled) return;
    final video = _video;
    final canvas = _canvas;
    if (video == null || canvas == null || !_jsQrAvailable()) return;
    if (video.videoWidth == 0 || video.videoHeight == 0) return;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    final ctx = canvas.getContext('2d');
    if (ctx == null || ctx.isUndefinedOrNull) return;
    final context2d = ctx as web.CanvasRenderingContext2D;
    context2d.drawImage(video, 0, 0);
    final imageData =
        context2d.getImageData(0, 0, canvas.width, canvas.height);
    final result = _jsQR(imageData.data, canvas.width, canvas.height);
    final raw = result?.data?.trim() ?? '';
    if (raw.isEmpty) return;

    _handled = true;
    _stopCamera();
    widget.onDetect(raw);
  }

  void _stopCamera() {
    _scanTimer?.cancel();
    _scanTimer = null;
    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getVideoTracks().toDart) {
        track.stop();
      }
    }
    _stream = null;
    _video = null;
    _canvas = null;
    _viewType = null;
    _scanning = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning && _viewType != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: HtmlElementView(viewType: _viewType!),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Inquadra il QR code esposto dal ristorante.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Per usare la fotocamera dal browser tocca il pulsante qui sotto. '
          'Il telefono chiederà il permesso di accesso.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _starting ? null : _activateCamera,
          icon: _starting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_camera_outlined),
          label: Text(
            _starting ? 'Avvio fotocamera...' : 'Attiva fotocamera',
          ),
        ),
        if ((_error ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
