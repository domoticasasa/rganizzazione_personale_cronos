/// Stub non-web: nessun badge sull'icona home.
abstract final class WebAppBadge {
  WebAppBadge._();

  static Future<void> setCount(int count) async {}

  static Future<void> clear() async {}
}
