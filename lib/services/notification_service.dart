import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:just_audio/just_audio.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'windows_taskbar_icon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_browser_notifications.dart';
import 'web_notification_sound.dart';
import 'android_notification_icon.dart';
import 'background_notif_service.dart';
import '../utils/responsive.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _supa = Supabase.instance.client;

  RealtimeChannel? _channel;
  int? _listeningUserId;
  int? _lastSeenId;
  bool _audioLoaded = false;
  bool _subscribed = false;
  String? _windowsSoundFilePath;
  Future<void>? _soundPlayInFlight;

  AudioPlayer? _player;
  final Map<String, DateTime> _recent = {};
  final Duration _dedupWindow = const Duration(seconds: 4);
  static final Map<String, DateTime> _recentExternal = {};
  final Set<int> _recoveredBannerIds = {};

  // Polling: fallback se Realtime non consegna in tempo
  Timer? _pollTimer;
  static const Duration _pollIntervalWindows = Duration(seconds: 5);
  static const Duration _pollIntervalDefault = Duration(seconds: 8);
  /// Mobile web: tab spesso sospese → poll più aggressivo a foreground.
  static const Duration _pollIntervalMobileWeb = Duration(seconds: 3);

  Future<void>? _startInFlight;
  Timer? _taskbarNotifyTimer;
  bool _taskbarNotifyActive = false;
  int _zeroUnreadStreak = 0;

  // Notifiche locali Android (banner di sistema)
  final FlutterLocalNotificationsPlugin _androidLocal =
      FlutterLocalNotificationsPlugin();
  bool _androidLocalInited = false;

  static const String _androidAlertChannelId = 'cronos_alerts_v2';
  static const String _androidAlertChannelName = 'Notifiche Cronos';
  static const String _androidLegacyChannelId = 'cronos_high_importance';

  static String _deliveredIdPrefsKey(int userId) => 'notif_delivered_id_$userId';

  Future<void> startListening(int userId, dynamic _) async {
    if (_subscribed && _listeningUserId == userId) return;
    if (_startInFlight != null) {
      await _startInFlight;
      if (_subscribed && _listeningUserId == userId) return;
    }

    _startInFlight = _startListeningImpl(userId);
    try {
      await _startInFlight;
    } finally {
      _startInFlight = null;
    }
  }

  Future<void> _startListeningImpl(int userId) async {
    debugPrint(">>> START LISTEN for $userId");

    await stop();

    _listeningUserId = userId;

    if (kIsWeb) {
      WebNotificationSound.prepare();
    }

    await _loadDeliveryCursor(userId);
    if (kIsWeb) {
      await WebBrowserNotifications.requestPermissionIfNeeded();
    }

    final ch = _supa.channel('notifications_user_$userId');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final row = Map<String, dynamic>.from(payload.newRecord);
        debugPrint(">>> RAW NOTIFICA (realtime): id=${row['id']} user_id=${row['user_id']}");
        unawaited(_handleIncomingNotificationRow(row, source: 'realtime'));
      },
    );

    ch.subscribe();

    _channel = ch;
    _subscribed = true;

    debugPrint(">>> LISTENER ATTIVO per $userId (cursore=${_lastSeenId ?? 0})");

    _pollTimer?.cancel();
    final pollEvery = kIsWeb
        ? (isMobileWebPlatform()
            ? _pollIntervalMobileWeb
            : _pollIntervalDefault)
        : (Platform.isWindows ? _pollIntervalWindows : _pollIntervalDefault);
    if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isWindows))) {
      _pollTimer = Timer.periodic(pollEvery, (_) {
        unawaited(_pollForNewNotifications());
      });
    }
    if (!kIsWeb && Platform.isWindows) {
      _taskbarNotifyTimer?.cancel();
      await _refreshTaskbarNotifyIcon();
      _taskbarNotifyTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshTaskbarNotifyIcon(),
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final session = _supa.auth.currentSession;
        await BackgroundNotifService.persistAuthSession(
          userId: userId,
          accessToken: session?.accessToken ?? '',
          refreshToken: session?.refreshToken,
          lastSeenId: _lastSeenId,
        );
      } catch (_) {}
    }

    await pollNow(triggerBackground: true, catchUpMissed: true);
  }

  /// Cursore «consegnata» (banner mostrato), non «letta» in app.
  Future<void> _loadDeliveryCursor(int userId) async {
    int? dbMaxId;
    try {
      final last = await _supa
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .order('id', ascending: false)
          .limit(1);
      if (last.isNotEmpty) {
        dbMaxId = (last.first['id'] as num?)?.toInt();
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final perUser = prefs.getInt(_deliveredIdPrefsKey(userId));
      int? bgCursor;
      if (!kIsWeb && Platform.isAndroid) {
        if (prefs.containsKey(BackgroundNotifService.prefsLastSeenIdKey)) {
          bgCursor = prefs.getInt(BackgroundNotifService.prefsLastSeenIdKey);
        }
      }

      if (perUser != null) {
        _lastSeenId = perUser;
      } else if (bgCursor != null) {
        _lastSeenId = bgCursor;
      } else if (dbMaxId != null) {
        // Come backup legacy: al login non riproporre tutto lo storico.
        _lastSeenId = dbMaxId;
      } else {
        _lastSeenId = 0;
      }
    } catch (_) {
      _lastSeenId = dbMaxId ?? 0;
    }
  }

  Future<void> _reloadDeliveryCursorFromPrefs(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = <String>[
        _deliveredIdPrefsKey(userId),
        if (!kIsWeb && Platform.isAndroid)
          BackgroundNotifService.prefsLastSeenIdKey,
      ];
      for (final key in keys) {
        final v = prefs.getInt(key);
        if (v != null && (_lastSeenId == null || v > _lastSeenId!)) {
          _lastSeenId = v;
        }
      }
    } catch (_) {}
  }

  /// Ex catch-up toast: riproponeva fino a 5 non lette a ogni riapertura
  /// (stesso messaggio × N). A tab/app chiusa ci pensa Web Push;
  /// a app aperta ci pensano realtime+poll sulle sole id > cursore.
  Future<void> _catchUpMissedUnreadBanners(int userId) async {
    // no-op (voluto): non ripetere banner OS già consegnati.
  }

  /// Controllo immediato (es. riapertura app) per banner persi in background.
  Future<void> pollNow({
    bool triggerBackground = false,
    bool catchUpMissed = false,
  }) async {
    final uid = _listeningUserId;
    if (uid != null && catchUpMissed) {
      await _catchUpMissedUnreadBanners(uid);
    }
    await _pollForNewNotifications();
    if (triggerBackground) {
      await BackgroundNotifService.triggerPoll();
    }
  }

  /// Mobile web: al ritorno in foreground riparte realtime + poll aggressivo.
  Future<void> wakeListeningOnForeground() async {
    final uid = _listeningUserId;
    if (uid == null) return;
    if (!_subscribed) {
      await startListening(uid, null);
    } else {
      // Riattacca il timer (può essere stato congelato dal browser).
      _pollTimer?.cancel();
      final pollEvery = kIsWeb && isMobileWebPlatform()
          ? _pollIntervalMobileWeb
          : (kIsWeb
              ? _pollIntervalDefault
              : (Platform.isWindows
                  ? _pollIntervalWindows
                  : _pollIntervalDefault));
      if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isWindows))) {
        _pollTimer = Timer.periodic(pollEvery, (_) {
          unawaited(_pollForNewNotifications());
        });
      }
    }
    await pollNow(catchUpMissed: true);
  }

  Future<void> _persistDeliveryCursor(int userId) async {
    final id = _lastSeenId;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_deliveredIdPrefsKey(userId), id);
      if (!kIsWeb && Platform.isAndroid) {
        await BackgroundNotifService.syncCursor(
          userId: userId,
          lastSeenId: id,
        );
      }
    } catch (_) {}
  }

  Future<void> stop({bool clearTaskbarIndicator = false}) async {
    try {
      if (_channel != null) {
        await _supa.removeChannel(_channel!);
      }
    } catch (_) {}
    _channel = null;
    _subscribed = false;
    _recoveredBannerIds.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    _taskbarNotifyTimer?.cancel();
    _taskbarNotifyTimer = null;
    if (clearTaskbarIndicator && !kIsWeb && Platform.isWindows) {
      _zeroUnreadStreak = 0;
      await _setTaskbarNotifyIcon(false);
    }
  }

  Future<AudioPlayer> _ensurePlayer() async {
    return _player ??= AudioPlayer();
  }

  /// Su Windows [just_audio] va invocato dal main isolate (post-frame).
  Future<T> _runAudioOnPlatformThread<T>(Future<T> Function() action) async {
    if (kIsWeb || !Platform.isWindows) {
      return action();
    }
    final completer = Completer<T>();
    void run() {
      action().then(completer.complete).catchError(
        (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
      );
    }

    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      binding.addPostFrameCallback((_) => run());
    } else {
      run();
    }
    return completer.future;
  }

  Future<void> _preloadNotificationSound() async {
    if (_audioLoaded) return;
    final player = await _ensurePlayer();
    if (!kIsWeb && Platform.isWindows) {
      final bytes = await rootBundle.load('assets/notification.mp3');
      final payload = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final dir = await getTemporaryDirectory();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final candidates = [
        p.join(dir.path, 'cronos_notification_$suffix.mp3'),
        p.join(dir.path, 'cronos_notification_${suffix + 1}.mp3'),
      ];
      Object? lastError;
      for (final path in candidates) {
        try {
          final file = File(path);
          await file.writeAsBytes(payload, flush: true);
          _windowsSoundFilePath = file.path;
          await player.setFilePath(_windowsSoundFilePath!);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (lastError != null) throw lastError;
    } else {
      await player.setAsset('assets/notification.mp3');
    }
    await player.setVolume(1.0);
    _audioLoaded = true;
  }

  Future<void> _playSound() async {
    if (kIsWeb) {
      await WebNotificationSound.play();
      return;
    }
    if (_soundPlayInFlight != null) {
      await _soundPlayInFlight;
    }
    _soundPlayInFlight = _runAudioOnPlatformThread(_playSoundImpl);
    try {
      await _soundPlayInFlight;
    } finally {
      _soundPlayInFlight = null;
    }
  }

  Future<void> _playSoundImpl() async {
    final player = await _ensurePlayer();
    try {
      if (!_audioLoaded) {
        await _preloadNotificationSound();
      }
      await player.setVolume(1.0);
      if (player.playing) {
        await player.stop();
      }
      await player.seek(Duration.zero);
      await player.play();
      debugPrint(">>> SUONO RIPRODOTTO (notification.mp3)");
    } catch (e) {
      debugPrint(">>> AUDIO ERROR: $e — retry da file");
      try {
        _audioLoaded = false;
        await _preloadNotificationSound();
        await player.setVolume(1.0);
        await player.seek(Duration.zero);
        await player.play();
        debugPrint(">>> SUONO RIPRODOTTO (retry)");
      } catch (e2) {
        debugPrint(">>> AUDIO ERROR retry: $e2");
      }
    }
  }

  Map<String, dynamic> _metaMapFromRow(Map<String, dynamic> row) {
    final raw = row['meta'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }

  bool _isTechnicalNoiseRow(Map<String, dynamic> row) {
    try {
      final m = _metaMapFromRow(row);
      final creator = (m['creator'] ?? m['by_name'] ?? '').toString();
      final type = (m['type'] ?? m['tipo'] ?? '').toString();
      final date = (m['date'] ?? m['data'] ?? '').toString();
      final msg = (row['message'] ?? '').toString().toLowerCase();
      return creator == 'N/D' &&
          type == 'N/D' &&
          date == 'N/D' &&
          msg.contains('inserita.');
    } catch (_) {
      return false;
    }
  }

  bool _isAppChatNotificationRow(Map<String, dynamic> row) {
    final title = (row['title'] ?? '').toString().trim();
    if (title.startsWith('GESTOPRO Chat')) return true;
    try {
      final m = _metaMapFromRow(row);
      final type = (m['type'] ?? '').toString().trim().toLowerCase();
      if (type == 'app_chat') return true;
      final action = (m['action'] ?? '').toString().trim().toLowerCase();
      return action == 'app_chat_dm' || action == 'app_chat_group';
    } catch (_) {
      return false;
    }
  }

  /// Evita solo doppia consegna (Realtime + poll) sulla stessa riga.
  String _dedupKeyFromRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    if (id.isNotEmpty) return 'id:$id';
    return '${row['title'] ?? ''}|${row['message'] ?? ''}';
  }

  Future<void> _commitSeenId(int id, int listening) async {
    if (_lastSeenId != null && id <= _lastSeenId!) return;
    _lastSeenId = id;
    await _persistDeliveryCursor(listening);
  }

  Future<void> _handleIncomingNotificationRow(
    Map<String, dynamic> row, {
    required String source,
  }) async {
    final listening = _listeningUserId;
    final idRaw = row['id'];
    final int? id = idRaw is int ? idRaw : int.tryParse(idRaw.toString());

    if (_isTechnicalNoiseRow(row)) {
      debugPrint('>>> SCARTATA ($source): notifica tecnica');
      if (listening != null && id != null) {
        await _commitSeenId(id, listening);
      }
      return;
    }
    if (_isAppChatNotificationRow(row)) {
      debugPrint('>>> SCARTATA ($source): notifica chat (solo FAB/push)');
      if (listening != null && id != null) {
        await _commitSeenId(id, listening);
      }
      return;
    }
    final rowUserId = int.tryParse(row['user_id']?.toString() ?? '');
    if (listening == null || rowUserId == null || rowUserId != listening) {
      debugPrint(
        '>>> SCARTATA ($source): user_id=${row['user_id']} != $listening',
      );
      return;
    }

    if (id == null) return;

    final isNew = _lastSeenId == null || id > _lastSeenId!;
    if (!isNew) return;

    final key = _dedupKeyFromRow(row);
    final now = DateTime.now();
    _recent.removeWhere((_, t) => now.difference(t) > _dedupWindow);
    if (_recent.containsKey(key)) {
      debugPrint('>>> SCARTATA ($source): già in elaborazione $key');
      return;
    }
    _recent[key] = now;
    _rememberExternalKey(key);
    if (!kIsWeb && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_setTaskbarNotifyIcon(true, force: true));
      });
    }
    debugPrint('>>> NOTIFICA VALIDA ($source) id=$id');
    final shown = await _presentPopupAndSound(row);
    if (shown) {
      await _commitSeenId(id, listening);
    } else {
      debugPrint(
        '>>> NOTIFICA id=$id: banner/suono non mostrato, retry al prossimo poll',
      );
    }
  }

  Future<void> _refreshTaskbarNotifyIcon() async {
    final uid = _listeningUserId;
    if (uid == null || kIsWeb || !Platform.isWindows) return;
    try {
      // is_read null = non letto (come notification_bell / notifications_page).
      final rows = await _supa
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .or('is_read.is.null,is_read.eq.false')
          .limit(1);
      final hasUnread = (rows as List).isNotEmpty;
      if (hasUnread) {
        _zeroUnreadStreak = 0;
        // Windows puo` perdere l'overlay dopo hide/show della finestra:
        // forziamo il re-apply finche' ci sono non lette.
        await _setTaskbarNotifyIcon(true, force: true);
      } else {
        // Evita spegnimenti "a scatto" del badge per eventuali latenze/refresh transienti.
        _zeroUnreadStreak += 1;
        if (_zeroUnreadStreak >= 2) {
          await _setTaskbarNotifyIcon(false);
        }
      }
    } catch (e) {
      assert(() {
        debugPrint('>>> _refreshTaskbarNotifyIcon: $e');
        return true;
      }());
    }
  }

  /// Barra applicazioni: overlay/badge quando ci sono non lette.
  /// Evita il cambio completo dell'icona principale.
  Future<void> _setTaskbarNotifyIcon(bool active, {bool force = false}) async {
    if (!force && _taskbarNotifyActive == active) return;
    _taskbarNotifyActive = active;
    try {
      if (active) {
        await WindowsTaskbarIcon.setOverlayFromAssetPath(
          'assets/icon_tray_notify.ico',
          description: 'Cronos - Nuove notifiche',
        );
      } else {
        await WindowsTaskbarIcon.clearOverlay();
      }
    } catch (_) {}
    try {
      await trayManager.setToolTip(
        active
            ? 'Cronos — nuove notifiche'
            : 'Cronos — notifiche anche da app chiusa',
      );
    } catch (_) {}
  }

  /// Toast/banner di sistema; su Android il suono passa dal canale notifiche.
  Future<bool> _presentPopupAndSound(Map<String, dynamic> row) async {
    final title = (row['title'] ?? 'Notifica').toString();
    final body = (row['message'] ?? '').toString();
    final notifId = (row['id'] as num?)?.toInt();

    if (kIsWeb) {
      // OS banner a tab chiusa/background = Service Worker (Web Push).
      // A tab aperta (soprattutto mobile): banner browser + suono, altrimenti
      // l'utente non vede nulla (prima c'era solo il beep).
      if (shouldSuppressExternalNotification(title, body) ||
          WebBrowserNotifications.pushSoundJustPlayed(title, body)) {
        debugPrint('>>> WEB: skip suono/banner (già consegnato da push)');
        return true;
      }
      // Riapertura app: push già mostrata mentre era chiusa → solo cursore, no suono.
      final createdRaw = row['created_at']?.toString();
      final createdAt = createdRaw == null ? null : DateTime.tryParse(createdRaw);
      if (createdAt != null) {
        final age = DateTime.now().toUtc().difference(createdAt.toUtc());
        if (age > const Duration(seconds: 20)) {
          return true;
        }
      }
      if (WebBrowserNotifications.isDocumentVisible) {
        await WebNotificationSound.play();
        WebBrowserNotifications.markInAppSoundPlayed(title, body);
        _rememberExternalKey('$title|$body');
      }
      return true;
    }

    if (Platform.isWindows) {
      if (shouldSuppressExternalNotification(title, body)) {
        return true;
      }
      await _playSound();
      await _showWindowsToast(
        title,
        body,
        silent: true,
        stableId: notifId,
      );
      return true;
    }

    if (Platform.isAndroid) {
      // Banner sul canale alert (suono incluso nel canale). just_audio solo se il banner fallisce.
      final shown = await _showAndroidLocalNotification(title, body, row['id']);
      if (!shown) {
        debugPrint('>>> ANDROID: banner fallito, solo suono asset');
        await _playSound();
      }
      return shown;
    }

    unawaited(_playSound());
    return true;
  }

  Future<void> _showWindowsToast(
    String title,
    String body, {
    bool silent = false,
    int? stableId,
  }) async {
    try {
      final n = LocalNotification(
        identifier: stableId != null
            ? 'cronos-notif-$stableId'
            : DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        silent: silent,
      );
      n.onClick = () async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      };
      await n.show();
      debugPrint(
        silent
            ? '>>> POPUP Windows mostrato (suono da notification.mp3)'
            : '>>> POPUP Windows mostrato',
      );
    } catch (e) {
      debugPrint('>>> POPUP Windows ERROR: $e');
    }
  }

  // ----------------------------------------------------------
  // PULL: controllo periodico notifiche
  // ----------------------------------------------------------
  Future<void> _pollForNewNotifications() async {
    final uid = _listeningUserId;
    if (uid == null) return;

    try {
      await _reloadDeliveryCursorFromPrefs(uid);
      final fromId = (_lastSeenId ?? 0);
      final rows = await _supa
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .gt('id', fromId)
          .order('id', ascending: true)
          .limit(20);

      if (rows.isEmpty) return;

      debugPrint(
        '>>> POLL: ${rows.length} nuove (id>$fromId, user=$uid)',
      );

      for (final raw in rows) {
        await _handleIncomingNotificationRow(
          Map<String, dynamic>.from(raw as Map),
          source: 'poll',
        );
      }
    } catch (e) {
      debugPrint('>>> POLL ERROR: $e');
    }
  }

  static bool shouldSuppressExternalNotification(String title, String body) {
    final key = '$title|$body';
    final now = DateTime.now();
    _recentExternal.removeWhere((_, t) => now.difference(t) > const Duration(seconds: 6));
    if (_recentExternal.containsKey(key)) return true;
    _recentExternal[key] = now;
    return false;
  }

  void _rememberExternalKey(String key) {
    _recentExternal[key] = DateTime.now();
  }

  // ----------------------------------------------------------
  // NOTIFICA LOCALE ANDROID (banner di sistema)
  // ----------------------------------------------------------
  Future<bool> _showAndroidLocalNotification(
    String title,
    String body,
    Object? id,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    final safeTitle = title.trim().isEmpty ? 'Notifica Cronos' : title.trim();
    final safeBody = body.trim().isEmpty ? 'Nuovo messaggio' : body.trim();

    try {
      if (!_androidLocalInited) {
        await initializeAndroidLocalNotifications(_androidLocal);
        final androidImpl = _androidLocal
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
        await androidImpl?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidAlertChannelId,
            _androidAlertChannelName,
            description: 'Notifiche prenotazioni e aggiornamenti',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            sound: RawResourceAndroidNotificationSound('notification'),
          ),
        );
        await androidImpl?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidLegacyChannelId,
            _androidAlertChannelName,
            description: 'Notifiche prenotazioni e aggiornamenti',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        _androidLocalInited = true;
      }

      final notifId = (id is int && id > 0)
          ? id
          : DateTime.now().millisecondsSinceEpoch.remainder(100000);

      final style = BigTextStyleInformation(
        safeBody,
        contentTitle: safeTitle,
        summaryText: 'Cronos',
      );

      Future<void> showOnChannel(String channelId, {bool customSound = true}) {
        final details = AndroidNotificationDetails(
          channelId,
          _androidAlertChannelName,
          channelDescription: 'Notifiche prenotazioni e aggiornamenti',
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
        return _androidLocal.show(
          notifId,
          safeTitle,
          safeBody,
          NotificationDetails(android: details),
        );
      }

      try {
        await showOnChannel(_androidAlertChannelId);
        debugPrint('>>> ANDROID BANNER ok: $safeTitle');
        return true;
      } catch (e1) {
        debugPrint('>>> ANDROID BANNER v2 err: $e1');
        try {
          await showOnChannel(_androidLegacyChannelId, customSound: false);
          debugPrint('>>> ANDROID BANNER ok (legacy): $safeTitle');
          return true;
        } catch (e2) {
          debugPrint('>>> ANDROID BANNER legacy err: $e2');
          return false;
        }
      }
    } catch (e) {
      debugPrint('>>> ANDROID LOCAL NOTIFICATION ERROR: $e');
      return false;
    }
  }
}