import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Coordina il flusso "password dimenticata" / recovery link.
///
/// Supabase emette [AuthChangeEvent.passwordRecovery] durante
/// [Supabase.initialize] (prima che [LoginPage] monti il listener): senza
/// questo gate l'evento si perde e [_tryAutoLogin] può entrare in app
/// saltando la pagina di nuova password.
class PasswordRecoveryGate {
  PasswordRecoveryGate._();

  static bool _pending = false;
  static bool _fromRecoveryLink = false;
  static bool _completed = false;
  static bool _verified = false;
  static String? _tokenHash;

  /// True solo se la sessione corrente è nata da un link di recupero
  /// (evento passwordRecovery, callback auth all'avvio o token_hash verificato).
  static bool get isRecoverySessionVerified => _verified && !_completed;

  /// Token del link ancora da verificare (tenuto solo in memoria).
  static bool get hasUnverifiedToken =>
      !_verified && (_tokenHash ?? '').isNotEmpty;

  static bool get isPending => _pending;

  /// True se l'utente è arrivato dal link mail: niente splash/login.
  static bool get shouldOpenResetPage {
    if (_completed) return false;
    return _pending ||
        _fromRecoveryLink ||
        (_tokenHash != null && _tokenHash!.isNotEmpty);
  }

  static void markPending() {
    if (_completed) return;
    _pending = true;
    _verified = true;
  }

  /// Reset riuscito: non riaprire più la pagina di nuova password.
  static void markCompleted() {
    _completed = true;
    _pending = false;
    _verified = false;
    _fromRecoveryLink = false;
    _tokenHash = null;
  }

  /// Nuova richiesta «Password dimenticata?».
  static void allowNewRecovery() {
    _completed = false;
    dismiss();
  }

  /// L'utente ha scelto di uscire dal reset: torna al login normale.
  static void dismiss() {
    _pending = false;
    _verified = false;
    _fromRecoveryLink = false;
    _tokenHash = null;
  }

  /// Restituisce true una sola volta se c'è un recovery in sospeso.
  static bool consume() {
    if (!_pending) return false;
    _pending = false;
    return true;
  }

  static void captureFromBoot({
    required Uri uri,
    String? storedTokenHash,
  }) {
    // Il solo percorso /password-recovery NON basta: serve un token del link
    // mail, altrimenti un utente già loggato potrebbe cambiare password
    // senza conoscere quella attuale.
    final fromUri = uri.queryParameters['token_hash']?.trim() ?? '';
    final stored = storedTokenHash?.trim() ?? '';
    final hash = fromUri.isNotEmpty ? fromUri : stored;
    if (hash.isNotEmpty) {
      _tokenHash = hash;
      _fromRecoveryLink = true;
    }
    if (uri.queryParameters['type']?.toLowerCase() == 'recovery') {
      _fromRecoveryLink = true;
    }
  }

  /// Scambia `token_hash` (link nella mail) in sessione recovery.
  static Future<bool> verifyTokenHashIfPresent(Uri uri) async {
    final fromUri = uri.queryParameters['token_hash']?.trim() ?? '';
    final tokenHash = (fromUri.isNotEmpty ? fromUri : (_tokenHash ?? '')).trim();
    if (tokenHash.isEmpty) return false;
    _tokenHash = tokenHash;
    _fromRecoveryLink = true;
    // In sospeso PRIMA di verifyOTP: l'evento signedIn arriva subito e non
    // deve avviare chat/notifiche/push con la sessione di recupero.
    final wasPending = _pending;
    _pending = true;
    try {
      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.recovery,
      );
      markPending();
      _tokenHash = null;
      if (kDebugMode) {
        // ignore: avoid_print
        print('PasswordRecoveryGate: token_hash verificato');
      }
      return true;
    } catch (e) {
      // Solo type=recovery: niente fallback a OTP di login via email.
      debugPrint('PasswordRecoveryGate.verifyOTP recovery: $e');
      _pending = wasPending;
      return false;
    }
  }

  /// True se l'URL di boot sembra un callback auth (PKCE / implicit recovery).
  static bool uriLooksLikeAuthCallback(Uri uri) {
    if (uri.queryParameters.containsKey('code')) return true;
    if (uri.queryParameters.containsKey('token_hash')) return true;
    if (uri.queryParameters['type'] == 'recovery') return true;
    final frag = uri.fragment;
    // Flutter hash routing (`#/login`) non è un callback auth.
    if (frag == '/login' || frag == '/' || frag.isEmpty) return false;
    if (frag.contains('type=recovery')) return true;
    if (frag.contains('access_token')) return true;
    if (frag.contains('refresh_token')) return true;
    return false;
  }

  /// Da chiamare subito dopo [Supabase.initialize] su web.
  ///
  /// [hadAuthCallbackUri] va calcolato **prima** di initialize (l'SDK può
  /// consumare/pulire i query param). [hasSession] deve essere true solo se
  /// lo scambio code/token è andato a buon fine.
  static void captureAfterInitialize({
    required bool hadAuthCallbackUri,
    required bool hasSession,
  }) {
    if (!kIsWeb || !hadAuthCallbackUri || !hasSession) return;
    markPending();
    if (kDebugMode) {
      // ignore: avoid_print
      print('PasswordRecoveryGate: recovery callback rilevato all\'avvio');
    }
  }
}
