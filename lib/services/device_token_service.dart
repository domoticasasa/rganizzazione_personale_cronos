import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Push FCM/Firebase rimosso (ottobre 2026).
/// Le notifiche restano: notifiche in-app / bacheca, polling in background
/// e notifiche locali (flutter_local_notifications), Web Push sul web.
/// Questa classe resta solo per non cambiare i punti di chiamata esistenti.
class DeviceTokenService {
  DeviceTokenService._();

  static bool get _isAndroidApk =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Chiede solo il permesso notifiche (serve alle notifiche locali Android).
  static Future<void> registerForCurrentUser() async {
    if (!_isAndroidApk) return;
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  /// Nessun token push da cancellare.
  static Future<void> clearForCurrentUser() async {}
}