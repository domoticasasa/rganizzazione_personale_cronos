import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Fotocamera **dentro** CRONOS (getUserMedia). Non apre l’app Camera di
/// sistema, così WhatsApp/WebView non va in OOM e non chiede di nuovo l’impronta.
Future<Uint8List?> capturePhotoInApp(
  BuildContext context, {
  String title = 'Fotocamera',
  String hint = 'Inquadra lo scontrino e tocca Scatta',
}) async {
  web.MediaStream? stream;
  String? startError;
  try {
    stream = await _openCameraStream();
  } catch (e) {
    startError = _mapCameraError(e);
  }
  if (!context.mounted) {
    _stopStream(stream);
    return null;
  }
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _WebInAppCameraDialog(
      title: title,
      hint: hint,
      stream: stream,
      startError: startError,
    ),
  );
}

Future<web.MediaStream> _openCameraStream() async {
  final mediaDevices = web.window.navigator.mediaDevices;
  if (mediaDevices.isUndefinedOrNull) {
    throw StateError('Fotocamera non supportata da questo browser.');
  }

  try {
    return await mediaDevices
        .getUserMedia(
          web.MediaStreamConstraints(
            video: <String, Object>{
              'facingMode': <String, String>{'ideal': 'environment'},
              'width': <String, int>{'ideal': 1280, 'max': 1600},
              'height': <String, int>{'ideal': 960, 'max': 1200},
            }.jsify()!,
          ),
        )
        .toDart;
  } catch (_) {}

  try {
    return await mediaDevices
        .getUserMedia(
          web.MediaStreamConstraints(
            video: web.MediaTrackConstraintSet(facingMode: 'environment'.toJS),
          ),
        )
        .toDart;
  } catch (_) {}

  return mediaDevices
      .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
      .toDart;
}

void _stopStream(web.MediaStream? stream) {
  if (stream == null) return;
  try {
    for (final track in stream.getVideoTracks().toDart) {
      track.stop();
    }
  } catch (_) {}
}

String _mapCameraError(Object e) {
  final msg = e.toString();
  if (msg.contains('NotAllowedError')) {
    return 'Permesso fotocamera negato.\n'
        'Tocca il lucchetto nell’indirizzo e consenti la fotocamera, '
        'oppure scegli la foto dalla galleria.';
  }
  if (msg.contains('NotFoundError') || msg.contains('NotReadableError')) {
    return 'Fotocamera non disponibile. Scegli la foto dalla galleria.';
  }
  if (msg.contains('NotSupportedError') || msg.contains('SecurityError')) {
    return 'Questo browser non può usare la fotocamera in pagina. '
        'Apri CRONOS in Chrome o Safari (non dal link di WhatsApp).';
  }
  return 'Fotocamera non avviata. Scegli la foto dalla galleria.';
}

bool _isWhatsAppWebView() {
  try {
    return web.window.navigator.userAgent.toLowerCase().contains('whatsapp');
  } catch (_) {
    return false;
  }
}

class _WebInAppCameraDialog extends StatefulWidget {
  const _WebInAppCameraDialog({
    required this.title,
    required this.hint,
    required this.stream,
    required this.startError,
  });

  final String title;
  final String hint;
  final web.MediaStream? stream;
  final String? startError;

  @override
  State<_WebInAppCameraDialog> createState() => _WebInAppCameraDialogState();
}

class _WebInAppCameraDialogState extends State<_WebInAppCameraDialog> {
  static int _viewCounter = 0;

  web.HTMLVideoElement? _video;
  String? _viewType;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    final stream = widget.stream;
    if (stream == null) return;

    _viewCounter += 1;
    final viewType = 'cronos-in-app-cam-$_viewCounter';
    final video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true');
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..backgroundColor = '#000';
    video.srcObject = stream;
    unawaited(video.play().toDart);

    final container = web.HTMLDivElement();
    container.style
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = '#000';
    container.append(video);

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (_) => container,
    );

    _video = video;
    _viewType = viewType;
  }

  @override
  void dispose() {
    _stopStream(widget.stream);
    _video = null;
    super.dispose();
  }

  Future<void> _capture() async {
    if (_capturing) return;
    final video = _video;
    if (video == null) return;
    if (video.videoWidth == 0 || video.videoHeight == 0) return;

    setState(() => _capturing = true);
    try {
      final bytes = _snapshotJpeg(video);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _capturing = false);
        return;
      }
      Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Uint8List? _snapshotJpeg(web.HTMLVideoElement video) {
    final vw = video.videoWidth;
    final vh = video.videoHeight;
    if (vw <= 0 || vh <= 0) return null;

    const maxEdge = 1280.0;
    final edge = vw > vh ? vw.toDouble() : vh.toDouble();
    final scale = edge > maxEdge ? maxEdge / edge : 1.0;

    final canvas = web.HTMLCanvasElement()
      ..width = (vw * scale).round()
      ..height = (vh * scale).round();
    final ctx = canvas.getContext('2d');
    if (ctx == null || ctx.isUndefinedOrNull) return null;
    final context2d = ctx as web.CanvasRenderingContext2D;
    (context2d as JSObject).callMethodVarArgs(
      'drawImage'.toJS,
      <JSAny?>[
        video,
        0.toJS,
        0.toJS,
        canvas.width.toJS,
        canvas.height.toJS,
      ],
    );

    final dataUrl = canvas.toDataURL('image/jpeg', 0.72.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || comma >= dataUrl.length - 8) return null;
    return base64Decode(dataUrl.substring(comma + 1));
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.startError;
    final previewH = (MediaQuery.sizeOf(context).height * 0.52).clamp(220.0, 420.0);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              err ?? widget.hint,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_isWhatsAppWebView() && err != null) ...[
              const SizedBox(height: 8),
              Text(
                'Se sei dentro WhatsApp, apri il sito in Chrome: '
                'menu ⋮ → Apri in Chrome.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_viewType != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: previewH,
                  width: double.infinity,
                  child: HtmlElementView(viewType: _viewType!),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _capturing ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        if (_viewType != null)
          FilledButton.icon(
            onPressed: _capturing ? null : _capture,
            icon: _capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(_capturing ? 'Salvataggio…' : 'Scatta'),
          ),
      ],
    );
  }
}
