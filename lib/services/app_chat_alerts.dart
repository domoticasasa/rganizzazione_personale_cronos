import 'package:flutter/foundation.dart';

import '../services/app_chat_service.dart';
import '../services/web_browser_notifications.dart';
import '../services/web_notification_sound.dart';

/// Suono + banner locale per messaggi chat in arrivo (tab aperta / in background).
/// Con app chiusa o tab non in focus la consegna resta sulla Web Push.
abstract final class AppChatAlerts {
  AppChatAlerts._();

  static DateTime? _lastAt;
  static String? _lastId;

  static Future<void> onIncoming(AppChatMessage msg, {required String? myAuthId}) async {
    if (myAuthId == null || myAuthId.isEmpty) return;
    if (msg.senderAuthId == myAuthId) return;

    // Evita doppio suono (realtime + insert locale mittente).
    if (_lastId == msg.id) return;
    final now = DateTime.now();
    if (_lastAt != null && now.difference(_lastAt!) < const Duration(milliseconds: 400)) {
      if (_lastId == msg.id) return;
    }
    _lastId = msg.id;
    _lastAt = now;

    final isDm = msg.isDirect;
    final title = isDm ? 'GESTOPRO Chat · Privato' : 'GESTOPRO Chat · Gruppo';
    final preview = () {
      final b = (msg.body ?? '').trim();
      if (b.isNotEmpty) {
        return b.length > 140 ? '${b.substring(0, 137)}…' : b;
      }
      final att = (msg.attachmentName ?? '').trim();
      if (att.isNotEmpty) return 'Allegato: $att';
      return 'Nuovo messaggio';
    }();
    final body = '${msg.senderName}: $preview';

    final pageFocused =
        !kIsWeb || WebBrowserNotifications.isDocumentFocused;

    // Tab non in focus: lascia solo la Web Push (altrimenti doppio banner).
    if (kIsWeb && !pageFocused) return;

    // Suono solo con tab in uso (altrimenti lo fa già la push).
    try {
      if (kIsWeb && !WebBrowserNotifications.pushSoundJustPlayed(title, body)) {
        await WebNotificationSound.play();
        WebBrowserNotifications.markInAppSoundPlayed(title, body);
      }
    } catch (_) {}

    // Banner OS web = solo Service Worker (icona Cronos).
  }
}

