import 'dart:io';
import 'package:flutter/foundation.dart';

bool isMobileDevice() {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

bool isDesktopDevice() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}