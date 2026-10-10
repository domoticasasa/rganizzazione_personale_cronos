import 'package:web/web.dart' as web;

String? readAuthQrFromSessionStorage() {
  try {
    final v = web.window.sessionStorage.getItem('cronos_auth_qr');
    final t = (v ?? '').trim().toUpperCase();
    return t.isEmpty ? null : t;
  } catch (_) {
    return null;
  }
}

void clearAuthQrFromSessionStorage() {
  try {
    web.window.sessionStorage.removeItem('cronos_auth_qr');
  } catch (_) {}
}
