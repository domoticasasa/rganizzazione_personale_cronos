import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Ponte JS ↔ Flutter per PWA Android/Chrome (notifica / scorciatoia Chat).
void installAppChatWebBridge({required void Function() onOpenChat}) {
  try {
    web.window.addEventListener(
      'cronos-open-chat',
      (web.Event _) {
        onOpenChat();
      }.toJS,
    );
  } catch (_) {}
}

bool consumeJsPendingOpenChat() {
  try {
    final v = web.window.getProperty('__cronosPendingOpenChat'.toJS);
    if (v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart) {
      web.window.setProperty('__cronosPendingOpenChat'.toJS, false.toJS);
      return true;
    }
  } catch (_) {}
  return false;
}
