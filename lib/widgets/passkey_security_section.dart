// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_device_unlock_gate.dart';
import '../services/passkey_auth_service.dart';
import '../utils/modify_feedback.dart';

/// Gestione Passkeys (WebAuthn / biometria) per l'utente autenticato.
class PasskeySecuritySection extends StatefulWidget {
  const PasskeySecuritySection({super.key});

  @override
  State<PasskeySecuritySection> createState() => _PasskeySecuritySectionState();
}

class _PasskeySecuritySectionState extends State<PasskeySecuritySection> {
  bool _loading = true;
  bool _busy = false;
  bool _onThisDevice = false;
  List<Passkey> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!PasskeyAuthService.isPlatformSupported) {
        setState(() {
          _items = const [];
          _error = PasskeyAuthService.unsupportedPlatformMessage;
          _loading = false;
        });
        return;
      }
      final items = await PasskeyAuthService.list();
      final authId =
          (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
      final onDevice = authId.isEmpty
          ? false
          : await AppDeviceUnlockGate.hasCompletedPasskeyOnThisDevice(authId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _onThisDevice = onDevice;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = PasskeyAuthService.userMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _forceCreate() async {
    if (_busy || _onThisDevice) return;
    setState(() => _busy = true);
    try {
      final created = await PasskeyAuthService.enrollPasskeyOnThisDevice();
      final authId =
          (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
      if (authId.isNotEmpty) {
        await AppDeviceUnlockGate.markPasskeyCompletedOnThisDevice(authId);
      }
      if (!mounted) return;
      ModifyFeedback.success(
        context,
        created
            ? 'Passkey creata su questo dispositivo.'
            : 'Passkey già attiva su questo dispositivo.',
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, PasskeyAuthService.userMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Passkey p) async {
    final label = _labelOf(p);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi Passkey'),
        content: Text('Rimuovere «$label»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await PasskeyAuthService.delete(p.id);
      if (!mounted) return;
      ModifyFeedback.success(context, 'Passkey rimossa.');
      await _reload();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, PasskeyAuthService.userMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _labelOf(Passkey p) {
    final n = (p.friendlyName ?? '').trim();
    return n.isEmpty ? 'Passkey' : n;
  }

  String _createdOf(Passkey p) {
    final l = p.createdAt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fingerprint, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Passkey / MFA (WebAuthn)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Aggiorna',
                  onPressed:
                      _busy || _loading ? null : () => unawaited(_reload()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Puoi avere una Passkey per ogni dispositivo. '
              'Qui crei/verifichi quella di QUESTO device con '
              '${PasskeyAuthService.systemUnlockLabel}. '
              'Se su questo dispositivo è già attiva, il pulsante resta disattivato. '
              'RP: gestopro360.it',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, height: 1.35),
              )
            else if (_items.isEmpty)
              Text(
                'Nessuna Passkey registrata su questo account.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ..._items.map((p) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    _labelOf(p),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Creata: ${_createdOf(p)}'),
                  trailing: IconButton(
                    tooltip: 'Rimuovi',
                    onPressed: _busy ? null : () => unawaited(_delete(p)),
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  ),
                );
              }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (!PasskeyAuthService.isPlatformSupported ||
                      _busy ||
                      _onThisDevice)
                  ? null
                  : () => unawaited(_forceCreate()),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fingerprint),
              label: Text(
                _onThisDevice
                    ? 'Passkey già su questo dispositivo'
                    : 'Crea Passkey su questo dispositivo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner home: visibile solo se manca la Passkey. Stesso pulsante di forzatura.
class PasskeyForceSetupBanner extends StatefulWidget {
  const PasskeyForceSetupBanner({super.key});

  @override
  State<PasskeyForceSetupBanner> createState() => _PasskeyForceSetupBannerState();
}

class _PasskeyForceSetupBannerState extends State<PasskeyForceSetupBanner> {
  bool _loading = true;
  bool _busy = false;
  bool _hasPasskey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    if (!PasskeyAuthService.isPlatformSupported) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasPasskey = true;
        });
      }
      return;
    }
    try {
      final authId =
          (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
      final onDevice = authId.isEmpty
          ? false
          : await AppDeviceUnlockGate.hasCompletedPasskeyOnThisDevice(authId);
      if (!mounted) return;
      setState(() {
        _hasPasskey = onDevice;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPasskey = false;
        _loading = false;
      });
    }
  }

  Future<void> _force() async {
    if (_busy || _hasPasskey) return;
    setState(() => _busy = true);
    try {
      final created = await PasskeyAuthService.enrollPasskeyOnThisDevice();
      final authId =
          (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
      if (authId.isNotEmpty) {
        await AppDeviceUnlockGate.markPasskeyCompletedOnThisDevice(authId);
      }
      if (!mounted) return;
      setState(() => _hasPasskey = true);
      ModifyFeedback.success(
        context,
        created
            ? 'Passkey creata su questo dispositivo.'
            : 'Passkey già attiva su questo dispositivo.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = PasskeyAuthService.userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _hasPasskey) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Passkey mancante su questo dispositivo',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Puoi usarla anche se ne hai già una su un altro telefono/PC. '
                'Tocca per crearla qui con ${PasskeyAuthService.systemUnlockLabel}.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : () => unawaited(_force()),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: const Text('Crea e verifica Passkey'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
