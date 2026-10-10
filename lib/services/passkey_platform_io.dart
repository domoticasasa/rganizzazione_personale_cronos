import 'dart:io' show Platform;

/// Native: Android, iOS, macOS, Windows (Windows Hello). Linux escluso.
bool get passkeyPlatformSupported {
  try {
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows;
  } catch (_) {
    return false;
  }
}
