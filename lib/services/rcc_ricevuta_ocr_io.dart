import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isOcrSupported {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

bool get isMobileOcrSupported => isOcrSupported;

Future<String> writeTempImage(String dir, String name, Uint8List bytes) async {
  final file = File('$dir/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
