import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Icona finestra sulla taskbar Windows: il plugin `window_manager.setIcon`
/// spesso non aggiorna la barra; il runner espone un canale nativo che usa
/// WM_SETICON + SetClassLongPtr (vedi `windows/runner/flutter_window.cpp`).
class WindowsTaskbarIcon {
  static const MethodChannel _ch =
      MethodChannel('organizzazione_personale_cronos/taskbar_icon');

  static String? _resolveAssetPath(String flutterAssetPath) {
    if (kIsWeb || !Platform.isWindows) return null;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final full = p.join(exeDir, 'data', 'flutter_assets', flutterAssetPath);
    if (!File(full).existsSync()) {
      assert(() {
        debugPrint('WindowsTaskbarIcon: file mancante: $full');
        return true;
      }());
      return null;
    }
    return full;
  }

  /// Overlay sulla taskbar (pallino/iconetta), senza cambiare icona principale.
  static Future<void> setOverlayFromAssetPath(
    String flutterAssetPath, {
    String description = 'Nuove notifiche',
  }) async {
    final full = _resolveAssetPath(flutterAssetPath);
    if (full == null) return;
    try {
      await _ch.invokeMethod<void>('setOverlay', <String, dynamic>{
        'path': full,
        'description': description,
      });
    } catch (e, st) {
      assert(() {
        debugPrint('WindowsTaskbarIcon: $e\n$st');
        return true;
      }());
    }
  }

  static Future<void> clearOverlay() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _ch.invokeMethod<void>('clearOverlay');
    } catch (e, st) {
      assert(() {
        debugPrint('WindowsTaskbarIcon.clearOverlay: $e\n$st');
        return true;
      }());
    }
  }
}
