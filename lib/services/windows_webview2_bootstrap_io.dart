import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

bool _environmentReady = false;

Future<bool> bootstrapWindowsWebView2() async {
  if (!Platform.isWindows) return true;
  if (_environmentReady) return true;
  try {
    final dir = await getApplicationSupportDirectory();
    final webDir = p.join(dir.path, 'cronos_webview2');
    await Directory(webDir).create(recursive: true);
    await WebviewController.initializeEnvironment(userDataPath: webDir);
    _environmentReady = true;
    return true;
  } on PlatformException catch (e) {
    if (e.code == 'environment_already_initialized') {
      _environmentReady = true;
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> isWindowsWebView2Available() async {
  if (!Platform.isWindows) return false;
  try {
    final version = await WebviewController.getWebViewVersion();
    return version != null && version.trim().isNotEmpty;
  } catch (_) {
    return false;
  }
}
