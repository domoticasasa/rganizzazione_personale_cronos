// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';

import 'web_notification_sound.dart';

class WebBrowserNotifications {
  static bool _asked = false;

  static Future<void> requestPermissionIfNeeded() async {
    if (!html.Notification.supported || _asked) return;
    _asked = true;
    try {
      final p = html.Notification.permission;
      if (p == 'default') {
        final res = await html.Notification.requestPermission();
        if (res == 'granted') {
          await WebNotificationSound.unlock();
        }
      } else if (p == 'granted') {
        await WebNotificationSound.unlock();
      }
    } catch (_) {}
  }

  /// Preferire tag stabile (es. id messaggio) per coalescere duplicati OS / Web Push.
  static Future<void> show(String title, String body, {String? tag}) async {
    if (!html.Notification.supported) return;
    try {
      var perm = html.Notification.permission;
      if (perm == 'default') {
        perm = await html.Notification.requestPermission();
      }
      if (perm == 'granted') {
        dynamic cronosPwa = js.context['cronosPwa'];
        if (cronosPwa != null) {
          try {
            await (cronosPwa as dynamic).showOsNotification(
              title,
              body,
              tag ?? 'cronos-${DateTime.now().millisecondsSinceEpoch}',
            );
            return;
          } catch (_) {}
        }
        html.Notification(
          title,
          body: body,
          tag: tag ?? 'cronos-${DateTime.now().millisecondsSinceEpoch}',
          icon: 'icons/Icon-192.png',
        );
      } else if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web browser notification skipped: permission=$perm');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web browser notification error: $e');
      }
    }
  }

  static bool get isDocumentVisible {
    try {
      return html.document.visibilityState == 'visible';
    } catch (_) {
      return true;
    }
  }

  /// Finestra davvero in uso (come il check `client.focused` del service worker).
  static bool get isDocumentFocused {
    try {
      // HtmlDocument in dart:html non espone hasFocus(); usare JS DOM.
      final focused =
          js.JsObject.fromBrowserObject(html.document).callMethod('hasFocus');
      return focused == true;
    } catch (_) {
      return isDocumentVisible;
    }
  }

  static void markInAppSoundPlayed(String title, String body) {
    try {
      js.context['__cronosInAppSoundAt'] =
          DateTime.now().millisecondsSinceEpoch;
      js.context['__cronosInAppSoundKey'] = '$title|$body';
    } catch (_) {}
  }

  /// True se il SW ha già fatto suonare/notificare lo stesso evento (pochi secondi fa).
  static bool pushSoundJustPlayed(String title, String body) {
    try {
      final atRaw = js.context['__cronosPushSoundAt'];
      final key = js.context['__cronosPushSoundKey']?.toString() ?? '';
      if (atRaw == null || key.isEmpty) return false;
      if (key != '$title|$body') return false;
      final at = atRaw is num
          ? atRaw.toInt()
          : int.tryParse(atRaw.toString()) ?? 0;
      return DateTime.now().millisecondsSinceEpoch - at < 8000;
    } catch (_) {
      return false;
    }
  }
}
