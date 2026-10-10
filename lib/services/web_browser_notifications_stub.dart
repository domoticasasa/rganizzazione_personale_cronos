class WebBrowserNotifications {
  static Future<void> requestPermissionIfNeeded() async {}

  static Future<void> show(String title, String body, {String? tag}) async {}

  /// Su non-web la "tab" non esiste: tratta come non visibile per i rami web-only.
  static bool get isDocumentVisible => false;

  static bool get isDocumentFocused => false;

  static void markInAppSoundPlayed(String title, String body) {}

  static bool pushSoundJustPlayed(String title, String body) => false;
}
