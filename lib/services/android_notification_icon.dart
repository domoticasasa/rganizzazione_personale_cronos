import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Nome risorsa drawable per icone notifica Android (senza prefisso `@drawable/`).
///
/// [flutter_local_notifications] risolve solo risorse in `res/drawable*`.
const List<String> kAndroidNotificationIconCandidates = [
  'ic_stat_cronos',
  'ic_bg_service_small',
  'ic_launcher_foreground',
];

String _resolvedAndroidNotificationIcon = kAndroidNotificationIconCandidates.first;

/// Icona usata da [AndroidNotificationDetails.icon] e init plugin.
String get androidNotificationIconName => _resolvedAndroidNotificationIcon;

/// Inizializza [plugin] provando più drawable fino a uno valido.
Future<void> initializeAndroidLocalNotifications(
  FlutterLocalNotificationsPlugin plugin,
) async {
  Object? lastError;
  for (final name in kAndroidNotificationIconCandidates) {
    try {
      await plugin.initialize(
        InitializationSettings(
          android: AndroidInitializationSettings(name),
        ),
      );
      _resolvedAndroidNotificationIcon = name;
      if (kDebugMode && name != kAndroidNotificationIconCandidates.first) {
        // ignore: avoid_print
        print('>>> Android notif icon: uso fallback "$name"');
      }
      return;
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ??
      StateError('Nessuna icona notifica Android trovata tra: '
          '${kAndroidNotificationIconCandidates.join(', ')}');
}
