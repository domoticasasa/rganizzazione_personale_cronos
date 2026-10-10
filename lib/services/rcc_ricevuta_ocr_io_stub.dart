import 'dart:typed_data';

bool get isOcrSupported => false;

bool get isMobileOcrSupported => false;

Future<String> writeTempImage(String dir, String name, Uint8List bytes) async {
  throw UnsupportedError('writeTempImage non disponibile su web.');
}
