import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'android_notification_icon.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
void backgroundNotifServiceEntryPoint(ServiceInstance service) {
  unawaited(BackgroundNotifService.onStart(service));
}

@pragma('vm:entry-point')
class BackgroundNotifService {
  BackgroundNotifService._();

  static const prefsUserIdKey = 'bg_notif_user_id';
  static const prefsLastSeenIdKey = 'bg_notif_last_seen_id';
  static const prefsRefreshTokenKey = 'bg_supabase_refresh_token';
  static const prefsAccessTokenKey = 'bg_supabase_access_token';
  /// true se l'utente vuole il servizio attivo (anche a app chiusa).
  static const prefsWantedKey = 'bg_notif_wanted';

  /// Canale alert (v2: suono custom; se v1 era muto, Android non aggiorna il canale).
  static const _channelId = 'cronos_alerts_v2';

  /// Canale legacy (backup APK): mantenuto per compatibilità.
  static const _legacyChannelId = 'cronos_high_importance';
  static const _legacyChannelName = 'Notifiche Cronos';

  /// Canale separato dalla barra persistente del foreground service.
  static const _foregroundChannelId = 'cronos_foreground_service';
  static const _foregroundChannelName = 'Cronos — servizio notifiche';
  static const _foregroundChannelDesc =
      'Notifica persistente: avvisi anche a app chiusa. '
      'Non disattivare questo canale se vuoi ricevere avvisi con l\'app chiusa.';

  static const _channelName = 'Notifiche Cronos';
  static const _channelDesc = 'Notifiche prenotazioni e aggiornamenti';

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final service = FlutterBackgroundService();
    final fln = FlutterLocalNotificationsPlugin();
    await _initNotifications(fln);

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: (_) {},
        onBackground: (_) async => true,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundNotifServiceEntryPoint,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _foregroundChannelId,
        initialNotificationTitle: 'Cronos — notifiche',
        initialNotificationContent:
            'Notifiche anche da app chiusa. Non disattivare questa notifica.',
        foregroundServiceNotificationId: 8888,
      ),
    );
  }

  /// Salva sessione Supabase per il processo background (Android).
  static Future<void> persistAuthSession({
    required int userId,
    required String accessToken,
    String? refreshToken,
    int? lastSeenId,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsUserIdKey, userId);
    if (accessToken.isNotEmpty) {
      await prefs.setString(prefsAccessTokenKey, accessToken);
    }
    final rt = (refreshToken ?? '').trim();
    if (rt.isNotEmpty) {
      await prefs.setString(prefsRefreshTokenKey, rt);
    }
    if (lastSeenId != null) {
      await prefs.setInt(prefsLastSeenIdKey, lastSeenId);
    }
  }

  /// Allinea cursore polling background con l'app in primo piano.
  static Future<void> syncCursor({
    required int userId,
    int? lastSeenId,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await persistAuthSession(
          userId: userId,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          lastSeenId: lastSeenId,
        );
        return;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsUserIdKey, userId);
    if (lastSeenId != null) {
      await prefs.setInt(prefsLastSeenIdKey, lastSeenId);
    }
  }

  static Future<void> startForUser(
    int userId, {
    bool requestPermissions = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await persistAuthSession(
          userId: userId,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(prefsUserIdKey, userId);
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefsUserIdKey, userId);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsWantedKey, true);

    if (requestPermissions) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      try {
        final batt = await Permission.ignoreBatteryOptimizations.status;
        if (!batt.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } catch (_) {}
    }

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    } else {
      service.invoke('setForeground');
      service.invoke('refresh');
    }
  }

  /// Riavvia / mantiene il FGS quando l'app va in background o viene chiusa.
  static Future<void> ensureListeningWhileClosed() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsWantedKey) != true) return;
    final uid = prefs.getInt(prefsUserIdKey);
    if (uid == null || uid <= 0) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await persistAuthSession(
          userId: uid,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        );
      }
    } catch (_) {}

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    } else {
      service.invoke('setForeground');
      service.invoke('refresh');
    }
  }

  static Future<void> triggerPoll() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('refresh');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsWantedKey, false);
    await prefs.remove(prefsUserIdKey);
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    final fln = FlutterLocalNotificationsPlugin();
    await _initNotifications(fln);

    try {
      await SupabaseService.initialize();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        if (kDebugMode) print('>>> BG NOTIF Supabase init: $e');
      }
    }

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Cronos — notifiche',
        content:
            'Notifiche anche da app chiusa. Non disattivare questa notifica.',
      );
    }

    Timer? t;

    Future<void> tick() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getInt(prefsUserIdKey);
        if (uid == null || uid <= 0) return;

        final lastSeen = prefs.getInt(prefsLastSeenIdKey) ?? 0;

        final client = Supabase.instance.client;
        final session = await _ensureBackgroundSession(client, prefs);
        final accessFromPrefs = prefs.getString(prefsAccessTokenKey);
        final bearer = (session?.accessToken ?? accessFromPrefs ?? '').trim();
        if (bearer.isEmpty) {
          if (kDebugMode) {
            // ignore: avoid_print
            if (kDebugMode) print('>>> BG NOTIF: nessun token, skip tick');
          }
          return;
        }

        List<Map<String, dynamic>> list;
        if (session != null) {
          try {
            final rows = await client
                .from('notifications')
                .select('id,title,message,meta,created_at')
                .eq('user_id', uid)
                .gt('id', lastSeen)
                .order('id', ascending: true)
                .limit(20);
            list = List<Map<String, dynamic>>.from(rows as List);
          } catch (e) {
            if (kDebugMode) {
              // ignore: avoid_print
              if (kDebugMode) print('>>> BG NOTIF Supabase query fallita, REST: $e');
            }
            list = await _fetchNotificationsViaRest(
              userId: uid,
              lastSeenId: lastSeen,
              accessToken: bearer,
            );
          }
        } else {
          list = await _fetchNotificationsViaRest(
            userId: uid,
            lastSeenId: lastSeen,
            accessToken: bearer,
          );
        }
        if (list.isEmpty) return;

        if (kDebugMode) {
          // ignore: avoid_print
          if (kDebugMode) print('>>> BG NOTIF: ${list.length} nuove (lastSeen=$lastSeen)');
        }

        int maxId = lastSeen;
        for (final row in list) {
          final id = (row['id'] as num?)?.toInt();
          if (id == null) continue;

          final title = (row['title'] ?? 'Notifica').toString();
          final body = (row['message'] ?? '').toString();
          final shown = await _show(fln, id, title, body);
          if (!shown) break;
          if (id > maxId) maxId = id;
        }

        if (maxId > lastSeen) {
          await prefs.setInt(prefsLastSeenIdKey, maxId);
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          if (kDebugMode) print('>>> BG NOTIF tick error: $e');
        }
      }
    }

    await tick();
    // Poll più frequente a app chiusa.
    t = Timer.periodic(const Duration(seconds: 15), (_) => tick());

    service.on('refresh').listen((_) async {
      await tick();
    });

    service.on('stop').listen((_) async {
      t?.cancel();
      t = null;
      await service.stopSelf();
    });

    if (service is AndroidServiceInstance) {
      // Resta sempre foreground: altrimenti Android può uccidere il processo
      // quando l'utente chiude l'app dalle recenti.
      await service.setAsForegroundService();
      service.on('setForeground').listen((_) {
        service.setAsForegroundService();
      });
      service.on('setBackground').listen((_) {
        // Ignora: vogliamo sempre la barra di ascolto attiva.
        service.setAsForegroundService();
      });
    }
  }

  /// Sessione valida nel processo background (isolate separato dall'app).
  static Future<Session?> _ensureBackgroundSession(
    SupabaseClient client,
    SharedPreferences prefs,
  ) async {
    var session = client.auth.currentSession;
    if (session != null && !session.isExpired) {
      final rt = session.refreshToken;
      if (rt != null && rt.isNotEmpty) {
        await prefs.setString(prefsRefreshTokenKey, rt);
      }
      return session;
    }

    final storedRt = prefs.getString(prefsRefreshTokenKey);
    if (storedRt != null && storedRt.isNotEmpty) {
      try {
        final refreshed = await client.auth.refreshSession(storedRt);
        session = refreshed.session;
        final newRt = session?.refreshToken;
        final newAt = session?.accessToken;
        if (newRt != null && newRt.isNotEmpty) {
          await prefs.setString(prefsRefreshTokenKey, newRt);
        }
        if (newAt != null && newAt.isNotEmpty) {
          await prefs.setString(prefsAccessTokenKey, newAt);
        }
        if (session != null) return session;
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          if (kDebugMode) print('>>> BG NOTIF refreshSession(stored): $e');
        }
      }
    }

    return null;
  }

  static Future<void> _initNotifications(
    FlutterLocalNotificationsPlugin fln,
  ) async {
    await initializeAndroidLocalNotifications(fln);
    final androidImpl = fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    const channelFg = AndroidNotificationChannel(
      _foregroundChannelId,
      _foregroundChannelName,
      description: _foregroundChannelDesc,
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    const legacyChannel = AndroidNotificationChannel(
      _legacyChannelId,
      _legacyChannelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await androidImpl?.createNotificationChannel(channelFg);
    await androidImpl?.createNotificationChannel(channel);
    await androidImpl?.createNotificationChannel(legacyChannel);
  }

  /// Fallback REST (come backup APK) con JWT utente — funziona anche se refresh fallisce.
  static Future<List<Map<String, dynamic>>> _fetchNotificationsViaRest({
    required int userId,
    required int lastSeenId,
    required String accessToken,
  }) async {
    final url = Uri.parse(
      '${SupabaseService.supabaseUrl}/rest/v1/notifications'
      '?select=id,title,message,meta,created_at'
      '&user_id=eq.$userId'
      '&id=gt.$lastSeenId'
      '&order=id.asc'
      '&limit=20',
    );

    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      req.headers.set('apikey', SupabaseService.anonKey);
      req.headers.set('Authorization', 'Bearer $accessToken');
      req.headers.set('Accept', 'application/json');

      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $raw');
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _show(
    FlutterLocalNotificationsPlugin fln,
    int id,
    String title,
    String body,
  ) async {
    final safeTitle = title.trim().isEmpty ? 'Notifica Cronos' : title.trim();
    final safeBody = body.trim().isEmpty ? 'Nuovo messaggio' : body.trim();
    final style = BigTextStyleInformation(
      safeBody,
      contentTitle: safeTitle,
      summaryText: 'Cronos',
    );

    AndroidNotificationDetails detailsFor(String channelId, {bool customSound = true}) {
      return AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        icon: androidNotificationIconName,
        sound: customSound
            ? const RawResourceAndroidNotificationSound('notification')
            : null,
        audioAttributesUsage: AudioAttributesUsage.notification,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        styleInformation: style,
        ticker: safeTitle,
        onlyAlertOnce: false,
        autoCancel: true,
      );
    }

    try {
      await fln.show(
        id,
        safeTitle,
        safeBody,
        NotificationDetails(android: detailsFor(_channelId)),
      );
      if (kDebugMode) {
        // ignore: avoid_print
        if (kDebugMode) print('>>> BG NOTIF banner: $safeTitle');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        if (kDebugMode) print('>>> BG NOTIF show v2 error: $e');
      }
      try {
        await fln.show(
          id,
          safeTitle,
          safeBody,
          NotificationDetails(android: detailsFor(_legacyChannelId, customSound: false)),
        );
        return true;
      } catch (e2) {
        if (kDebugMode) {
          // ignore: avoid_print
          if (kDebugMode) print('>>> BG NOTIF show legacy error: $e2');
        }
        return false;
      }
    }
  }
}
