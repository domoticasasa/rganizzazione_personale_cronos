import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:timezone/timezone.dart' as tz;

import '../utils/date_formatters.dart';
import 'personal_agenda_service.dart';

/// Schedula/cancella avvisi locali per voci agenda.
class AgendaReminderScheduler {
  AgendaReminderScheduler._();
  static final AgendaReminderScheduler instance = AgendaReminderScheduler._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;
  final Map<String, Timer> _timers = {};

  Future<void> ensureReady() async {
    if (_pluginReady || kIsWeb) return;
    ensureItalyTimezoneInitialized();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      _pluginReady = true;
    }
  }

  int _notifIdFor(String entryId) {
    var h = 0;
    for (final c in entryId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 700000 + (h % 200000);
  }

  Future<void> scheduleFor(AgendaEntry entry) async {
    await cancelFor(entry.id);
    if (!entry.reminderEnabled || entry.startsAt == null) return;
    final minutes = entry.reminderMinutesBefore ?? 15;
    final when = entry.startsAt!.subtract(Duration(minutes: minutes));
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) return;

    final title = 'Agenda: ${entry.title}';
    final body = minutes == 0
        ? 'Inizia ora'
        : agendaReminderPresetLabel(minutes);

    // Timer in-app (web/Windows/desktop): sync solo con app aperta (limite v1).
    _timers[entry.id] = Timer(delay, () {
      _timers.remove(entry.id);
      unawaited(_fire(entry.id, title, body));
    });

    // Android/iOS: anche zonedSchedule per sopravvivenza breve in background.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await ensureReady();
        ensureItalyTimezoneInitialized();
        final loc = tz.getLocation(kAppTimezone);
        final scheduled = tz.TZDateTime.from(when, loc);
        await _plugin.zonedSchedule(
          _notifIdFor(entry.id),
          title,
          body,
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'agenda_reminders',
              'Avvisi agenda',
              channelDescription: 'Promemoria eventi agenda personale',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('AgendaReminderScheduler.zonedSchedule: $e');
        }
      }
    }
  }

  Future<void> cancelFor(String entryId) async {
    _timers.remove(entryId)?.cancel();
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await ensureReady();
        await _plugin.cancel(_notifIdFor(entryId));
      } catch (_) {}
    }
  }

  Future<void> _fire(String entryId, String title, String body) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final n = LocalNotification(
          identifier: 'agenda-reminder-$entryId',
          title: title,
          body: body,
        );
        await n.show();
        return;
      }
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await ensureReady();
        await _plugin.show(
          _notifIdFor(entryId),
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'agenda_reminders',
              'Avvisi agenda',
              channelDescription: 'Promemoria eventi agenda personale',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
        return;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('Agenda reminder due: $title — $body');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AgendaReminderScheduler._fire: $e');
      }
    }
  }
}
