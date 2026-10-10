import 'package:supabase_flutter/supabase_flutter.dart';

/// Ripara JWT orfani («Session from session_id claim in JWT does not exist»).
abstract final class AuthSessionHeal {
  AuthSessionHeal._();

  static bool isDeadSessionError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('session_id claim') ||
        s.contains('session from session_id') ||
        s.contains('session_not_found') ||
        s.contains('invalid session') ||
        s.contains('refresh_token_not_found') ||
        s.contains('invalid refresh token');
  }

  /// Aggiorna i token; se la sessione è morta lato Auth, fa signOut e ritorna null.
  static Future<Session?> ensureFreshSession({bool signOutIfDead = true}) async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) return null;
    try {
      final res = await auth.refreshSession();
      return res.session ?? auth.currentSession;
    } catch (e) {
      if (isDeadSessionError(e)) {
        if (signOutIfDead) {
          try {
            await auth.signOut();
          } catch (_) {}
        }
        return null;
      }
      // Refresh fallito per rete/altro: tieni la sessione corrente.
      return auth.currentSession ?? session;
    }
  }
}
