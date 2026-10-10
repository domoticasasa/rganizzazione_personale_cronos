// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/passkey_auth_service.dart';
import '../services/password_recovery_gate.dart';
import '../utils/password_policy.dart';
import '../utils/auth_callback_bootstrap_stub.dart'
    if (dart.library.html) '../utils/auth_callback_bootstrap_web.dart';
import '../widgets/app_logo.dart';
import 'login_page.dart';

class ChangePasswordResetPage extends StatefulWidget {
  const ChangePasswordResetPage({super.key});

  @override
  State<ChangePasswordResetPage> createState() =>
      _ChangePasswordResetPageState();
}

class _ChangePasswordResetPageState extends State<ChangePasswordResetPage> {
  final pw1 = TextEditingController();
  final pw2 = TextEditingController();
  bool loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _centerMessage;
  bool _centerIsError = true;

  /// Solo da link di recupero: una sessione normale NON basta.
  bool get _canSetPassword =>
      PasswordRecoveryGate.isRecoverySessionVerified ||
      PasswordRecoveryGate.hasUnverifiedToken;

  @override
  void initState() {
    super.initState();
    // Il token resta solo in memoria (PasswordRecoveryGate): lo togliamo
    // subito da URL, cronologia e sessionStorage.
    stripAuthQueryFromUrl();
    clearStoredAuthCallback();
  }

  @override
  void dispose() {
    pw1.dispose();
    pw2.dispose();
    super.dispose();
  }

  void _showCenter(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _centerMessage = message;
      _centerIsError = error;
    });
  }

  String _italianAuthError(Object e) {
    final auth = e is AuthException ? e : null;
    final code = (auth?.code ?? '').toLowerCase();
    final raw = '${auth?.message ?? ''} $e'.toLowerCase();
    if (code == 'same_password' ||
        raw.contains('same_password') ||
        raw.contains('different from the old password')) {
      return 'La nuova password deve essere diversa da quella attuale.';
    }
    if (raw.contains('expired') ||
        raw.contains('otp') ||
        raw.contains('token') && raw.contains('invalid')) {
      return 'Il link di recupero non è più valido. Richiedi un nuovo reset.';
    }
    if (raw.contains('weak') ||
        raw.contains('least') ||
        raw.contains('characters') ||
        raw.contains('too short')) {
      return 'La password non è abbastanza sicura. ${PasswordPolicy.rulesText}';
    }
    return 'Non è stato possibile aggiornare la password. Riprova.';
  }

  Future<void> _save() async {
    // Nessun trim silenzioso: la password è esattamente quella digitata.
    final t1 = pw1.text;
    final t2 = pw2.text;

    if (t1.isEmpty || t2.isEmpty) {
      _showCenter('Compila entrambi i campi');
      return;
    }
    final ruleError = PasswordPolicy.validate(
      t1,
      email: Supabase.instance.client.auth.currentUser?.email,
    );
    if (ruleError != null) {
      _showCenter(ruleError);
      return;
    }
    if (t1 != t2) {
      _showCenter('Le password non coincidono');
      return;
    }

    setState(() {
      loading = true;
      _centerMessage = null;
    });

    try {
      if (!PasswordRecoveryGate.isRecoverySessionVerified) {
        final ok =
            await PasswordRecoveryGate.verifyTokenHashIfPresent(Uri.base);
        if (!ok || Supabase.instance.client.auth.currentSession == null) {
          _showCenter(
            'Link scaduto o già usato. Torna al login e richiedi un nuovo reset.',
          );
          return;
        }
      }

      final sb = Supabase.instance.client;
      await sb.auth.updateUser(UserAttributes(password: t1));

      // Notifica "password cambiata" (best-effort: se la funzione non è
      // ancora pubblicata non blocca il flusso).
      try {
        await sb.functions.invoke('notify-password-changed');
      } catch (_) {}

      // Mostra le Passkey dell'account con possibilità di revoca.
      if (mounted) await _reviewPasskeys();

      PasswordRecoveryGate.markCompleted();
      clearStoredAuthCallback();
      // Chiude TUTTE le sessioni (anche su altri dispositivi).
      try {
        await sb.auth.signOut(scope: SignOutScope.global);
      } catch (_) {
        try {
          await sb.auth.signOut(scope: SignOutScope.local);
        } catch (_) {}
      }
      if (!mounted) return;
      _showCenter(
          'Password aggiornata. Tutti i dispositivi sono stati disconnessi: '
          'accedi con la nuova password.',
          error: false);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/login'),
          builder: (_) => const LoginPage(),
        ),
        (_) => false,
      );
    } catch (e) {
      debugPrint('ChangePasswordResetPage._save: $e');
      _showCenter(_italianAuthError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Dopo il reset: elenco Passkey con revoca (se il reset non l'hai fatto tu
  /// o una Passkey non è più tua, rimuovila).
  Future<void> _reviewPasskeys() async {
    if (!PasskeyAuthService.isPlatformSupported) return;
    List<Passkey> items;
    try {
      items = await PasskeyAuthService.list();
    } catch (e) {
      debugPrint('reviewPasskeys list: $e');
      return;
    }
    if (items.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var list = List<Passkey>.from(items);
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Controlla le tue Passkey'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Queste Passkey possono ancora accedere al tuo account. '
                    'Rimuovi quelle che non riconosci o che non usi più.',
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty) const Text('Nessuna Passkey rimasta.'),
                  for (final p in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.key),
                      title: Text((p.friendlyName ?? '').trim().isEmpty
                          ? 'Passkey'
                          : p.friendlyName!.trim()),
                      subtitle: Text(
                          'Creata il ${MaterialLocalizations.of(ctx).formatShortDate(p.createdAt.toLocal())}'),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await PasskeyAuthService.delete(p.id);
                            setD(() => list.remove(p));
                          } catch (e) {
                            debugPrint('reviewPasskeys delete: $e');
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Non è stato possibile rimuovere la Passkey. '
                                      'Potrai farlo da Impostazioni → Sicurezza.'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Revoca'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Continua'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _goLogin() {
    PasswordRecoveryGate.dismiss();
    clearStoredAuthCallback();
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ResponsiveAppBarTitle(title: "Imposta nuova password"),
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: 'Torna al login',
          onPressed: _goLogin,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_canSetPassword) ...[
                      const Text(
                        'Il link di recupero non è più valido o è già stato usato.\n\n'
                        'Torna al login e premi di nuovo «Password dimenticata?».\n'
                        'Apri il link nuovo nel browser, senza premere «Apri nell’app».',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _goLogin,
                        child: const Text('Torna al login'),
                      ),
                    ] else ...[
                      const Text(
                        'Scegli una nuova password, poi premi Salva.\n'
                        '${PasswordPolicy.rulesText}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: pw1,
                        obscureText: _obscure1,
                        decoration: InputDecoration(
                          labelText: "Nuova password",
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure1
                                ? 'Mostra password'
                                : 'Nascondi password',
                            icon: Icon(_obscure1
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure1 = !_obscure1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pw2,
                        obscureText: _obscure2,
                        decoration: InputDecoration(
                          labelText: "Conferma password",
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure2
                                ? 'Mostra password'
                                : 'Nascondi password',
                            icon: Icon(_obscure2
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure2 = !_obscure2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: loading ? null : _save,
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text("Salva"),
                      ),
                      if (_centerMessage != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _centerMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _centerIsError
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF1B5E20),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
