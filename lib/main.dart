import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

// Servizi
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'services/password_recovery_gate.dart';
import 'services/windows_webview2_bootstrap.dart';
import 'services/android_notification_icon.dart';
import 'services/background_notif_service.dart';
import 'services/device_token_service.dart';
import 'services/gestopro_mode_prefs.dart';
import 'services/app_branding_service.dart';
import 'services/app_theme_mode_service.dart';
import 'services/web_push_service.dart';
import 'theme/cronos_app_themes.dart';
import 'services/web_notification_sound.dart';
import 'services/app_open_tracker.dart';
import 'services/app_chat_service.dart';
import 'services/app_chat_overlay_controller.dart';
import 'services/assenza_rfp03_pdf_convert_browser.dart';
import 'services/classic_nav_session_cache.dart';
import 'services/classic_nav_sub_items_cache.dart';
import 'services/outlook_calendar_sync_service.dart';
import 'services/passkeys_web_bootstrap_stub.dart'
    if (dart.library.html) 'services/passkeys_web_bootstrap_web.dart';
import 'services/app_device_unlock_gate.dart';
import 'services/app_device_unlock_visibility.dart';
import 'services/auth_qr_pending.dart';
import 'widgets/app_chat/app_chat_overlay_host.dart';
import 'widgets/neon_orbit_border.dart';

// Pagine
import 'utils/app_navigator.dart';
import 'utils/app_chat_deep_link.dart';
import 'utils/buono_pasto_scan_deep_link.dart';
import 'utils/viaggio_mezzo_scan_deep_link.dart';
import 'utils/auth_callback_bootstrap_stub.dart'
    if (dart.library.html) 'utils/auth_callback_bootstrap_web.dart';
import 'utils/date_formatters.dart';
import 'utils/domain_migration_notice.dart';
import 'widgets/app_logo.dart';
import 'widgets/classic_sidebar_shell.dart';
import 'widgets/cronos_app_background.dart';
import 'pages/login_page.dart';
import 'pages/change_password_reset_page.dart';
import 'pages/gestopro_splash_page.dart';
import 'pages/home_page.dart';
import 'pages/outlook_oauth_callback_page.dart';
import 'pages/ristoratore_home_page.dart';
import 'pages/dipendente_prenotazione_page.dart';
import 'pages/caposquadra_prenotazione_page.dart';
import 'pages/security_incident_public_page.dart';
import 'utils/responsive.dart';
import 'widgets/cronos_small_screen_fit.dart';
import 'Mobile/employee_mobile_pages.dart';

Uri? _pendingOutlookOAuthUri;

bool get _isMobileNative =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

// === PUSH: Web = Web Push; Android APK = polling + notifiche locali; iOS fuori scope ===
String? _pushSetupAuthId;
StreamSubscription<AuthState>? _authSub;
Timer? _notifActivateDebounce;
String? _pendingNotifAuthId;
final GlobalKey<NavigatorState> _appNavKey = appNavigatorKey;

final _windowCloseListener = _CronosWindowCloseListener();
final _trayListener = _CronosTrayListener();

Future<void> _exitFromTray() async {
  _CronosWindowCloseListener.isExiting = true;
  await windowManager.setPreventClose(false);
  await trayManager.destroy();
  await windowManager.destroy();
}

Future<void> _ensurePushSetup(String authId) async {
  // Push indipendente dal Passkey: le toast a app chiusa non sono uno sblocco
  // privacy. La sheet biometrica nasconde il document, ma la subscription
  // va tenuta viva e ri-salvata su Supabase comunque.
  if (_isMobileNative) {
    if (_pushSetupAuthId == authId) return;
    await setupPushForCurrentUser(authId);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await DeviceTokenService.registerForCurrentUser();
    }
    _pushSetupAuthId = authId;
    return;
  }
  if (kIsWeb) {
    // Sync silenzioso a ogni login/refresh: se il permesso è già granted
    // registra da sola senza chiedere di premere «Registra push».
    await WebPushService.ensureRegisteredForCurrentUser(force: false);
    _pushSetupAuthId = authId;
    return;
  }
}

/// Evita più restart concorrenti del listener (auth + resume).
void _scheduleActivateNotifications(String authId) {
  _pendingNotifAuthId = authId;
  _notifActivateDebounce?.cancel();
  _notifActivateDebounce = Timer(const Duration(milliseconds: 400), () {
    final id = _pendingNotifAuthId;
    if (id == null) return;
    unawaited(_activateNotifications(id));
  });
}

Future<int?> _userIdForAuth(String authId) async {
  try {
    final row = await Supabase.instance.client
        .from('users')
        .select('id')
        .or('auth_id.eq.$authId,id_uuid.eq.$authId')
        .maybeSingle();
    return (row?['id'] as num?)?.toInt();
  } catch (_) {
    return null;
  }
}

/// Barra persistente Android anche durante Passkey (non deve aspettare lo sblocco).
Future<void> _startAndroidListeningBar(String authId) async {
  if (kIsWeb) return;
  if (!_isMobileNative || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final userId = await _userIdForAuth(authId);
  if (userId == null || userId <= 0) return;
  await BackgroundNotifService.startForUser(
    userId,
    requestPermissions: !AppDeviceUnlockGate.isUnlockInProgress,
  );
}

/// Avvia ascolto notifiche (Realtime + polling) su tutte le piattaforme;
/// su Android anche il foreground service per l'app chiusa.
Future<void> _activateNotifications(String authId) async {
  // Canale OS (Web Push) subito, anche se è aperta la sheet Passkey.
  await _ensurePushSetup(authId);
  await _startAndroidListeningBar(authId);
  if (AppDeviceUnlockGate.isUnlockInProgress) {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (Supabase.instance.client.auth.currentSession?.user.id == authId) {
        _scheduleActivateNotifications(authId);
      }
    });
    return;
  }
  unawaited(AppOpenTracker.touchCurrentUser());
  unawaited(AppChatService.instance.start());
  try {
    final userId = await _userIdForAuth(authId);
    if (userId == null || userId <= 0) return;
    if (_isMobileNative && defaultTargetPlatform == TargetPlatform.android) {
      await BackgroundNotifService.startForUser(userId);
    }
    await NotificationService().startListening(userId, null);
    if (kIsWeb) {
      unawaited(WebNotificationSound.unlock());
    }
  } catch (e) {
    debugPrint('>>> activateNotifications: $e');
  }
}

final _flutterLocalNotifications = FlutterLocalNotificationsPlugin();

class _CronosWindowCloseListener with WindowListener {
  // Serve per evitare di “nascondere” anche quando usciamo dal tray.
  static bool _isExiting = false;

  static set isExiting(bool value) => _isExiting = value;

  @override
  void onWindowClose() {
    if (_isExiting) return;
    // Intercettiamo la chiusura (X) e nascondiamo la finestra:
    // l'app continua a rimanere attiva in background.
    unawaited(windowManager.hide());
  }
}

class _CronosTrayListener with TrayListener {
  Future<void> _showWindowFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    // Click sinistro sull'icona tray: riapre la finestra.
    unawaited(_showWindowFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    // Click destro: apre il menu contestuale del tray.
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindowFromTray());
        break;
      case 'exit_app':
        unawaited(_exitFromTray());
        break;
    }
  }
}

Future<void> _initWindowCloseToTray() async {
  if (!_isWindows) return;

  await windowManager.ensureInitialized();
  windowManager.addListener(_windowCloseListener);
  await windowManager.setPreventClose(true);

  // Tray menu (per “Mostra” e “Esci”). Stato notifiche: stesse ICO in
  // NotificationService + canale nativo `taskbar_icon` in flutter_window.cpp
  // (WM_SETICON + SetClassLongPtr) perché window_manager.setIcon da solo spesso
  // non aggiorna l’icona sulla taskbar.
  await trayManager.setIcon('assets/icon_tray.ico');
  await trayManager.setToolTip('Cronos — notifiche anche da app chiusa');
  final menu = Menu(
    items: [
      MenuItem(key: 'show_window', label: 'Mostra'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: 'Esci'),
    ],
  );
  await trayManager.setContextMenu(menu);
  trayManager.addListener(_trayListener);
}

/// Android/iOS: canale notifiche locali + permesso.
Future<void> setupPushForCurrentUser(String authId) async {
  if (!_isMobileNative) return;

  await initializeAndroidLocalNotifications(_flutterLocalNotifications);
  const channel = AndroidNotificationChannel(
    'cronos_alerts_v2',
    'Notifiche Cronos',
    description: 'Notifiche prenotazioni e aggiornamenti',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('notification'),
  );
  await _flutterLocalNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  if (defaultTargetPlatform == TargetPlatform.android) {
    await Permission.notification.request();
  }
}

// === MAIN ===
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: registra PasskeysWeb (il registrant build a volte lo omette → UnimplementedError).
  ensurePasskeysWebRegistered();

  // Su web evita fetch runtime verso fonts.gstatic.com (spesso bloccati in rete aziendale).
  // L'UI usa CronosFonts (Arial) al posto di GoogleFonts quando il fetch è disabilitato.
  if (kIsWeb) {
    GoogleFonts.config.allowRuntimeFetching = false;
    configureAppUrlStrategy();
  }

  // Web legacy host (pernotti/gestopro.pages.dev) → gestopro360.it
  DomainMigrationNotice.redirectLegacyHostIfNeeded();


  // Windows: se chiudi la finestra con la X, l'app resta attiva in background
  // (viene nascosta e gestita dal system tray).
  await _initWindowCloseToTray();

  // local_notifier su Windows richiede una setup esplicita, altrimenti i toast
  // possono non comparire anche se chiamiamo LocalNotification.show().
  if (_isWindows) {
    await localNotifier.setup(
      appName: 'Cronos Gestopro',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  // Nasconde subito il FAB chat: lo splash lo tiene bloccato fino al login.
  AppChatOverlayController.splashBlocking.value = true;

  // Supabase + background service dopo il primo frame: così il raster non resta
  // a lungo senza paint (evita “Skipped N frames” / sensazione di freeze all’avvio).
  runApp(const _AppBootstrap());
}

/// Shell che mostra subito un frame leggero, poi completa init rete/servizi.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapAfterFirstFrame());
    });
  }

  Future<void> _bootstrapAfterFirstFrame() async {
    try {
      ensureItalyTimezoneInitialized();

      if (_isWindows) {
        await bootstrapWindowsWebView2();
      }

      if (_isMobileNative && defaultTargetPlatform == TargetPlatform.android) {
        await Permission.notification.request();
      }

      // Snapshot URL prima di initialize: su web l'SDK consuma ?code= / hash
      // recovery e può emettere passwordRecovery prima che i nostri listener
      // esistano (poi LoginPage farebbe auto-login saltando il reset).
      // Ripristina l'hash salvato in index.html (Flutter lo sovrascrive con #/login).
      restoreSupabaseAuthCallbackFromStorage();
      PasswordRecoveryGate.captureFromBoot(
        uri: Uri.base,
        storedTokenHash: readStoredRecoveryTokenHash(),
      );
      final bootUri = Uri.base;
      final isOutlookOAuthCallback = kIsWeb &&
          bootUri.path.contains('/auth/outlook/callback') &&
          (bootUri.queryParameters.containsKey('code') ||
              bootUri.queryParameters.containsKey('error'));
      final hadStoredRecovery =
          kIsWeb && storedAuthCallbackLooksLikeRecovery();
      final hadAuthCallback = kIsWeb &&
          !isOutlookOAuthCallback &&
          (PasswordRecoveryGate.uriLooksLikeAuthCallback(bootUri) ||
              hadStoredRecovery);
      AppChatDeepLink.captureFromBootUri(bootUri);
      ViaggioMezzoScanDeepLink.captureFromBootUri(bootUri);
      BuonoPastoScanDeepLink.captureFromBootUri(bootUri);
      if (isOutlookOAuthCallback) {
        _pendingOutlookOAuthUri = bootUri;
      }

      await SupabaseService.initialize();
      await AppBrandingService.instance.load();
      await AppThemeModeService.instance.load();
      final bootQr = AuthQrPending.codeFromUrl(bootUri);
      if (bootQr != null) await AuthQrPending.remember(bootQr);
      // Non chiamare verifyOTP qui: il token è one-shot. Lo scanner della
      // mail o un secondo mount brucerebbe il link prima di «Salva».
      final hasSession =
          Supabase.instance.client.auth.currentSession != null;
      PasswordRecoveryGate.captureAfterInitialize(
        hadAuthCallbackUri: hadAuthCallback,
        hasSession: hasSession,
      );
      if (kIsWeb) {
        preloadRfp03PdfEngine();
      }
      try {
        await BackgroundNotifService.init();
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('>>> BackgroundNotifService.init: $e');
        }
      }

      _authSub?.cancel();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.passwordRecovery) {
          if (PasswordRecoveryGate.shouldOpenResetPage) {
            PasswordRecoveryGate.markPending();
          }
          return;
        }
        if (event == AuthChangeEvent.signedOut) {
          _pushSetupAuthId = null;
          AppOpenTracker.stopForegroundHeartbeat();
          // Solo logout esplicito: non usare `session == null` (sparisce anche
          // in fase di restore/refresh e cancellava i flag push a ogni apertura).
          ClassicNavSessionCache.clear();
          ClassicNavSubItemsCache.clear();
          unawaited(WebPushService.deactivateCurrentDeviceOnLogout());
          unawaited(DeviceTokenService.clearForCurrentUser());
          unawaited(GestoproModePrefs.deactivate());
          unawaited(NotificationService().stop());
          // Non fermare il FGS: Passkey annullata / sessione chiusa non deve
          // togliere la barra «Cronos — in ascolto» né il canale OS.
          AppChatOverlayController.close();
          unawaited(AppChatService.instance.stop());
          OutlookCalendarSyncService.instance.stopAutoSync();
          return;
        }
        if (session == null) return;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession ||
            event == AuthChangeEvent.tokenRefreshed) {
          if (PasswordRecoveryGate.isPending) return;
          AppOpenTracker.startForegroundHeartbeat();
          unawaited(AppBrandingService.instance.load());
          _scheduleActivateNotifications(session.user.id);
          unawaited(OutlookCalendarSyncService.instance.init());
        }
      });

      final s0 = Supabase.instance.client.auth.currentSession;
      if (s0 != null && !PasswordRecoveryGate.isPending) {
        _scheduleActivateNotifications(s0.user.id);
        unawaited(OutlookCalendarSyncService.instance.init());
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Errore avvio: $_error', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: kIsWeb ? 'Arial' : null,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        // Path URL strategy: l'utente può atterrare su /login#access_token=…
        // Questo MaterialApp non ha quella rotta — onGenerateRoute evita l'errore.
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (context) => const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLogo(size: 72),
                  SizedBox(height: 24),
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Avvio in corso…',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const CronosApp();
  }
}

// === APP ROOT ===
class CronosApp extends StatefulWidget {
  const CronosApp({super.key});

  @override
  State<CronosApp> createState() => _CronosAppState();
}

class _CronosAppState extends State<CronosApp> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    attachAppDeviceUnlockVisibilityListener(
      onHidden: () {
        // Impronta di sistema o fotocamera/galleria: il document va hidden
        // ma CRONOS resta in memoria — non invalidare lo sblocco.
        if (AppDeviceUnlockGate.shouldIgnoreBackgroundLock) return;
        _pausedAt = DateTime.now();
      },
      onVisible: () {
        unawaited(_onWebDocumentVisible());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Supabase.instance.client.auth.currentSession == null) return;
      AppOpenTracker.startForegroundHeartbeat();
      final ctx = _appNavKey.currentContext;
      unawaited(AuthQrPending.tryApproveForCurrentSession(ctx));
    });
  }

  @override
  void dispose() {
    AppOpenTracker.stopForegroundHeartbeat();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppOpenTracker.startForegroundHeartbeat();
      unawaited(NotificationService().pollNow(triggerBackground: true, catchUpMissed: true));
      final authId = Supabase.instance.client.auth.currentSession?.user.id;
      if (authId != null) {
        _scheduleActivateNotifications(authId);
      }
      unawaited(AppOpenTracker.touchCurrentUser(force: true));
      unawaited(_maybeRelockOnResume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      AppOpenTracker.stopForegroundHeartbeat();
      if (!AppDeviceUnlockGate.shouldIgnoreBackgroundLock) {
        _pausedAt = DateTime.now();
      }
      unawaited(_persistSessionForBackground());
      // Mantieni la barra «in ascolto» anche chiudendo/swipando l'app.
      unawaited(BackgroundNotifService.ensureListeningWhileClosed());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(_persistSessionForBackground());
      unawaited(BackgroundNotifService.ensureListeningWhileClosed());
    }
  }

  Future<void> _onWebDocumentVisible() async {
    // Mobile web: visibility è più affidabile di AppLifecycle → riparti ascolto.
    unawaited(NotificationService().wakeListeningOnForeground());
    final authId = Supabase.instance.client.auth.currentSession?.user.id;
    if (authId != null) {
      _scheduleActivateNotifications(authId);
      unawaited(WebPushService.ensureRegisteredForCurrentUser(force: false));
    }
    await _maybeRelockOnResume();
  }

  Future<void> _maybeRelockOnResume() async {
    if (!AppDeviceUnlockGate.isRequiredOnThisDevice) return;
    // Impronta, fotocamera, galleria: non riaprire lo sblocco al rientro.
    if (AppDeviceUnlockGate.shouldIgnoreBackgroundLock) return;
    if (await AppDeviceUnlockGate.shouldSkipRepeatUnlockForCurrentUser()) {
      AppDeviceUnlockGate.markUnlocked();
      return;
    }
    if (AppDeviceUnlockGate.isUnlockedRecently) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final paused = _pausedAt;
    _pausedAt = null;
    // Evita dialog su flicker: solo se in background ≥ 8s.
    if (paused != null &&
        DateTime.now().difference(paused) < const Duration(seconds: 8)) {
      AppDeviceUnlockGate.markUnlocked();
      return;
    }
    final ctx = _appNavKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final route = ModalRoute.of(ctx)?.settings.name;
    if (route == '/login' || route == '/') return;
    // force:false rispetta isUnlockedRecently (evita loop post-impronta).
    final ok = await AppDeviceUnlockGate.ensureUnlockedForCurrentSession(
      ctx,
      force: false,
    );
    if (!ok) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      _appNavKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
    } else if (kIsWeb) {
      unawaited(WebPushService.ensureRegisteredForCurrentUser(force: false));
    }
  }

  Future<void> _persistSessionForBackground() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      if (kIsWeb) {
        unawaited(WebPushService.persistNotificationSession());
        unawaited(WebPushService.ensureRegisteredForCurrentUser(force: false));
        return;
      }
      final authId = session.user.id;
      final row = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      final userId = (row?['id'] as num?)?.toInt();
      if (userId == null || userId <= 0) return;
      await BackgroundNotifService.persistAuthSession(
        userId: userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppBrandingService.instance,
        AppThemeModeService.instance,
      ]),
      builder: (context, _) {
        final brand = AppBrandingService.instance;
        final accent = brand.accentColor;
        final topBar = brand.topBarColor;
        final themeCtrl = AppThemeModeService.instance;
        Widget app = MaterialApp(
      navigatorKey: _appNavKey,
      navigatorObservers: [logoLightSweepRouteObserver],
      title: brand.appTitle,
      debugShowCheckedModeBanner: false,
      theme: CronosAppThemes.light(accent: accent, topBar: topBar),
      darkTheme: CronosAppThemes.dark(accent: accent, topBar: topBar),
      themeMode: themeCtrl.themeMode,
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        // Overlay proprio: la sidebar nel builder è SOPRA il Navigator e
        // senza questo i Tooltip della rail crashano ("No Overlay widget found").
        final canvas = CronosAppBackground.baseColorOf(context);
        return CronosSmallScreenFit(
          child: NeonOrbitTicker(
            child: Builder(
            builder: (context) {
              final mq = cronosClampMediaQuery(MediaQuery.of(context));
              return MediaQuery(
                data: mq,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (ctx) {
                        final content = child == null
                            ? const SizedBox.shrink()
                            : ClassicSidebarShell(child: child);
                        return ColoredBox(
                          color: canvas,
                          child: AppChatOverlayHost(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const CronosAppBackground(),
                                Positioned.fill(child: content),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          ),
        );
      },

      // `home` spezza '/password-recovery' in '/' (splash) + recovery: dopo
      // ~1s lo splash fa pushReplacementNamed('/login') e cancella il reset.
      onGenerateInitialRoutes: (initialRoute) {
        if (_pendingOutlookOAuthUri != null) {
          return [
            MaterialPageRoute(
              builder: (_) =>
                  OutlookOAuthCallbackPage(uri: _pendingOutlookOAuthUri!),
            ),
          ];
        }
        if (PasswordRecoveryGate.shouldOpenResetPage) {
          return [
            MaterialPageRoute(
              settings: const RouteSettings(name: '/password-recovery'),
              builder: (_) => const ChangePasswordResetPage(),
            ),
          ];
        }
        final bootPath = () {
          final p = Uri.base.path;
          if (p == '/segnalazione-sicurezza' ||
              initialRoute == '/segnalazione-sicurezza') {
            return '/segnalazione-sicurezza';
          }
          return '';
        }();
        if (bootPath == '/segnalazione-sicurezza') {
          return [
            MaterialPageRoute(
              settings: const RouteSettings(name: '/segnalazione-sicurezza'),
              builder: (_) => const SecurityIncidentPublicPage(),
            ),
          ];
        }
        return [
          MaterialPageRoute(
            settings: const RouteSettings(name: '/splash'),
            builder: (_) => const GestoproSplashPage(),
          ),
        ];
      },
      routes: {
        '/splash': (_) => const GestoproSplashPage(),
        '/login': (_) => const LoginPage(),
        '/password-recovery': (_) => const ChangePasswordResetPage(),
        '/segnalazione-sicurezza': (_) => const SecurityIncidentPublicPage(),
      },

      onGenerateRoute: (settings) {
        final name = settings.name;
        final routePath = () {
          if (name == null || name.isEmpty) return '';
          final parsed = Uri.tryParse(name);
          if (parsed != null && parsed.path.isNotEmpty) return parsed.path;
          return name.split('?').first;
        }();

        if (routePath == '/password-recovery') {
          return MaterialPageRoute(
            settings: const RouteSettings(name: '/password-recovery'),
            builder: (_) => const ChangePasswordResetPage(),
          );
        }

        if (routePath == '/segnalazione-sicurezza') {
          return MaterialPageRoute(
            settings: const RouteSettings(name: '/segnalazione-sicurezza'),
            builder: (_) => const SecurityIncidentPublicPage(),
          );
        }

        if (name != null && name.startsWith('/auth/outlook/callback')) {
          final uri = Uri.parse(name.contains('?')
              ? name
              : '${settings.name}?${Uri.base.query}');
          return MaterialPageRoute(
            builder: (_) => OutlookOAuthCallbackPage(
              uri: name.contains('?') ? uri : Uri.base,
            ),
          );
        }

        if (name == '/dipendentePrenotazioni') {
          final session = Supabase.instance.client.auth.currentSession;

          return MaterialPageRoute(
            builder: (_) => session == null
                ? const LoginPage()
                : FutureBuilder<Map<String, dynamic>?>(
                    future: Supabase.instance.client
                        .from('users')
                        .select('id, username, full_name, email')
                        .eq('auth_id', session.user.id)
                        .maybeSingle(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final u = snap.data!;
                      final userId = u['id'] as int;

                      final username = (u['username'] ?? '').toString();
                      final fullName = (u['full_name'] ?? '').toString().trim();
                      final email = (u['email'] ?? '').toString();

                      final visibleName = fullName.isNotEmpty
                          ? fullName
                          : (username.isNotEmpty ? username : email);

                      _scheduleActivateNotifications(session.user.id);

                      return useMobileUi(context)
                          ? DipendentePrenotazioniMobilePage(
                              userId: userId,
                              username: username,
                              fullName: visibleName,
                            )
                          : DipendentePrenotazioniPage(
                              userId: userId,
                              username: username,
                              fullName: visibleName,
                            );
                    },
                  ),
          );
        }

        if (name == '/caposquadraPrenotazioni') {
          final s = Supabase.instance.client.auth.currentSession;
          return MaterialPageRoute(
            builder: (_) => s == null
                ? const LoginPage()
                : FutureBuilder<int>(
                    future: _resolveUserId(s.user.id),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final userId = snap.data!;
                      _scheduleActivateNotifications(s.user.id);
                      return CaposquadraPrenotazioniPage(userId: userId);
                    },
                  ),
          );
        }

        if (name == '/ristoratoreHome') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (_) => args == null
                ? const LoginPage()
                : RistoratoreHomePage(
                    userId: args['id'] as int,
                    username: (args['username'] ?? '') as String,
                    fullName: (args['full_name'] ?? '') as String,
                  ),
          );
        }

        if (name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            _scheduleActivateNotifications(session.user.id);
          }
          final homeUserId = args?['id'] as int?;
          if (homeUserId != null && homeUserId > 0) {
            unawaited(NotificationService().startListening(homeUserId, null));
          }
          return MaterialPageRoute(
            builder: (_) => args == null
                ? const LoginPage()
                : HomePage(
                    userId: args['id'] as int,
                    username: (args['username'] ?? '') as String,
                    role: (args['role'] ?? '') as String,
                    fullName: (args['full_name'] ?? '') as String,
                    secondaryRole: (args['secondary_role'] ?? '').toString().trim().isEmpty
                        ? null
                        : (args['secondary_role'] ?? '').toString(),
                  ),
          );
        }

        return MaterialPageRoute(builder: (_) => const LoginPage());
      },
    );
    if (kIsWeb) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => unawaited(WebNotificationSound.unlock()),
        child: app,
      );
    }
    return app;
      },
    );
  }
}

Future<int> _resolveUserId(String authId) async {
  final row = await Supabase.instance.client
      .from('users')
      .select('id')
      .eq('auth_id', authId)
      .single();

  return row['id'] as int;
}
