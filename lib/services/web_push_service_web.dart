// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class WebPushService {
  WebPushService._();

  static const String _vapidPublicKey =
      String.fromEnvironment('WEB_PUSH_VAPID_PUBLIC_KEY', defaultValue: '');
  static bool _inProgress = false;
  static final List<void Function()> _permissionListeners = <void Function()>[];
  static html.EventListener? _permissionWindowListener;

  static void addPermissionChangeListener(void Function() listener) {
    if (!kIsWeb) return;
    if (!_permissionListeners.contains(listener)) {
      _permissionListeners.add(listener);
    }
    _permissionWindowListener ??= (_) {
      for (final cb in List<void Function()>.from(_permissionListeners)) {
        cb();
      }
    };
    html.window.removeEventListener(
      'cronos-notification-permission',
      _permissionWindowListener!,
    );
    html.window.addEventListener(
      'cronos-notification-permission',
      _permissionWindowListener!,
    );
  }

  static void removePermissionChangeListener(void Function() listener) {
    if (!kIsWeb) return;
    _permissionListeners.remove(listener);
    if (_permissionListeners.isEmpty && _permissionWindowListener != null) {
      html.window.removeEventListener(
        'cronos-notification-permission',
        _permissionWindowListener!,
      );
      _permissionWindowListener = null;
    }
  }

  static String get notificationPermission {
    if (!kIsWeb) return 'unsupported';
    try {
      final cronosPwa = js.context['cronosPwa'];
      if (cronosPwa != null) {
        final dynamic getter = (cronosPwa as dynamic).getNotificationPermission;
        if (getter != null) {
          final value = getter().toString().trim();
          if (value.isNotEmpty && value != 'unsupported') return value;
        }
      }
    } catch (_) {}
    try {
      if (html.Notification.supported) {
        return html.Notification.permission ?? 'default';
      }
    } catch (_) {}
    return 'unsupported';
  }

  static bool get isBrowserNotificationGranted =>
      notificationPermission == 'granted';

  /// Subscription salvata su questo browser (serve per push a tab chiusa).
  static bool get isPushRegisteredOnThisDevice {
    if (!kIsWeb) return false;
    try {
      final cronosPwa = js.context['cronosPwa'];
      if (cronosPwa == null) return false;
      final dynamic fn = (cronosPwa as dynamic).isPushRegistered;
      if (fn == null) return false;
      return fn() == true;
    } catch (_) {
      return false;
    }
  }

  static bool get isIosSafariTabWithoutHomeScreen {
    if (!kIsWeb) return false;
    try {
      final cronosPwa = js.context['cronosPwa'];
      if (cronosPwa == null) return false;
      final dynamic isIos = (cronosPwa as dynamic).isIos;
      final dynamic isStandalone = (cronosPwa as dynamic).isInStandaloneMode;
      if (isIos == null || isStandalone == null) return false;
      return isIos() == true && isStandalone() != true;
    } catch (_) {
      return false;
    }
  }

  /// Richiede permesso notifiche (deve partire da un tap utente su Web).
  static Future<bool> requestBrowserPermissionFromUser() async {
    if (!kIsWeb) return false;
    // Bootstrap JWT/VAPID prima del prompt (senza aspettarsi già permission granted).
    await ensureRegisteredForCurrentUser();
    dynamic cronosPwa = js.context['cronosPwa'];
    if (cronosPwa == null) {
      for (var i = 0; i < 8 && cronosPwa == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        cronosPwa = js.context['cronosPwa'];
      }
    }
    if (cronosPwa == null) return false;
    try {
      await (cronosPwa as dynamic).askNotificationPermission();
    } catch (_) {
      // askNotificationPermission gestisce già alert lato JS.
    }
    for (var i = 0; i < 12; i++) {
      if (isBrowserNotificationGranted) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!isBrowserNotificationGranted) return false;
    // Dopo il tap utente, forza la registrazione sul server.
    return ensureRegisteredForCurrentUser(force: true);
  }

  static Future<bool> ensureRegisteredForCurrentUser({bool force = false}) async {
    if (!kIsWeb) return false;
    if (_inProgress) {
      for (var i = 0; i < 25 && _inProgress; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (_inProgress) return false;
    }
    _inProgress = true;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return false;
      dynamic cronosPwa = js.context['cronosPwa'];
      if (cronosPwa == null) {
        // On web startup, flutter app can initialize before pwa_helper.js is ready.
        for (var i = 0; i < 8 && cronosPwa == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          cronosPwa = js.context['cronosPwa'];
        }
      }
      if (cronosPwa == null) return false;
      final keyFromWindow = js.context['CRONOS_VAPID_PUBLIC_KEY']?.toString() ?? '';
      final vapidPublicKey =
          _vapidPublicKey.isNotEmpty ? _vapidPublicKey : keyFromWindow;
      if (vapidPublicKey.isEmpty) return false;

      final functionUrl = '${SupabaseService.supabaseUrl}/functions/v1/web-push-subscribe';
      js.context['cronosPushBootstrap'] = js.JsObject.jsify({
        'functionUrl': functionUrl,
        'accessToken': session.accessToken,
        'vapidPublicKey': vapidPublicKey,
        'authUserId': session.user.id,
        'refreshToken': session.refreshToken ?? '',
        'supabaseUrl': SupabaseService.supabaseUrl,
        'anonKey': SupabaseService.anonKey,
      });
      try {
        await (cronosPwa as dynamic).persistNotificationSession();
      } catch (_) {}
      try {
        await (cronosPwa as dynamic).resyncWebPushIfPossible();
      } catch (_) {}
      Future<bool> tryRegister({bool forceRefresh = false}) async {
        try {
          final result = await (cronosPwa as dynamic).registerWebPushWithSupabase(
            functionUrl,
            session.accessToken,
            vapidPublicKey,
            forceRefresh,
            session.user.id,
          );
          return result == true;
        } catch (_) {
          return false;
        }
      }

      var ok = await tryRegister(forceRefresh: force);
      if (!ok) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        ok = await tryRegister(forceRefresh: false);
      }
      if (!ok && kDebugMode) {
        final perm = (cronosPwa as dynamic).getNotificationPermission?.call();
        // ignore: avoid_print
        print('>>> Web Push: registrazione non completata (permission=$perm). '
            'Su Web usa «Abilita notifiche browser» in basso a destra.');
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _inProgress = false;
    }
  }

  /// Copia JWT/VAPID in IndexedDB per il Service Worker (app chiusa / Passkey).
  static Future<void> persistNotificationSession() async {
    if (!kIsWeb) return;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final keyFromWindow = js.context['CRONOS_VAPID_PUBLIC_KEY']?.toString() ?? '';
        final vapidPublicKey =
            _vapidPublicKey.isNotEmpty ? _vapidPublicKey : keyFromWindow;
        if (vapidPublicKey.isNotEmpty) {
          js.context['cronosPushBootstrap'] = js.JsObject.jsify({
            'functionUrl':
                '${SupabaseService.supabaseUrl}/functions/v1/web-push-subscribe',
            'accessToken': session.accessToken,
            'vapidPublicKey': vapidPublicKey,
            'authUserId': session.user.id,
            'refreshToken': session.refreshToken ?? '',
            'supabaseUrl': SupabaseService.supabaseUrl,
            'anonKey': SupabaseService.anonKey,
          });
        }
      }
      final cronosPwa = js.context['cronosPwa'];
      if (cronosPwa == null) return;
      await (cronosPwa as dynamic).persistNotificationSession();
      try {
        (cronosPwa as dynamic).keepListeningAfterClose();
      } catch (_) {}
    } catch (_) {}
  }

  /// Logout: pulisce solo i flag locali (la subscription resta attiva su Supabase
  /// per ricevere push a tab/app chiusa).
  static Future<void> deactivateCurrentDeviceOnLogout() async {
    if (!kIsWeb) return;
    try {
      dynamic cronosPwa = js.context['cronosPwa'];
      if (cronosPwa == null) return;
      final boot = js.context['cronosPushBootstrap'];
      final functionUrl = boot == null ? '' : (boot['functionUrl']?.toString() ?? '');
      final accessToken = boot == null ? '' : (boot['accessToken']?.toString() ?? '');
      await (cronosPwa as dynamic).deactivateWebPushOnLogout(
        functionUrl,
        accessToken,
      );
    } catch (_) {
      // best-effort
    } finally {
      try {
        js.context['cronosPushBootstrap'] = null;
      } catch (_) {}
    }
  }
}
