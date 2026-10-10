// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'passkey_platform.dart';
import 'passkey_hybrid_pref.dart';
import 'app_device_unlock_gate.dart';
import 'auth_session_heal.dart';
import 'supabase_service.dart';

/// Autenticazione Passkeys (WebAuthn) via Supabase Auth (`supabase_flutter` 2.15+).
///
/// La cerimonia apre le credenziali di sistema:
/// - Windows: Windows Hello / chiave di sicurezza
/// - Web mobile / Android / iOS: Face ID, Touch ID o impronta
class PasskeyAuthService {
  PasskeyAuthService._();

  static GoTrueClient get _auth => SupabaseService.client.auth;

  /// True se la piattaforma corrente può eseguire la cerimonia passkey.
  static bool get isPlatformSupported => passkeyPlatformSupported;

  /// Login Passkey sul telefono (QR Windows hybrid), non Hello locale.
  static bool get preferPhoneQrCeremony => false;

  static bool get _isDesktopWeb {
    if (!kIsWeb) return false;
    return defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android;
  }

  /// Testo breve per lo sblocco biometrico / Hello della piattaforma corrente.
  static String get systemUnlockLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 'Face ID / Touch ID';
      case TargetPlatform.android:
        return 'impronta o blocco schermo';
      case TargetPlatform.windows:
        return 'Windows Hello (PIN / password di sblocco)';
      default:
        return kIsWeb
            ? 'biometria o blocco schermo del dispositivo'
            : 'credenziali di sistema';
    }
  }

  static const String _verificationFailedHelp =
      'La passkey scelta da Windows non è valida per CRONOS '
      '(spesso «Gestione password Microsoft», non Windows Hello).\n\n'
      'Usa «Accedi con Passkey sul telefono» o «Accedi con QR telefono». '
      'In alternativa accedi con password: verrà registrato Windows Hello '
      'su questo PC.';

  static Future<T> _withCeremonyHint<T>(
    Future<T> Function() action, {
    bool preferHybrid = false,
    bool preferPlatform = false,
  }) async {
    if (kIsWeb) {
      setPreferHybridPasskey(preferHybrid);
      setPreferPlatformPasskey(preferPlatform && !preferHybrid);
    }
    try {
      return await action();
    } finally {
      if (kIsWeb) {
        setPreferHybridPasskey(false);
        setPreferPlatformPasskey(false);
      }
    }
  }

  static String get unsupportedPlatformMessage =>
      'Passkeys non sono supportate su questa piattaforma. '
      'Usa browser (Chrome/Edge/Safari), Android, iOS, macOS o Windows.';

  /// Login passkey diretto: solo desktop (Windows/macOS). Su telefono/tablet
  /// l’impronta si attiva in automatico dopo «Accedi» con password.
  static bool get showPasskeyLoginButton {
    if (!isPlatformSupported) return false;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return false;
    }
    return true;
  }

  static void _ensureSupported() {
    if (!isPlatformSupported) {
      throw UnsupportedError(unsupportedPlatformMessage);
    }
  }

  /// `true` se il hint indica che lo sblocco di sistema non è pronto.
  static bool isBlockingAvailabilityHint(String? hint) {
    if (hint == null) return false;
    final h = hint.toLowerCase();
    return h.contains('non risulta') ||
        h.contains('non è configurato') ||
        h.contains('non disponibili') ||
        h.contains('non supporta passkey') ||
        h.contains('non supporta passkey/webauthn');
  }

  /// Verifica runtime (WebAuthn / biometria / Windows Hello).
  static Future<String?> availabilityHint() async {
    if (!isPlatformSupported) return unsupportedPlatformMessage;
    try {
      final auth = PasskeyAuthenticator();
      if (kIsWeb) {
        final a = await auth.getAvailability().web();
        if (!a.hasPasskeySupport) {
          return 'Questo browser non supporta Passkey/WebAuthn. '
              'Su telefono usa Chrome o Safari aggiornati (HTTPS).';
        }
        // Desktop senza Windows Hello: si usa QR hybrid sul telefono.
        // Mobile: UVPA può essere false pur con impronta attiva.
        return null;
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.windows:
          final a = await auth.getAvailability().windows();
          if (!a.hasPasskeySupport) {
            return 'Passkey non disponibili su questo Windows. '
                'Aggiorna Windows e configura Windows Hello.';
          }
          // Hello assente: non bloccare se poi si usa browser/QR.
          break;
        case TargetPlatform.android:
          final a = await auth.getAvailability().android();
          if (!a.hasPasskeySupport) {
            return 'Passkey non disponibili su questo Android. '
                'Serve Android 9+ con Google Play Services e blocco schermo.';
          }
          break;
        case TargetPlatform.iOS:
          final a = await auth.getAvailability().iOS();
          if (!a.hasPasskeySupport) {
            return 'Passkey non disponibili su questo iPhone/iPad. '
                'Serve iOS 16+ con Face ID / Touch ID configurato.';
          }
          break;
        default:
          break;
      }
    } catch (_) {
      // Availability opzionale: non bloccare il flusso.
    }
    return null;
  }

  /// Dopo login con password: biometria / Passkey.
  /// Se l’account ha già una Passkey → accedi/verifica con quella
  /// (non chiede di crearne un’altra). Solo se non ce n’è nessuna usabile → enroll.
  static Future<void> ensureBiometricAfterPasswordLogin() async {
    return AppDeviceUnlockGate.runWithCeremony(() async {
      _ensureSupported();
      final healed = await AuthSessionHeal.ensureFreshSession();
      if (healed == null && _auth.currentSession == null) {
        throw StateError(
          'Sessione scaduta. Accedi di nuovo con password.',
        );
      }
      if (_auth.currentSession == null) {
        throw StateError('Sessione assente: impossibile attivare la biometria.');
      }

      final hint = await availabilityHint();
      if (isBlockingAvailabilityHint(hint)) {
        throw StateError(hint ?? unsupportedPlatformMessage);
      }

      final hasServerPasskey = await hasAnyPasskey();
      if (hasServerPasskey) {
        try {
          await _withCeremonyHint(
            _signInWithPasskeyRaw,
            preferPlatform: true,
          );
          return;
        } catch (e) {
          if (e is PasskeyAuthCancelledException) rethrow;
          if (!_isUnusableLocalPasskey(e)) rethrow;
          // Credenziale locale non CRONOS (es. Gestione password Microsoft)
          // oppure nessuna passkey su questo PC.
          if (_isDesktopWeb) {
            try {
              await _withCeremonyHint(
                _signInWithPasskeyRaw,
                preferHybrid: true,
              );
              return;
            } catch (hybridErr) {
              if (hybridErr is PasskeyAuthCancelledException) rethrow;
              if (!_isUnusableLocalPasskey(hybridErr)) rethrow;
            }
          }
        }
      }

      try {
        await _withCeremonyHint(
          () => _registerRaw(friendlyName: _autoDeviceLabel()),
          preferPlatform: true,
        );
      } catch (e) {
        if (_isPasskeyAlreadyOnThisDevice(e)) {
          try {
            await _withCeremonyHint(
              _signInWithPasskeyRaw,
              preferPlatform: true,
            );
            return;
          } catch (verifyErr) {
            if (verifyErr is PasskeyAuthCancelledException) rethrow;
            if (_isNoLocalPasskeyError(verifyErr)) {
              throw StateError(
                'Su questo dispositivo non c’è ancora una Passkey CRONOS. '
                'Apri «I miei dati» e tocca «Crea e verifica Passkey».',
              );
            }
            if (_isCredentialVerificationFailed(verifyErr)) {
              throw StateError(_verificationFailedHelp);
            }
            throw StateError(
              'Passkey già presente su questo dispositivo. '
              'Conferma lo sblocco e riprova «Accedi».',
            );
          }
        }
        if (_isMfaLevelBlocked(e)) {
          throw StateError(
            'Per registrare l’impronta serve prima completare l’MFA TOTP '
            'sull’account, oppure disabilitare il TOTP obbligatorio in Supabase.',
          );
        }
        rethrow;
      }
    });
  }

  /// Verifica biometrica solo se la Passkey esiste in locale; altrimenti non
  /// apre il dialogo Google «nessuna passkey» (es. Passkey solo su PC).
  // ignore: unused_element
  static Future<void> _verifyLocalPasskeyIfPresent() async {
    try {
      await verifyAsSecondFactor();
    } catch (e) {
      if (_isNoLocalPasskeyError(e) || e is PasskeyAuthCancelledException) {
        if (e is PasskeyAuthCancelledException) rethrow;
        return;
      }
      rethrow;
    }
  }

  static bool _isPasskeyAlreadyOnThisDevice(Object e) {
    if (e is ExcludeCredentialsCanNotBeRegisteredException) return true;
    if (e is AuthException) {
      final code = (e.code ?? '').toLowerCase();
      if (code == 'webauthn_credential_exists' ||
          code.contains('credential_exists') ||
          code.contains('already_exists')) {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('invalidstateerror') ||
        s.contains('invalid state') ||
        s.contains('already registered') ||
        s.contains('credentials already') ||
        s.contains('excludecredentials') ||
        s.contains('exclude_credentials') ||
        s.contains('credential that contains one of the credentials');
  }

  static bool _isNoLocalPasskeyError(Object e) {
    if (e is NoCredentialsAvailableException) return true;
    final lower = e.toString().toLowerCase();
    return lower.contains('no-credentials') ||
        lower.contains('no_credentials') ||
        lower.contains('non sono present') ||
        lower.contains('nessuna passkey') ||
        lower.contains('no passkey') ||
        lower.contains('no credentials available');
  }

  static bool _isCredentialVerificationFailed(Object e) {
    String code = '';
    String msg = '';
    if (e is AuthException) {
      code = (e.code ?? '').toLowerCase();
      msg = e.message.toLowerCase();
    }
    final lower = '$code $msg ${e.toString()}'.toLowerCase();
    return lower.contains('credential verification failed') ||
        lower.contains('webauthn_credential_invalid') ||
        lower.contains('invalid webauthn') ||
        lower.contains('unknown credential') ||
        (lower.contains('webauthn') &&
            (lower.contains('verification failed') ||
                lower.contains('invalid_credential')));
  }

  /// Passkey locale mostrata da Windows ma non registrata su CRONOS
  /// (tipico: «Gestione password Microsoft») oppure assente su questo PC.
  static bool _isUnusableLocalPasskey(Object e) =>
      _isNoLocalPasskeyError(e) || _isCredentialVerificationFailed(e);

  static bool _isMfaLevelBlocked(Object e) {
    if (e is AuthException) {
      final code = (e.code ?? '').toLowerCase();
      final msg = e.message.toLowerCase();
      return code.contains('mfa') ||
          msg.contains('aal2') ||
          msg.contains('mfa verification');
    }
    final lower = e.toString().toLowerCase();
    return lower.contains('aal2') || lower.contains('mfa verification');
  }

  static String _autoDeviceLabel() {
    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iPhone/iPad $stamp';
      case TargetPlatform.android:
        return 'Android $stamp';
      case TargetPlatform.windows:
        return 'Windows $stamp';
      case TargetPlatform.macOS:
        return 'Mac $stamp';
      default:
        return kIsWeb ? 'Browser $stamp' : 'Dispositivo $stamp';
    }
  }

  /// Registra una nuova passkey per l'utente già autenticato.
  static Future<Passkey> register({String? friendlyName}) async {
    _ensureSupported();
    if (_auth.currentSession == null) {
      throw StateError('Devi essere autenticato per registrare una Passkey.');
    }
    return _withCeremonyHint(
      () => _registerRaw(friendlyName: friendlyName),
      preferPlatform: true,
    );
  }

  static Future<Passkey> _registerRaw({String? friendlyName}) async {
    final passkey = await _auth.registerPasskey();
    final name = (friendlyName ?? '').trim();
    if (name.isNotEmpty) {
      try {
        await _auth.passkey.update(
          passkeyId: passkey.id,
          friendlyName: name,
        );
        final listed = await list();
        return listed.firstWhere(
          (p) => p.id == passkey.id,
          orElse: () => passkey,
        );
      } catch (_) {
        return passkey;
      }
    }
    return passkey;
  }

  /// Registra una Passkey su QUESTO dispositivo (multi-device OK).
  /// Restituisce `false` se su questo device funziona già; `true` se ne è stata creata una.
  static Future<bool> enrollPasskeyOnThisDevice() async {
    _ensureSupported();
    if (_auth.currentSession == null) {
      throw StateError('Devi essere autenticato per registrare una Passkey.');
    }
    try {
      await _withCeremonyHint(
        () => _registerRaw(friendlyName: _autoDeviceLabel()),
        preferPlatform: true,
      );
    } catch (e) {
      if (e is PasskeyAuthCancelledException) rethrow;
      if (_isPasskeyAlreadyOnThisDevice(e)) {
        try {
          await _withCeremonyHint(
            _signInWithPasskeyRaw,
            preferPlatform: true,
          );
          return false;
        } catch (verifyErr) {
          if (verifyErr is PasskeyAuthCancelledException) rethrow;
          // Account ha Passkey altrove ma non usabile qui → riprova enroll sotto.
          if (!_isUnusableLocalPasskey(verifyErr)) rethrow;
        }
        // Seconda chance: crea comunque su questo device.
        await _withCeremonyHint(
          () => _registerRaw(friendlyName: _autoDeviceLabel()),
          preferPlatform: true,
        );
      } else if (_isMfaLevelBlocked(e)) {
        throw StateError(
          'Per registrare l’impronta serve prima l’OTP email o l’MFA '
          'richiesto dall’account.',
        );
      } else {
        rethrow;
      }
    }
    try {
      await verifyAsSecondFactor();
    } catch (e) {
      if (e is PasskeyAuthCancelledException) rethrow;
      if (!_isNoLocalPasskeyError(e) && !_isCredentialVerificationFailed(e)) {
        rethrow;
      }
    }
    return true;
  }

  /// Alias: crea su questo device anche se l’account ha già Passkey altrove.
  static Future<bool> forceCreateThenVerifyIfMissing() =>
      enrollPasskeyOnThisDevice();

  /// Login passwordless: Face ID / impronta / Windows Hello.
  /// [preferPhone]: forza il QR Windows «Usa un telefono».
  static Future<AuthResponse> signIn({bool preferPhone = false}) async {
    return AppDeviceUnlockGate.runWithCeremony(() async {
      _ensureSupported();
      try {
        return await _withCeremonyHint(
          _signInWithPasskeyRaw,
          preferHybrid: preferPhone,
          preferPlatform: !preferPhone,
        );
      } catch (e) {
        if (e is PasskeyAuthCancelledException) rethrow;
        if (!preferPhone &&
            _isDesktopWeb &&
            _isCredentialVerificationFailed(e)) {
          return await _withCeremonyHint(
            _signInWithPasskeyRaw,
            preferHybrid: true,
          );
        }
        rethrow;
      }
    });
  }

  /// Secondo fattore dopo login password.
  static Future<AuthResponse> verifyAsSecondFactor() async {
    Future<AuthResponse> run() async {
      _ensureSupported();
      return _withCeremonyHint(
        _signInWithPasskeyRaw,
        preferPlatform: true,
      );
    }

    if (AppDeviceUnlockGate.isUnlockInProgress) {
      return run();
    }
    return AppDeviceUnlockGate.runWithCeremony(run);
  }

  static Future<AuthResponse> _signInWithPasskeyRaw() =>
      _auth.signInWithPasskey();

  static Future<List<Passkey>> list() async {
    return _auth.passkey.list();
  }

  static Future<void> rename({
    required String passkeyId,
    required String friendlyName,
  }) async {
    await _auth.passkey.update(
      passkeyId: passkeyId,
      friendlyName: friendlyName.trim(),
    );
  }

  static Future<void> delete(String passkeyId) async {
    await _auth.passkey.delete(passkeyId: passkeyId);
  }

  static Future<bool> hasAnyPasskey() async {
    try {
      final items = await list();
      return items.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String userMessage(Object e) {
    if (e is UnimplementedError) {
      return 'Plugin Passkey non inizializzato su questo client. '
          'Ricarica la pagina su https://gestopro360.it '
          '(hard refresh) dopo il nuovo deploy.';
    }
    if (e is UnsupportedError) {
      final m = (e.message ?? '').trim();
      if (m.contains('Passkeys non sono supportate')) {
        return unsupportedPlatformMessage;
      }
      if (m.isNotEmpty) return m;
    }
    if (e is StateError) {
      final m = e.message.trim();
      if (m.isNotEmpty) return m;
    }

    final raw = e.toString();
    final lower = raw.toLowerCase();

    if (e is PasskeyAuthCancelledException) {
      return 'Operazione Passkey annullata.';
    }
    if (e is NoCredentialsAvailableException) {
      return 'Nessuna Passkey su questo dispositivo. '
          'Ripeti l’accesso con password: verrà registrata '
          '$systemUnlockLabel in automatico.';
    }
    if (lower.contains('non sono present') ||
        lower.contains('nessuna passkey') ||
        lower.contains('no passkey')) {
      return 'Passkey non ancora registrata su questo telefono/PC. '
          'Accedi di nuovo con password: comparirà la richiesta di '
          '$systemUnlockLabel per registrarla.';
    }
    if (e is DeviceNotSupportedException) {
      return 'Dispositivo senza supporto Passkey. '
          'Configura $systemUnlockLabel nelle impostazioni di sistema.';
    }
    if (e is PasskeyUnsupportedException) {
      return e.message ??
          'Passkey non supportate su questa versione del sistema.';
    }
    if (e is DomainNotAssociatedException) {
      final m = (e.message ?? '').trim();
      return m.isNotEmpty
          ? m
          : 'Dominio non associato all’app (RP ID: gestopro360.it). '
              'Apri il sito su https://gestopro360.it (non da altro dominio).';
    }

    if (_isCredentialVerificationFailed(e)) {
      return _verificationFailedHelp;
    }

    if (lower.contains('session_id claim') ||
        lower.contains('session from session_id') ||
        lower.contains('session_not_found')) {
      return 'Sessione telefono scaduta o non valida. '
          'Accedi di nuovo con email e password, poi riprova.';
    }

    if (lower.contains('passkey_disabled') ||
        lower.contains('passkeys are disabled') ||
        lower.contains('not enabled')) {
      return 'Passkeys non abilitate sul progetto Supabase. '
          'Dashboard → Authentication → Passkeys (RP ID: gestopro360.it).';
    }
    if (lower.contains('invalidstateerror') ||
        lower.contains('already registered') ||
        lower.contains('credentials already')) {
      return 'Impronta già attiva su questo telefono. '
          'Ripeti «Accedi»: verrà chiesta solo la verifica.';
    }
    if (lower.contains('cancelled') ||
        lower.contains('canceled') ||
        lower.contains('abort') ||
        lower.contains('notallowederror')) {
      return 'Operazione annullata o bloccata. '
          'Conferma con $systemUnlockLabel.';
    }
    if (lower.contains('notsupportederror')) {
      return 'WebAuthn non disponibile in questo browser. '
          'Usa Chrome/Safari su https://gestopro360.it.';
    }
    if (e is AuthException && e.message.trim().isNotEmpty) {
      final m = e.message.toLowerCase();
      if (m.contains('credential') ||
          m.contains('webauthn') ||
          m.contains('passkey')) {
        return _verificationFailedHelp;
      }
      return e.message;
    }
    return 'Errore Passkey: $e';
  }
}
