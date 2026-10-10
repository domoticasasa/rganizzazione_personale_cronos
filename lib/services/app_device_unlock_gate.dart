import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:passkeys/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/responsive.dart';
import 'app_device_unlock_visibility.dart';
import 'auth_session_heal.dart';
import 'doc_firma_webauthn.dart';
import 'passkey_auth_service.dart';
import 'supabase_service.dart';

/// Sblocco app su mobile = **solo** lo sblocco di sistema del telefono
/// (impronta / Face ID / PIN del device). Nessun PIN/segno creati dall’app.
abstract final class AppDeviceUnlockGate {
  AppDeviceUnlockGate._();

  static const _credKey = 'cronos_app_unlock_webauthn_cred_v1';
  static const _trustedPrefix = 'cronos_android_web_passkey_ok_v1_';

  static DateTime? _unlockedAt;
  static bool _dialogOpen = false;
  /// True mentre è aperta la cerimonia WebAuthn/Passkey (impronta di sistema).
  static bool _ceremonyInProgress = false;
  static int _ceremonyDepth = 0;
  static int _externalPickerDepth = 0;
  static DateTime? _externalPickerGraceUntil;
  static bool _hydratedFromSession = false;

  /// Telefono/tablet nativo o browser mobile (iOS/Android).
  static bool get isRequiredOnThisDevice {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }
    return isMobileWebPlatform();
  }

  /// PWA / Chrome Android: Passkey una volta su questo telefono, poi no.
  /// NIS2: il primo accesso è MFA (password + Passkey); i successivi sono
  /// sullo stesso dispositivo già verificato (sblocco OS Android + sessione).
  static bool get remembersUnlockAfterFirstTime =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String _trustedKey(String authId) =>
      '$_trustedPrefix${authId.trim()}';

  static Future<bool> hasCompletedPasskeyOnThisDevice(String authId) async {
    final id = authId.trim();
    if (id.isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_trustedKey(id)) ?? false;
  }

  static Future<void> markPasskeyCompletedOnThisDevice(String authId) async {
    final id = authId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_trustedKey(id), true);
  }

  /// Sessione corrente già verificata su questo browser Android.
  static Future<bool> shouldSkipRepeatUnlockForCurrentUser() async {
    if (!remembersUnlockAfterFirstTime) return false;
    final id = (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
    if (id.isEmpty) return false;
    return hasCompletedPasskeyOnThisDevice(id);
  }

  /// Dialog o cerimonia biometrica in corso: non trattare come “app in background”.
  static bool get isUnlockInProgress => _dialogOpen || _ceremonyInProgress;

  /// Fotocamera / galleria / file picker: l’OS nasconde CRONOS ma la sessione resta.
  static bool get isExternalPickerInProgress {
    _hydrateFromSession();
    if (_externalPickerDepth > 0) return true;
    final until = _externalPickerGraceUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _externalPickerGraceUntil = null;
    persistAppDevicePickerGraceUntil(null);
    return false;
  }

  /// Non marcare locked né riaprire lo sblocco (impronta / visibilità hidden).
  static bool get shouldIgnoreBackgroundLock =>
      isUnlockInProgress || isExternalPickerInProgress;

  /// Avvolge cerimonie Passkey/WebAuthn (anche MFA post-password su desktop).
  /// Evita che visibility=hidden durante l’impronta spezzi push / re-lock.
  static Future<T> runWithCeremony<T>(Future<T> Function() action) async {
    _ceremonyDepth++;
    _ceremonyInProgress = true;
    try {
      return await action();
    } finally {
      _ceremonyDepth--;
      if (_ceremonyDepth <= 0) {
        _ceremonyDepth = 0;
        _ceremonyInProgress = false;
      }
    }
  }

  /// Fotocamera/galleria/file di sistema: non chiedere la passkey al rientro.
  static Future<T> runWithExternalPicker<T>(Future<T> Function() action) async {
    beginExternalPicker();
    try {
      return await action();
    } finally {
      endExternalPicker();
    }
  }

  static void beginExternalPicker() {
    _hydrateFromSession();
    _externalPickerDepth++;
    // iOS/PWA può ricaricare la tab durante la fotocamera: tieni una finestra
    // in sessionStorage così al rientro non riparte l’impronta.
    _externalPickerGraceUntil =
        DateTime.now().add(const Duration(minutes: 5));
    persistAppDevicePickerGraceUntil(_externalPickerGraceUntil);
  }

  static void endExternalPicker() {
    if (_externalPickerDepth > 0) _externalPickerDepth--;
    markUnlocked();
    _externalPickerGraceUntil =
        DateTime.now().add(const Duration(seconds: 45));
    persistAppDevicePickerGraceUntil(_externalPickerGraceUntil);
  }

  static bool get isUnlockedRecently {
    _hydrateFromSession();
    final at = _unlockedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(minutes: 30);
  }

  static void markUnlocked() {
    _unlockedAt = DateTime.now();
    persistAppDeviceUnlockAt(_unlockedAt);
  }

  static void markLocked() {
    // Non invalidare lo sblocco mentre l’utente sta usando l’impronta di sistema
    // o la fotocamera/galleria (l’app va in background ma resta in memoria).
    if (shouldIgnoreBackgroundLock) return;
    _unlockedAt = null;
    persistAppDeviceUnlockAt(null);
  }

  static void _hydrateFromSession() {
    if (_hydratedFromSession) return;
    _hydratedFromSession = true;
    final at = readPersistedAppDeviceUnlockAt();
    if (at != null && _unlockedAt == null) {
      _unlockedAt = at;
    }
    final grace = readPersistedAppDevicePickerGraceUntil();
    if (grace != null &&
        (_externalPickerGraceUntil == null ||
            grace.isAfter(_externalPickerGraceUntil!))) {
      _externalPickerGraceUntil = grace;
    }
  }

  static Future<String?> _savedCredId() async {
    final p = await SharedPreferences.getInstance();
    final id = (p.getString(_credKey) ?? '').trim();
    return id.isEmpty ? null : id;
  }

  static Future<void> _saveCredId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_credKey, trimmed);
  }

  static Future<void> _clearCredId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_credKey);
  }

  /// Chiede lo sblocco di sistema. `false` = annullato / fallito.
  static Future<bool> ensureUnlocked(
    BuildContext context, {
    required Map<String, dynamic> userRow,
    bool force = false,
  }) async {
    if (!isRequiredOnThisDevice) return true;
    if (!force && isUnlockedRecently) return true;
    // Già in corso: non aprire un secondo dialog (evita loop / false failure).
    if (_dialogOpen) return true;
    if (!context.mounted) return false;

    final authId = (userRow['auth_id'] ??
            SupabaseService.client.auth.currentUser?.id ??
            '')
        .toString()
        .trim();
    final username = (userRow['username'] ?? userRow['email'] ?? 'utente')
        .toString()
        .trim();
    final display = (userRow['full_name'] ?? username).toString().trim();
    if (authId.isEmpty) return false;

    if (remembersUnlockAfterFirstTime &&
        await hasCompletedPasskeyOnThisDevice(authId)) {
      markUnlocked();
      return true;
    }
    if (!context.mounted) return false;

    _dialogOpen = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SystemUnlockDialog(
          userId: authId,
          userName: username.isEmpty ? 'utente' : username,
          displayName: display.isEmpty ? username : display,
        ),
      );
      if (ok == true) {
        markUnlocked();
        if (remembersUnlockAfterFirstTime) {
          await markPasskeyCompletedOnThisDevice(authId);
        }
        return true;
      }
      return false;
    } finally {
      _dialogOpen = false;
    }
  }

  static Future<bool> ensureUnlockedForCurrentSession(
    BuildContext context, {
    bool force = false,
  }) async {
    if (!isRequiredOnThisDevice) return true;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return true;
    if (await shouldSkipRepeatUnlockForCurrentUser()) {
      markUnlocked();
      return true;
    }
    if (!force && isUnlockedRecently) return true;
    if (isUnlockInProgress) return true;
    if (!context.mounted) return false;

    Map<String, dynamic> fallback() => {
          'auth_id': session.user.id,
          'username': session.user.email ?? 'utente',
          'full_name': session.user.email ?? 'utente',
        };

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('auth_id,username,email,full_name')
          .eq('auth_id', session.user.id)
          .maybeSingle();
      if (!context.mounted) return false;
      return ensureUnlocked(
        context,
        userRow: row == null ? fallback() : Map<String, dynamic>.from(row),
        force: force,
      );
    } catch (_) {
      if (!context.mounted) return false;
      return ensureUnlocked(
        context,
        userRow: fallback(),
        force: force,
      );
    }
  }

  /// Web: WebAuthn piattaforma (sblocco OS). Native: Passkey Supabase.
  ///
  /// Al massimo **una** cerimonia biometrica di successo per chiamata
  /// (niente register→authenticate a catena che ripete l’impronta).
  static Future<String?> unlockWithSystemBiometrics({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    // Sempre Passkey Supabase quando supportata: così l’impronta sul telefono
    // registra/verifica una Passkey sull’account (usabile anche da PC), non solo
    // una credenziale locale DocFirma invisibile in «Passkey / MFA».
    if (PasskeyAuthService.isPlatformSupported) {
      if (kIsWeb) {
        final canAttempt = await DocFirmaWebAuthn.canAttemptPlatformAuth();
        if (!canAttempt) {
          return 'Questo browser non può usare lo sblocco del telefono.\n\n'
              'Su iPhone/iPad: apri CRONOS in Safari (non dal link di WhatsApp/'
              'Mail/Teams), su https://gestopro360.it, con Face ID o codice '
              'di sblocco attivi sul dispositivo.';
        }
      }
      return runWithCeremony(() async {
        final fresh =
            await AuthSessionHeal.ensureFreshSession(signOutIfDead: true);
        if (fresh == null) {
          return 'Sessione telefono scaduta o non valida.\n\n'
              'Chiudi questa pagina, apri di nuovo il link del QR, '
              'Accedi con email e password, poi conferma.';
        }
        try {
          await PasskeyAuthService.ensureBiometricAfterPasswordLogin();
          return null;
        } catch (e) {
          final msg = PasskeyAuthService.userMessage(e);
          if (AuthSessionHeal.isDeadSessionError(e)) {
            await AuthSessionHeal.ensureFreshSession(signOutIfDead: true);
            return 'Sessione telefono non valida.\n\n'
                'Accedi di nuovo con password, poi conferma il QR.';
          }
          // Fallback: sblocco OS locale se la Passkey account non è usabile.
          if (kIsWeb &&
              (_shouldFallbackToLocalWebUnlock(e) ||
                  msg.toLowerCase().contains('nessuna passkey') ||
                  msg.toLowerCase().contains('no passkey'))) {
            final local = await _unlockWeb(
              userId: userId,
              userName: userName,
              displayName: displayName,
            );
            if (local == null) return null;
            return '$msg\n\nSblocco locale: $local';
          }
          return msg;
        }
      });
    }

    if (kIsWeb) {
      final canAttempt = await DocFirmaWebAuthn.canAttemptPlatformAuth();
      if (!canAttempt) {
        return 'Questo browser non può usare lo sblocco del telefono.\n\n'
            'Su iPhone/iPad: apri CRONOS in Safari (non dal link di WhatsApp/'
            'Mail/Teams), su https://gestopro360.it, con Face ID o codice '
            'di sblocco attivi sul dispositivo.';
      }
      return runWithCeremony(() async {
        return _unlockWeb(
          userId: userId,
          userName: userName,
          displayName: displayName,
        );
      });
    }

    return PasskeyAuthService.unsupportedPlatformMessage;
  }

  static bool _shouldFallbackToLocalWebUnlock(Object e) {
    final lower = e.toString().toLowerCase();
    if (e is PasskeyAuthCancelledException) return false;
    if (lower.contains('annull') || lower.contains('cancel')) return false;
    return lower.contains('passkey_disabled') ||
        lower.contains('passkeys are disabled') ||
        lower.contains('not enabled') ||
        lower.contains('feature') && lower.contains('disabled');
  }

  static Future<String?> _unlockWeb({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    final saved = await _savedCredId();

    // 1) Credenziale già nota: una sola verifica.
    if (saved != null) {
      final auth = await DocFirmaWebAuthn.authenticateDetailed(
        credentialIdBase64Url: saved,
      );
      if (auth.ok) {
        final id = (auth.credentialId ?? saved).trim();
        await _saveCredId(id);
        return null;
      }
      final lower = (auth.errorMessage ?? '').toLowerCase();
      if (lower.contains('notallowed') ||
          lower.contains('annull') ||
          lower.contains('cancel')) {
        return auth.errorMessage ?? 'Sblocco annullato.';
      }
      // Credenziale non più valida → riparti da enroll.
      await _clearCredId();
    }

    // 2) Prova discoverable get (una sola richiesta impronta) se esiste già.
    final discover = await DocFirmaWebAuthn.authenticateDetailed();
    if (discover.ok) {
      final id = (discover.credentialId ?? '').trim();
      if (id.isNotEmpty) await _saveCredId(id);
      return null;
    }

    // 3) Nessuna credenziale usabile → registra una volta.
    final reg = await DocFirmaWebAuthn.registerDetailed(
      userId: userId,
      userName: userName,
      displayName: displayName,
    );
    if (reg.ok) {
      final id = (reg.credentialId ?? '').trim();
      if (id.isNotEmpty) await _saveCredId(id);
      return null;
    }

    final msg = (reg.errorMessage ?? '').toLowerCase();
    // Già registrata sul device: una sola auth di recupero.
    if (msg.contains('invalidstate') || msg.contains('già present')) {
      final auth = await DocFirmaWebAuthn.authenticateDetailed();
      if (auth.ok) {
        final id = (auth.credentialId ?? '').trim();
        if (id.isNotEmpty) await _saveCredId(id);
        return null;
      }
      return auth.errorMessage ??
          'Impronta già presente ma non verificabile. Riprova.';
    }

    return reg.errorMessage ?? 'Sblocco telefono non riuscito. Riprova.';
  }
}

class _SystemUnlockDialog extends StatefulWidget {
  const _SystemUnlockDialog({
    required this.userId,
    required this.userName,
    required this.displayName,
  });

  final String userId;
  final String userName;
  final String displayName;

  @override
  State<_SystemUnlockDialog> createState() => _SystemUnlockDialogState();
}

class _SystemUnlockDialogState extends State<_SystemUnlockDialog> {
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      // iOS/Safari: WebAuthn richiede un gesto utente (tap).
      // Su Android possiamo avviare subito.
      final needsTap = kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (!needsTap) {
        _run();
      }
    });
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AppDeviceUnlockGate.unlockWithSystemBiometrics(
      userId: widget.userId,
      userName: widget.userName,
      displayName: widget.displayName,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTapHint = kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !_busy &&
        _error == null;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Sblocca CRONOS'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Usa lo sblocco del telefono (impronta, Face ID o PIN di sistema). '
                'Non viene creato un PIN diverso per CRONOS.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (showTapHint) ...[
                const SizedBox(height: 12),
                Text(
                  'Su iPhone tocca «Sblocca col telefono» per attivare Face ID.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'In attesa dello sblocco del dispositivo…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.fingerprint),
            label: Text(_busy ? 'In corso…' : 'Sblocca col telefono'),
          ),
        ],
      ),
    );
  }
}
