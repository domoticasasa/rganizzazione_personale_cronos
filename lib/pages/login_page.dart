import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';
import '../widgets/neo_buttons.dart';
import '../utils/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'change_password_page.dart';
import '../services/gestopro_mode_prefs.dart';
import '../services/app_branding_service.dart';
import '../services/app_chat_overlay_controller.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/classic_nav_sub_items_cache.dart';
import '../widgets/futuristic/gestopro_session_cache.dart';
import '../services/web_notification_sound.dart';
import '../utils/app_copyright.dart';
import '../utils/domain_migration_notice.dart';
import '../services/password_recovery_gate.dart';
import '../services/app_open_tracker.dart';
import '../utils/roles.dart';
import '../services/passkey_auth_service.dart';
import '../services/app_device_unlock_gate.dart';
import '../services/web_push_service.dart';
import '../services/auth_qr_pending.dart';
import '../widgets/auth_qr_login_dialog.dart';
import '../theme/cronos_app_themes.dart';

String _loginErrorMessage(Object e) {
  final raw = e.toString().toLowerCase();
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Email o password non corretti. Controlla i dati e riprova.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email non confermata. Controlla la posta e conferma l\'account.';
    }
    if (msg.contains('credential verification failed') ||
        msg.contains('webauthn') ||
        msg.contains('passkey')) {
      return PasskeyAuthService.userMessage(e);
    }
    if (e.message.trim().isNotEmpty &&
        !e.message.contains('AuthApiException') &&
        !e.message.contains('statusCode')) {
      return e.message;
    }
  }
  if (raw.contains('invalid login credentials') ||
      raw.contains('invalid_credentials')) {
    return 'Email o password non corretti. Controlla i dati e riprova.';
  }
  return 'Accesso non riuscito. Riprova più tardi.';
}

enum _LoginOtpResult { ok, cancelled, continueWithout }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl  = TextEditingController();
  StreamSubscription<AuthState>? _authSub;
  Timer? _resetCooldownTimer;
  DateTime? _lastForgotPasswordRequest;

  bool loading = false;
  bool resetting = false;
  int resetCooldownSec = 0;
  String? _resetCooldownEmail;
  bool rememberMe = true;
  bool obscure = true;
  String? error;
  bool _openedRecoveryPage = false;
  String? _authQrBannerCode;
  /// Se true, su QUESTO dispositivo la Passkey è già ok → pulsante inibito.
  bool _passkeyOnThisDevice = false;

  @override
  void initState() {
    super.initState();
    AppChatOverlayController.clearSplashBlock();
    ClassicNavSessionCache.clear();
    ClassicNavSubItemsCache.clear();
    GestoproSessionCache.clear();
    unawaited(GestoproModePrefs.isActive());
    final qr = AuthQrPending.codeFromUrl();
    if (qr != null) {
      _authQrBannerCode = qr;
      unawaited(AuthQrPending.remember(qr));
    }
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (!PasswordRecoveryGate.shouldOpenResetPage) return;
        PasswordRecoveryGate.markPending();
        _openResetPasswordPage();
      }
    });
    _prefill().then((_) {
      if (!mounted) return;
      if (PasswordRecoveryGate.shouldOpenResetPage) {
        _openResetPasswordPage();
        return;
      }
      unawaited(_tryAutoLogin());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(DomainMigrationNotice.maybeShow(context));
    });
  }

  void _openResetPasswordPage() {
    if (_openedRecoveryPage) {
      PasswordRecoveryGate.consume();
      return;
    }
    _openedRecoveryPage = true;
    PasswordRecoveryGate.consume();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .pushNamed('/password-recovery')
          .then((_) {
        if (mounted) _openedRecoveryPage = false;
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _resetCooldownTimer?.cancel();
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  /// Blocca il tap solo se il cooldown è attivo per **questa** email (così cambiando
  /// casella si può riprovare subito senza attendere il timer di un altro indirizzo).
  bool _forgotPasswordCooldownBlocksTap() {
    if (resetCooldownSec <= 0) return false;
    final ce = (_resetCooldownEmail ?? '').trim().toLowerCase();
    final cur = emailCtrl.text.trim().toLowerCase();
    return ce.isNotEmpty && ce == cur;
  }

  void _startResetCooldown(int seconds, String email) {
    _resetCooldownTimer?.cancel();
    setState(() {
      resetCooldownSec = seconds;
      _resetCooldownEmail = email.trim().toLowerCase();
    });
    _resetCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (resetCooldownSec <= 1) {
        t.cancel();
        setState(() {
          resetCooldownSec = 0;
          _resetCooldownEmail = null;
        });
      } else {
        setState(() => resetCooldownSec -= 1);
      }
    });
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    rememberMe = prefs.getBool("remember_me") ?? true;

    if (rememberMe) {
      emailCtrl.text = prefs.getString("remember_email") ?? "";
    }

    if (mounted) setState(() {});
  }

  Future<void> _remember(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("remember_me", rememberMe);
    if (rememberMe) {
      await prefs.setString("remember_email", email);
    } else {
      await prefs.remove("remember_email");
    }
  }

  /// Dopo password: biometria automatica.
  /// Per ruoli elevati (admin/logistica) è obbligatoria se la piattaforma supporta Passkey.
  Future<bool> _passkeyBiometricGate({required bool elevatedRole}) async {
    if (!PasskeyAuthService.isPlatformSupported) {
      if (elevatedRole) {
        // Non blocchiamo login su piattaforme senza WebAuthn, ma avvisiamo.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Attenzione NIS2: questo dispositivo non supporta Passkey. '
                'Usa PC/telefono con Windows Hello, Face ID o impronta.',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
      return true;
    }
    if (!mounted) return false;
    setState(() => error = null);
    try {
      await PasskeyAuthService.ensureBiometricAfterPasswordLogin();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => error = PasskeyAuthService.userMessage(e));
      }
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      return false;
    }
  }

  bool _isElevatedSecurityRole(String role) {
    final r = normalizeRole(role);
    return r == 'admin_generale' ||
        r == 'admin_vista' ||
        r == 'admin_pernottamenti' ||
        r == 'admin_trenoaereo' ||
        r == 'admin_formazione' ||
        r == 'admin_dpi' ||
        r == 'logistica' ||
        r == 'dt' ||
        r == 'assistente_dt';
  }

  Future<void> _completeLoginForUser(Map<String, dynamic> p,
      {required bool enforcePasskeyMfa,
      bool skipBiometricGate = false,
      bool forceDeviceUnlock = false}) async {
    final mustChange = p['must_change_password'] == true;
    final role = (p['role'] ?? '').toString().toLowerCase();
    final authId = Supabase.instance.client.auth.currentUser?.id;
    final elevated = _isElevatedSecurityRole(role);

    if (mustChange) {
      if (!mounted || authId == null) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChangePasswordPage(authId: authId),
        ),
      );
      return;
    }

    // Mobile (web/app): sblocco dispositivo (impronta / Face ID / PIN / segno).
    if (AppDeviceUnlockGate.isRequiredOnThisDevice) {
      if (!skipBiometricGate) {
        final unlocked = await AppDeviceUnlockGate.ensureUnlocked(
          context,
          userRow: p,
          // Solo dopo password: un reload (fotocamera/WhatsApp) non deve
          // rifare l’impronta se lo sblocco è ancora valido.
          force: forceDeviceUnlock,
        );
        if (!unlocked || !mounted) {
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
          if (mounted) {
            setState(() {
              error =
                  'Sblocco annullato. Usa impronta, Face ID o PIN del telefono.';
            });
          }
          return;
        }
      }
    } else if (!skipBiometricGate && (enforcePasskeyMfa || elevated)) {
      // Passkey/QR già fatti: non riaprire una seconda cerimonia.
      final ok = await _passkeyBiometricGate(elevatedRole: elevated);
      if (!ok || !mounted) return;
    }

    final userId = int.tryParse('${p['id']}') ?? 0;
    if (!mounted) return;
    await AppCopyright.ensureAccepted(context, userId: userId);
    if (!mounted) return;

    // QR PC: prova a confermare, ma non bloccare mai il login sul telefono.
    await AuthQrPending.tryApproveForCurrentSession(context);
    if (!mounted) return;
    if (_authQrBannerCode != null) {
      setState(() => _authQrBannerCode = null);
    }

    if (kIsWeb) {
      unawaited(WebNotificationSound.unlock());
      // Dopo Passkey la tab era nascosta: la subscribe push può essere fallita.
      // Forza re-bind endpoint → altrimenti a PWA chiusa non arrivano toast.
      unawaited(WebPushService.ensureRegisteredForCurrentUser(force: true));
    }

    switch (role) {
      case 'dipendente':
      case 'user':
        Navigator.pushNamedAndRemoveUntil(
            context, '/dipendentePrenotazioni', (_) => false);
        break;

      case 'caposquadra':
        Navigator.pushNamedAndRemoveUntil(
            context, '/caposquadraPrenotazioni', (_) => false);
        break;

      case 'ristoratore':
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/ristoratoreHome',
          (_) => false,
          arguments: {
            'id': p['id'],
            'username': p['username'],
            'full_name': p['full_name'],
          },
        );
        break;

      default:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (_) => false,
          arguments: {
            'id': p['id'],
            'username': p['username'],
            'role': p['role'],
            'secondary_role': p['secondary_role'],
            'full_name': p['full_name'],
            'email': p['email'],
          },
        );
    }
  }

  // ---------------------------------------------------
  // LOGIN
  // ---------------------------------------------------
  Future<void> _login() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => error = 'Inserisci email e password');
      return;
    }

    setState(() => loading = true);
    final sb = Supabase.instance.client;

    try {
      final res = await sb.auth.signInWithPassword(
        email: email,
        password: pass,
      );

      if (res.user == null) {
        setState(() => error =
            'Email o password non corretti. Controlla i dati e riprova.');
        return;
      }

      unawaited(AppOpenTracker.touchCurrentUser());
      await _remember(email);

      final p = await sb
          .from('users')
          .select('*')
          .eq('auth_id', res.user!.id)
          .maybeSingle();

      if (p == null) {
        setState(() => error = 'Profilo non trovato');
        return;
      }

      // Pulsante inibito solo se su QUESTO device c’è già Passkey.
      if (PasskeyAuthService.isPlatformSupported) {
        final onDevice =
            await AppDeviceUnlockGate.hasCompletedPasskeyOnThisDevice(
          res.user!.id,
        );
        if (mounted) setState(() => _passkeyOnThisDevice = onDevice);
      }

      await _completeLoginForUser(
        Map<String, dynamic>.from(p),
        enforcePasskeyMfa: true,
        forceDeviceUnlock: true,
      );
    } catch (e) {
      setState(() => error = _loginErrorMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Nuovo dispositivo: email+password → (OTP se già Passkey altrove) → crea qui.
  Future<void> _createPasskeyOnLogin() async {
    if (!PasskeyAuthService.isPlatformSupported || _passkeyOnThisDevice) {
      return;
    }
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text.trim();
    // Pulsante già disabilitato se manca email/password: niente messaggio rosso.
    if (email.isEmpty || pass.isEmpty) return;

    setState(() {
      loading = true;
      error = null;
    });
    final sb = Supabase.instance.client;
    try {
      final res = await sb.auth.signInWithPassword(
        email: email,
        password: pass,
      );
      if (res.user == null) {
        setState(() => error =
            'Email o password non corretti. Controlla i dati e riprova.');
        return;
      }

      final authId = res.user!.id;
      if (await AppDeviceUnlockGate.hasCompletedPasskeyOnThisDevice(authId)) {
        if (mounted) {
          setState(() {
            _passkeyOnThisDevice = true;
            error =
                'Su questo dispositivo la Passkey è già attiva. Usa «Accedi».';
          });
        }
        try {
          await sb.auth.signOut();
        } catch (_) {}
        return;
      }

      // Account già con Passkey altrove → OTP email (opzionale se non disponibile).
      final hasElsewhere = await PasskeyAuthService.hasAnyPasskey();
      if (hasElsewhere) {
        if (!mounted) return;
        setState(() => loading = false);
        final otp = await _confirmEmailOtp(email);
        if (otp == _LoginOtpResult.cancelled) {
          try {
            await sb.auth.signOut();
          } catch (_) {}
          return;
        }
        // ok / continueWithout: password già verificata → crea Passkey qui.
        if (mounted) setState(() => loading = true);
        // Se l’OTP ha sostituito la sessione, assicurati che sia ancora valida.
        if (sb.auth.currentSession == null) {
          final again = await sb.auth.signInWithPassword(
            email: email,
            password: pass,
          );
          if (again.user == null) {
            setState(() => error =
                'Sessione scaduta dopo l’OTP. Riprova con email e password.');
            return;
          }
        }
      }

      final created = await PasskeyAuthService.enrollPasskeyOnThisDevice();
      AppDeviceUnlockGate.markUnlocked();
      await AppDeviceUnlockGate.markPasskeyCompletedOnThisDevice(authId);

      unawaited(AppOpenTracker.touchCurrentUser());
      await _remember(email);

      final p = await sb
          .from('users')
          .select('*')
          .eq('auth_id', authId)
          .maybeSingle();
      if (p == null) {
        setState(() => error = 'Profilo non trovato');
        return;
      }
      if (mounted) {
        setState(() {
          _passkeyOnThisDevice = true;
          if (!created) {
            error =
                'Passkey già presente su questo dispositivo. Accesso in corso…';
          }
        });
      }

      await _completeLoginForUser(
        Map<String, dynamic>.from(p),
        enforcePasskeyMfa: false,
        skipBiometricGate: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AuthException ||
                  e.toString().toLowerCase().contains('passkey') ||
                  e.toString().toLowerCase().contains('webauthn') ||
                  e.toString().toLowerCase().contains('otp')
              ? PasskeyAuthService.userMessage(e)
              : _loginErrorMessage(e);
        });
      }
      try {
        await sb.auth.signOut();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// OTP email per nuovo device. Se l’invio/verifica fallisce → continua con password.
  Future<_LoginOtpResult> _confirmEmailOtp(String email) async {
    final sb = Supabase.instance.client;
    var sendOk = true;
    String? sendErr;
    try {
      await sb.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );
    } catch (e) {
      sendOk = false;
      sendErr = e is AuthException && e.message.trim().isNotEmpty
          ? e.message.trim()
          : _loginErrorMessage(e);
    }
    if (!mounted) return _LoginOtpResult.cancelled;

    // Invio fallito (OTP non attivo su Supabase, rate limit, ecc.): non bloccare.
    if (!sendOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'OTP email non disponibile (${sendErr ?? 'errore'}). '
              'Continuo con password già verificata.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return _LoginOtpResult.continueWithout;
    }

    final codeCtrl = TextEditingController();
    var dialogError = '';
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Codice email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Controlla $email (anche spam).\n'
                    'Serve un codice perché hai già una Passkey su un altro dispositivo.\n'
                    'Se non arriva il codice, puoi continuare solo con la password.',
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Codice OTP',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogError,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, '__cancel__'),
                  child: const Text('Annulla'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, '__skip__'),
                  child: const Text('Continua senza OTP'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await sb.auth.signInWithOtp(
                        email: email,
                        shouldCreateUser: false,
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Codice reinviato')),
                        );
                      }
                    } catch (e) {
                      setLocal(() {
                        dialogError = e is AuthException &&
                                e.message.trim().isNotEmpty
                            ? e.message.trim()
                            : 'Reinvio non riuscito';
                      });
                    }
                  },
                  child: const Text('Reinvia'),
                ),
                FilledButton(
                  onPressed: () async {
                    final token = codeCtrl.text.trim();
                    if (token.isEmpty) {
                      setLocal(() => dialogError = 'Inserisci il codice');
                      return;
                    }
                    try {
                      AuthResponse? verified;
                      try {
                        verified = await sb.auth.verifyOTP(
                          email: email,
                          token: token,
                          type: OtpType.email,
                        );
                      } catch (_) {
                        verified = await sb.auth.verifyOTP(
                          email: email,
                          token: token,
                          type: OtpType.magiclink,
                        );
                      }
                      if (verified.session != null || verified.user != null) {
                        if (ctx.mounted) Navigator.pop(ctx, '__ok__');
                      } else {
                        setLocal(() => dialogError = 'Codice non valido');
                      }
                    } catch (e) {
                      setLocal(() {
                        dialogError = e is AuthException &&
                                e.message.trim().isNotEmpty
                            ? e.message.trim()
                            : 'Codice non valido o scaduto';
                      });
                    }
                  },
                  child: const Text('Conferma'),
                ),
              ],
            );
          },
        );
      },
    );
    codeCtrl.dispose();

    if (choice == null || choice == '__cancel__') {
      return _LoginOtpResult.cancelled;
    }
    if (choice == '__skip__') return _LoginOtpResult.continueWithout;
    if (choice == '__ok__') return _LoginOtpResult.ok;
    return _LoginOtpResult.continueWithout;
  }

  Future<void> _loginWithPasskey() async {
    if (!PasskeyAuthService.showPasskeyLoginButton) {
      setState(() => error =
          'Su telefono usa «Accedi» con password: l’impronta verrà '
          'richiesta subito dopo.');
      return;
    }
    if (!PasskeyAuthService.isPlatformSupported) {
      setState(() => error = PasskeyAuthService.unsupportedPlatformMessage);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final sb = Supabase.instance.client;
    try {
      final hint = await PasskeyAuthService.availabilityHint();
      if (PasskeyAuthService.isBlockingAvailabilityHint(hint)) {
        if (!mounted) return;
        setState(() => error = hint);
        return;
      }

      final res = await PasskeyAuthService.signIn();
      if (res.user == null) {
        setState(() => error = 'Accesso con Passkey non riuscito.');
        return;
      }

      unawaited(AppOpenTracker.touchCurrentUser());
      final email = (res.user!.email ?? '').trim();
      if (email.isNotEmpty) await _remember(email);

      final p = await sb
          .from('users')
          .select('*')
          .eq('auth_id', res.user!.id)
          .maybeSingle();

      if (p == null) {
        setState(() => error = 'Profilo non trovato');
        return;
      }

      // Passkey è già il fattore forte: niente secondo step.
      await _completeLoginForUser(
        Map<String, dynamic>.from(p),
        enforcePasskeyMfa: false,
        skipBiometricGate: true,
      );
    } catch (e) {
      setState(() => error = PasskeyAuthService.userMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Passkey ibrida Windows: QR di sistema «Usa un telefono», non Hello locale.
  Future<void> _loginWithPasskeyPhone() async {
    if (!kIsWeb || isMobileWebPlatform()) return;
    if (!PasskeyAuthService.isPlatformSupported) {
      setState(() => error = PasskeyAuthService.unsupportedPlatformMessage);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final sb = Supabase.instance.client;
    try {
      final res = await PasskeyAuthService.signIn(preferPhone: true);
      if (res.user == null) {
        setState(() => error = 'Accesso con Passkey non riuscito.');
        return;
      }

      unawaited(AppOpenTracker.touchCurrentUser());
      final email = (res.user!.email ?? '').trim();
      if (email.isNotEmpty) await _remember(email);

      final p = await sb
          .from('users')
          .select('*')
          .eq('auth_id', res.user!.id)
          .maybeSingle();

      if (p == null) {
        setState(() => error = 'Profilo non trovato');
        return;
      }

      await _completeLoginForUser(
        Map<String, dynamic>.from(p),
        enforcePasskeyMfa: false,
        skipBiometricGate: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = PasskeyAuthService.userMessage(e));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Bypass Windows USB: QR sul telefono + impronta cellulare.
  Future<void> _loginWithPhoneQr() async {
    if (!kIsWeb || isMobileWebPlatform()) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final ok = await showAuthQrLoginDialog(context);
      if (!ok || !mounted) return;
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => error = 'Sessione QR non ricevuta. Riprova.');
        return;
      }
      unawaited(AppOpenTracker.touchCurrentUser());
      final p = await Supabase.instance.client
          .from('users')
          .select('*')
          .eq('auth_id', user.id)
          .maybeSingle();
      if (p == null) {
        setState(() => error = 'Profilo non trovato');
        return;
      }
      await _completeLoginForUser(
        Map<String, dynamic>.from(p),
        enforcePasskeyMfa: false,
        skipBiometricGate: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = PasskeyAuthService.userMessage(e));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------------------------------------------------
  // RESET PASSWORD VIA EMAIL
  // ---------------------------------------------------
  String _recoveryRedirectTo() {
    if (kIsWeb) {
      // Solo fallback (funzione non pubblicata): dominio canonico fisso,
      // mai l'origin corrente (anteprime/pages.dev/ore).
      return 'https://gestopro360.it/password-recovery';
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
      return 'myapp://auth-callback';
    }
    return 'myapp://auth-callback';
  }

  Future<void> _resetPassword() async {
    if (resetting) return;
    final now = DateTime.now();
    if (_lastForgotPasswordRequest != null &&
        now.difference(_lastForgotPasswordRequest!) <
            const Duration(seconds: 2)) {
      setState(() => error = 'Attendi un momento prima di riprovare.');
      return;
    }
    final cooldownEmail = (_resetCooldownEmail ?? '').trim().toLowerCase();
    final currentEmail = emailCtrl.text.trim().toLowerCase();
    if (resetCooldownSec > 0 &&
        cooldownEmail.isNotEmpty &&
        cooldownEmail == currentEmail) {
      setState(() => error = "Attendi $resetCooldownSec secondi prima di riprovare.");
      return;
    }
    if (resetCooldownSec > 0 &&
        cooldownEmail.isNotEmpty &&
        cooldownEmail != currentEmail) {
      _resetCooldownTimer?.cancel();
      setState(() {
        resetCooldownSec = 0;
        _resetCooldownEmail = null;
      });
    }
    final email = emailCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => error = "Inserisci l'email per il reset");
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email)) {
      setState(() => error = 'Inserisci un indirizzo email valido');
      return;
    }

    // Messaggio SEMPRE identico: non rivela se l'email è registrata,
    // né dettagli tecnici (redirect, rate limit, errori server).
    const genericMsg =
        "Se l'indirizzo è registrato riceverai a breve un'email con il link "
        "per impostare una nuova password (controlla anche lo spam). "
        "Il link vale 60 minuti e si può usare una sola volta.";
    try {
      PasswordRecoveryGate.allowNewRecovery();
      setState(() {
        resetting = true;
        error = null;
      });
      _lastForgotPasswordRequest = DateTime.now();
      try {
        // Il redirect è deciso dal server (allow-list fissa): non lo inviamo.
        await Supabase.instance.client.functions.invoke(
          'request-password-reset',
          body: {'email': email},
        );
      } on FunctionException catch (fe) {
        if (fe.status == 404) {
          await Supabase.instance.client.auth.resetPasswordForEmail(
            email,
            redirectTo: _recoveryRedirectTo(),
          );
        } else {
          rethrow;
        }
      }
    } catch (e) {
      // Solo log: all'utente lo stesso messaggio generico.
      debugPrint('request-password-reset: $e');
    } finally {
      if (mounted) {
        _startResetCooldown(60, email);
        setState(() {
          resetting = false;
          error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(genericMsg),
            duration: Duration(seconds: 10),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------
  // AUTO LOGIN
  // ---------------------------------------------------
  Future<void> _tryAutoLogin() async {
    if (rememberMe == false) return;
    if (PasswordRecoveryGate.shouldOpenResetPage) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final sb = Supabase.instance.client;

    final p = await sb
        .from("users")
        .select("*")
        .eq("auth_id", session.user.id)
        .maybeSingle();

    if (p == null) return;
    if (p["must_change_password"] == true) return;

    // Auto-login: su mobile il gate dispositivo è sempre in _completeLoginForUser.
    await _completeLoginForUser(
      Map<String, dynamic>.from(p),
      enforcePasskeyMfa: false,
    );
  }

  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final topBar = AppBrandingService.instance.topBarColor;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: topBar,
            foregroundColor: Colors.white,
            title: const ResponsiveAppBarTitle(
              title: 'Accedi',
              desktopLogoSize: 44,
              mobileLogoSize: 28,
              lightOnDark: true,
              showBrandAndClock: false,
            ),
          ),
          body: PageWithTopLogo(
            logoSize: 120,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: cronosPageHorizontalPadding(context),
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cronosAdaptiveValue(
                            context: context,
                            phone: 400,
                            tablet: 420,
                            desktop: 440,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_authQrBannerCode != null) ...[
                              Material(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.qr_code_2,
                                        color: Color(0xFF1565C0),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Conferma accesso sul PC\n'
                                          'Codice ${_authQrBannerCode!}. '
                                          'Accedi qui (impronta) per autorizzare il computer.',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: emailCtrl,
                              onChanged: (_) => setState(() {
                                _passkeyOnThisDevice = false;
                                if (error != null) error = null;
                              }),
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: passCtrl,
                              obscureText: obscure,
                              onChanged: (_) => setState(() {
                                if (error != null) error = null;
                              }),
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off),
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                ),
                              ),
                            ),
                            CheckboxListTile(
                              value: rememberMe,
                              activeColor:
                                  AppBrandingService.instance.accentColor,
                              onChanged: (v) =>
                                  setState(() => rememberMe = v ?? true),
                              dense: true,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: const Text('Rimani connesso'),
                            ),
                            if (error != null)
                              Text(error!,
                                  style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: NeoFilledButton(
                                onTap: loading ? null : _login,
                                child: loading
                                    ? const Center(
                                        child: SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Center(child: Text('Accedi')),
                              ),
                            ),
                            if (PasskeyAuthService.isPlatformSupported) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: NeoButton(
                                  onTap: (loading ||
                                          _passkeyOnThisDevice ||
                                          emailCtrl.text.trim().isEmpty ||
                                          passCtrl.text.trim().isEmpty)
                                      ? null
                                      : _createPasskeyOnLogin,
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _passkeyOnThisDevice
                                              ? Icons.verified
                                              : Icons.fingerprint,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _passkeyOnThisDevice
                                              ? 'Passkey già su questo dispositivo'
                                              : 'Crea Passkey su questo dispositivo',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _passkeyOnThisDevice
                                    ? 'Su questo dispositivo la Passkey è già attiva: usa «Accedi».'
                                    : 'Compila email e password, poi tocca il pulsante. '
                                        'Se hai già Passkey su un altro device, '
                                        'ti chiediamo anche un codice OTP via email.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CronosAppThemes.mutedOf(context),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (PasskeyAuthService.isPlatformSupported &&
                                !PasskeyAuthService.showPasskeyLoginButton) ...[
                              const SizedBox(height: 8),
                              Text(
                                AppDeviceUnlockGate.remembersUnlockAfterFirstTime
                                    ? 'La prima volta su questo telefono verrà '
                                        'chiesta l’impronta (Passkey). '
                                        'Ai prossimi accessi da qui non verrà '
                                        'più richiesta.'
                                    : 'Dopo «Accedi» verrà chiesta in automatico '
                                        'l’impronta o Face ID per questo telefono.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CronosAppThemes.mutedOf(context),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            if (PasskeyAuthService.showPasskeyLoginButton) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: NeoButton(
                                  onTap: loading ? null : _loginWithPasskey,
                                  child: const Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fingerprint, size: 20),
                                        SizedBox(width: 8),
                                        Text('Accedi con Passkey'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (kIsWeb && !isMobileWebPlatform()) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: NeoButton(
                                    onTap: loading
                                        ? null
                                        : _loginWithPasskeyPhone,
                                    child: const Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.phone_iphone, size: 20),
                                          SizedBox(width: 8),
                                          Text('Accedi con Passkey sul telefono'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: NeoButton(
                                    onTap: loading ? null : _loginWithPhoneQr,
                                    child: const Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.qr_code_2, size: 20),
                                          SizedBox(width: 8),
                                          Text('Accedi con QR telefono'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Non usare «Gestione password Microsoft»: '
                                  'non è la Passkey CRONOS. '
                                  'Usa «Passkey sul telefono» o il QR. '
                                  'Oppure accedi con password: verrà '
                                  'attivato Windows Hello su questo PC.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CronosAppThemes.mutedOf(context),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 8),
                            NeoButton(
                              onTap: (loading ||
                                      resetting ||
                                      _forgotPasswordCooldownBlocksTap())
                                  ? null
                                  : _resetPassword,
                              child: resetting
                                  ? const Center(
                                      child: SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        _forgotPasswordCooldownBlocksTap()
                                            ? 'Attendi ${resetCooldownSec}s…'
                                            : 'Password dimenticata?',
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            NeoButton(
                              onTap: loading || resetting
                                  ? null
                                  : () {
                                      Navigator.of(context).pushNamed(
                                        '/segnalazione-sicurezza',
                                      );
                                    },
                              child: const Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.report_gmailerrorred_outlined,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Segnalazione sicurezza'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const AppCopyrightFooter(compact: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}