import 'dart:typed_data';

/// Su piattaforme non-web: nessun listener nativo.
void Function()? attachAppChatWebPasteListener(
  void Function(Uint8List bytes, String mime) onImage,
) {
  return null;
}
