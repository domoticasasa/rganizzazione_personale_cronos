class WebPushService {
  WebPushService._();

  static Future<bool> ensureRegisteredForCurrentUser({bool force = false}) async =>
      false;

  static Future<void> deactivateCurrentDeviceOnLogout() async {}

  static Future<void> persistNotificationSession() async {}

  static String get notificationPermission => 'unsupported';

  static bool get isBrowserNotificationGranted => false;

  static bool get isPushRegisteredOnThisDevice => false;

  static bool get isIosSafariTabWithoutHomeScreen => false;

  static void addPermissionChangeListener(void Function() listener) {}

  static void removePermissionChangeListener(void Function() listener) {}

  static Future<bool> requestBrowserPermissionFromUser() async => false;
}
