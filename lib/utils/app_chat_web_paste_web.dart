import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Listener `paste` sul document: cattura screenshot/immagini dagli appunti.
void Function()? attachAppChatWebPasteListener(
  void Function(Uint8List bytes, String mime) onImage,
) {
  void handle(web.Event raw) {
    final e = raw as web.ClipboardEvent;
    final data = e.clipboardData;
    if (data == null) return;
    final items = data.items;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final type = item.type;
      if (!type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file == null) continue;
      e.preventDefault();
      unawaited(_readFile(file, type, onImage));
      return;
    }
  }

  final jsHandler = handle.toJS;
  web.document.addEventListener('paste', jsHandler);
  return () => web.document.removeEventListener('paste', jsHandler);
}

Future<void> _readFile(
  web.File file,
  String mime,
  void Function(Uint8List bytes, String mime) onImage,
) async {
  final jsBuffer = await file.arrayBuffer().toDart;
  final bytes = jsBuffer.toDart.asUint8List();
  if (bytes.isEmpty) return;
  onImage(bytes, mime.isNotEmpty ? mime : 'image/png');
}
