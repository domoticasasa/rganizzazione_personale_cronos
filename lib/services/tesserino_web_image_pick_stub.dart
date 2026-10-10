import 'dart:typed_data';

/// Su piattaforme non-web: non usare; restituisce subito null.
void pickTesserinoWebImageOnUserGesture({
  required bool camera,
  required void Function(Uint8List? bytes) onDone,
}) {
  onDone(null);
}

Uint8List? peekPendingTesserinoFotoBytes() => null;

Uint8List? takePendingTesserinoFotoBytes() => null;

void clearPendingTesserinoFotoBytes() {}
