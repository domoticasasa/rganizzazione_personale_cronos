import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Canale client per Accessi app: web, android (APK), windows, ios.
String cronosClientPlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    default:
      return '';
  }
}

String cronosClientPlatformLabel(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'web':
      return 'Web';
    case 'android':
      return 'Android (APK)';
    case 'windows':
      return 'Windows';
    case 'ios':
      return 'iOS';
    case 'macos':
      return 'macOS';
    case 'linux':
      return 'Linux';
    default:
      return '—';
  }
}

/// Registra quando l'utente apre/entra in app (`users.last_app_open_at`).
/// Diverso dal login Auth (`last_sign_in_at`).
abstract final class AppOpenTracker {
  AppOpenTracker._();

  static DateTime? _lastTouchLocal;
  static Timer? _foregroundHeartbeat;
  static const _minInterval = Duration(seconds: 30);
  static const _heartbeatInterval = Duration(seconds: 40);

  static Future<void> touchCurrentUser({bool force = false}) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final now = DateTime.now().toUtc();
    final prev = _lastTouchLocal;
    if (!force && prev != null && now.difference(prev) < _minInterval) return;
    _lastTouchLocal = now;

    final platform = cronosClientPlatform();
    try {
      await SupabaseService.client.rpc(
        'touch_my_last_app_open',
        params: {'p_platform': platform},
      );
    } on PostgrestException catch (e) {
      // RPC vecchia (senza parametro) o schema non migrato.
      if (e.code == 'PGRST202' || e.code == '42883') {
        try {
          await SupabaseService.client.rpc('touch_my_last_app_open');
        } catch (_) {}
        return;
      }
      // ignore: avoid_print
      print('>>> AppOpenTracker: $e');
    } catch (e) {
      // ignore: avoid_print
      print('>>> AppOpenTracker: $e');
    }
  }

  /// Heartbeat leggero: aggiorna presenza se passato il throttle heartbeat.
  static Future<void> heartbeat() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final now = DateTime.now().toUtc();
    final prev = _lastTouchLocal;
    if (prev != null && now.difference(prev) < _heartbeatInterval) return;
    await touchCurrentUser(force: true);
  }

  /// Avvia ping presenza mentre l'app è in foreground (online in tempo reale).
  static void startForegroundHeartbeat() {
    _foregroundHeartbeat?.cancel();
    unawaited(touchCurrentUser(force: true));
    _foregroundHeartbeat = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(heartbeat());
    });
  }

  static void stopForegroundHeartbeat() {
    _foregroundHeartbeat?.cancel();
    _foregroundHeartbeat = null;
  }
}
