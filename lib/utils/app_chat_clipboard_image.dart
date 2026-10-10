import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import 'app_chat_web_paste.dart';

/// Lettura screenshot / immagini dagli appunti (desktop + web).
abstract final class AppChatClipboardImage {
  AppChatClipboardImage._();

  /// Bytes + mime + nome file suggerito, oppure null se non c'è un'immagine.
  static Future<({Uint8List bytes, String mime, String fileName})?>
      readScreenshot() async {
    final raw = await Pasteboard.image;
    if (raw == null || raw.isEmpty) return null;
    final bytes = Uint8List.fromList(raw);
    final info = _guessImageInfo(bytes);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (
      bytes: bytes,
      mime: info.mime,
      fileName: 'screenshot_$stamp.${info.ext}',
    );
  }

  /// Su web: listener nativo `paste` (più affidabile per screen copiati).
  /// Su altre piattaforme: no-op (ritorna null).
  static void Function()? attachNativePasteListener(
    void Function(Uint8List bytes, String mime) onImage,
  ) {
    return attachAppChatWebPasteListener(onImage);
  }

  static ({String mime, String ext}) _guessImageInfo(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return (mime: 'image/png', ext: 'png');
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return (mime: 'image/jpeg', ext: 'jpg');
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x38) {
      return (mime: 'image/gif', ext: 'gif');
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return (mime: 'image/webp', ext: 'webp');
    }
    return (mime: 'image/png', ext: 'png');
  }
}
