import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _unlockAtKey = 'cronos_app_unlock_at_ms_v1';
const _pickerGraceKey = 'cronos_app_unlock_picker_grace_ms_v1';

/// Su web mobile, `visibilitychange` è più affidabile di AppLifecycle.
void attachAppDeviceUnlockVisibilityListener({
  required void Function() onHidden,
  required void Function() onVisible,
}) {
  web.document.addEventListener(
    'visibilitychange',
    (web.Event _) {
      if (web.document.visibilityState == 'hidden') {
        onHidden();
      } else if (web.document.visibilityState == 'visible') {
        onVisible();
      }
    }.toJS,
  );
}

/// localStorage: sopravvive al kill/reload del WebView (WhatsApp/fotocamera).
/// La scadenza a 30 minuti è nel gate (`isUnlockedRecently`).
void persistAppDeviceUnlockAt(DateTime? at) {
  _writeMs(_unlockAtKey, at?.millisecondsSinceEpoch);
}

DateTime? readPersistedAppDeviceUnlockAt() => _readMs(_unlockAtKey);

void persistAppDevicePickerGraceUntil(DateTime? until) {
  _writeMs(_pickerGraceKey, until?.millisecondsSinceEpoch);
}

DateTime? readPersistedAppDevicePickerGraceUntil() => _readMs(_pickerGraceKey);

void _writeMs(String key, int? ms) {
  try {
    final store = web.window.localStorage;
    if (ms == null) {
      store.removeItem(key);
      web.window.sessionStorage.removeItem(key);
    } else {
      store.setItem(key, '$ms');
    }
  } catch (_) {}
}

DateTime? _readMs(String key) {
  try {
    var raw = (web.window.localStorage.getItem(key) ?? '').trim();
    if (raw.isEmpty) {
      raw = (web.window.sessionStorage.getItem(key) ?? '').trim();
    }
    if (raw.isEmpty) return null;
    final ms = int.tryParse(raw);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  } catch (_) {
    return null;
  }
}
