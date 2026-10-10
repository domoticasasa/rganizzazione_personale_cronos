// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'app_device_unlock_gate.dart';

/// Chiave sessionStorage: foto scelta ma non ancora caricata (sopravvive al reload
/// tipico di iOS/PWA dopo la fotocamera di sistema).
const String kTesserinoPendingFotoStorageKey = 'cronos_pending_tesserino_foto_v1';

/// Apre subito il selettore (stesso gesto utente del [onTap]).
/// [onDone] viene chiamato quando l'utente sceglie un file o annulla.
void pickTesserinoWebImageOnUserGesture({
  required bool camera,
  required void Function(Uint8List? bytes) onDone,
}) {
  AppDeviceUnlockGate.beginExternalPicker();
  final input = html.FileUploadInputElement();
  input.setAttribute('type', 'file');
  input.accept = 'image/*';
  if (camera) {
    input.setAttribute('data-cronos-source', 'camera');
  }

  final target = html.document.querySelector('#__tesserino_web_picker_host') ??
      (() {
        final host = html.DivElement()
          ..id = '__tesserino_web_picker_host'
          ..style.setProperty('position', 'fixed')
          ..style.setProperty('left', '-9999px')
          ..style.setProperty('width', '1px')
          ..style.setProperty('height', '1px')
          ..style.setProperty('opacity', '0')
          ..style.setProperty('overflow', 'hidden')
          ..style.setProperty('pointer-events', 'none');
        html.document.body?.append(host);
        return host;
      })();

  var completed = false;
  Timer? cancelTimer;

  late final void Function(html.Event) onWindowFocus;
  late final void Function(html.Event) onVisibility;

  void complete(Uint8List? bytes) {
    if (completed) return;
    completed = true;
    cancelTimer?.cancel();
    try {
      html.window.removeEventListener('focus', onWindowFocus);
      html.document.removeEventListener('visibilitychange', onVisibility);
    } catch (_) {}
    // Non rimuovere subito l'input: alcuni browser finiscono di esporre
    // `files` solo dopo il ritorno focus; lo lasciamo nel host.
    try {
      AppDeviceUnlockGate.endExternalPicker();
    } catch (_) {}
    onDone(bytes);
  }

  Future<void> handleFiles(List<html.File> files) async {
    if (files.isEmpty) {
      complete(null);
      return;
    }
    try {
      final bytes = await _readHtmlFileBytes(files.first);
      if (bytes != null && bytes.isNotEmpty) {
        _stashPendingFotoBytes(bytes);
      }
      complete(bytes);
    } catch (_) {
      complete(null);
    }
  }

  void tryCompleteFromInput() {
    if (completed) return;
    final list = input.files;
    if (list != null && list.isNotEmpty) {
      handleFiles(list);
      return;
    }
  }

  void scheduleCancelCheck() {
    cancelTimer?.cancel();
    // Dopo fotocamera iOS il focus puo' arrivare PRIMA che `files` sia pronto.
    // Aspettiamo a lungo e riproviamo piu' volte prima di considerare annullato.
    cancelTimer = Timer(const Duration(milliseconds: 1800), () {
      if (completed) return;
      tryCompleteFromInput();
      if (completed) return;
      Timer(const Duration(milliseconds: 1200), () {
        if (completed) return;
        tryCompleteFromInput();
        if (completed) return;
        final visible = html.document.visibilityState == 'visible';
        final list = input.files;
        if (visible && (list == null || list.isEmpty)) {
          complete(null);
        }
      });
    });
  }

  onWindowFocus = (_) {
    scheduleCancelCheck();
  };
  onVisibility = (_) {
    if (html.document.visibilityState == 'visible') {
      scheduleCancelCheck();
    }
  };

  input.onChange.listen((_) {
    final list = input.files;
    if (list == null || list.isEmpty) {
      // Non annullare subito: su alcuni browser change scatta vuoto e poi si riempie.
      scheduleCancelCheck();
      return;
    }
    handleFiles(list);
  });

  input.onError.listen((_) => complete(null));

  html.window.addEventListener('focus', onWindowFocus);
  html.document.addEventListener('visibilitychange', onVisibility);

  // Non fare clear del host se c'e' un input precedente ancora in uso: sostituisci.
  target.children.clear();
  target.children.add(input);
  // Defer minimo: alcuni browser richiedono l'input gia' nel DOM.
  scheduleMicrotask(() {
    if (completed) return;
    try {
      input.click();
    } catch (_) {
      complete(null);
    }
  });
}

/// Legge una foto in attesa senza rimuoverla.
Uint8List? peekPendingTesserinoFotoBytes() {
  try {
    final raw = html.window.sessionStorage[kTesserinoPendingFotoStorageKey];
    if (raw == null || raw.isEmpty) return null;
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

/// Recupera (e rimuove) una foto in attesa dopo reload pagina.
Uint8List? takePendingTesserinoFotoBytes() {
  final bytes = peekPendingTesserinoFotoBytes();
  clearPendingTesserinoFotoBytes();
  return bytes;
}

void clearPendingTesserinoFotoBytes() {
  try {
    html.window.sessionStorage.remove(kTesserinoPendingFotoStorageKey);
  } catch (_) {}
}

void _stashPendingFotoBytes(Uint8List bytes) {
  // WhatsApp WebView ha poca RAM: non salvare foto grandi.
  if (bytes.length > 900 * 1024) return;
  try {
    html.window.sessionStorage[kTesserinoPendingFotoStorageKey] =
        base64Encode(bytes);
  } catch (_) {}
}

Future<Uint8List?> _readHtmlFileBytes(html.File file) async {
  final reader = html.FileReader();
  final completer = Completer<Uint8List?>();

  reader.onLoad.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(Uint8List.view(result));
    } else if (result is Uint8List) {
      completer.complete(result);
    } else {
      completer.complete(null);
    }
  });
  reader.onError.listen((_) {
    if (!completer.isCompleted) completer.complete(null);
  });

  try {
    reader.readAsArrayBuffer(file);
  } catch (_) {
    if (!completer.isCompleted) completer.complete(null);
  }

  return completer.future;
}
