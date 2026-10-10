import 'package:flutter/foundation.dart';

/// Deep link web: `/?openChat=1` (scorciatoia Home / notifica).
abstract final class AppChatDeepLink {
  AppChatDeepLink._();

  static bool _pendingOpen = false;

  static bool get pendingOpen => _pendingOpen;

  /// Chiama all'avvio (prima che splash/login consumino la URL).
  static void captureFromBootUri(Uri uri) {
    if (!kIsWeb) return;
    final q = uri.queryParameters['openChat']?.trim().toLowerCase() ?? '';
    final hash = uri.fragment.trim().toLowerCase();
    if (q == '1' || q == 'true' || q == 'yes' || hash == 'chat') {
      _pendingOpen = true;
    }
  }

  static void markPending() => _pendingOpen = true;

  static bool consumePendingOpen() {
    if (!_pendingOpen) return false;
    _pendingOpen = false;
    return true;
  }
}
