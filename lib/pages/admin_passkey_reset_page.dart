import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/classic_nav_session_cache.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni → Reset Passkey (solo admin generale, protetto da password).
class AdminPasskeyResetPage extends StatefulWidget {
  const AdminPasskeyResetPage({super.key});

  @override
  State<AdminPasskeyResetPage> createState() => _AdminPasskeyResetPageState();
}

class _AdminPasskeyResetPageState extends State<AdminPasskeyResetPage> {
  bool _unlocked = false;
  bool _loadingUsers = false;
  bool _busy = false;
  String _query = '';
  String? _error;
  List<_UserRow> _users = const [];

  bool get _isAdminGenerale {
    final role = ClassicNavSessionCache.current?.role ?? '';
    return isAdminGeneraleLikeRole(role);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isAdminGenerale) return;
      unawaited(_askUnlock());
    });
  }

  Future<void> _askUnlock() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PasswordGateDialog(),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() => _unlocked = true);
      await _loadUsers();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('id, id_uuid, auth_id, full_name, username, email, role')
          .not('auth_id', 'is', null)
          .order('full_name', ascending: true)
          .limit(2000);
      final list = <_UserRow>[];
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final authId = (m['auth_id'] ?? '').toString().trim();
        if (authId.isEmpty) continue;
        list.add(_UserRow.fromMap(m));
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _error = '$e';
      });
    }
  }

  List<_UserRow> get _filtered {
    final k = _query.trim().toLowerCase();
    if (k.isEmpty) return _users;
    return _users.where((u) {
      return u.displayName.toLowerCase().contains(k) ||
          u.email.toLowerCase().contains(k) ||
          u.username.toLowerCase().contains(k) ||
          u.role.toLowerCase().contains(k);
    }).toList(growable: false);
  }

  Future<String?> _askConfirmPassword({required String title}) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _ConfirmPasswordDialog(title: title),
    );
  }

  Future<void> _inspect(_UserRow user) async {
    final pw = await _askConfirmPassword(
      title: 'Conferma password per vedere le Passkey di ${user.displayName}',
    );
    if (pw == null || pw.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-reset-passkeys',
        body: {
          'action': 'list_passkeys',
          'auth_id': user.authId,
          'confirm_password': pw,
        },
      );
      final data = res.data;
      if (res.status != 200 || data is! Map) {
        throw StateError(
          (data is Map ? data['error'] : null)?.toString() ??
              'Errore elenco Passkey (${res.status})',
        );
      }
      if (data['error'] != null) {
        throw StateError(data['error'].toString());
      }
      final count = (data['count'] as num?)?.toInt() ?? 0;
      final passkeys = (data['passkeys'] as List?) ?? const [];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(user.displayName),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? 'Nessuna Passkey registrata su questo account.'
                      : '$count Passkey sul server Auth:',
                ),
                const SizedBox(height: 10),
                if (count > 0)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: passkeys.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final pk = Map<String, dynamic>.from(
                          passkeys[i] as Map,
                        );
                        final name = (pk['friendly_name'] ?? 'Passkey')
                            .toString();
                        final created = (pk['created_at'] ?? '').toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.key_outlined),
                          title: Text(name),
                          subtitle: created.isEmpty ? null : Text(created),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
            if (count > 0)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_reset(user));
                },
                child: const Text('Reset Passkey'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset(_UserRow user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Passkey'),
        content: Text(
          'Eliminare tutte le Passkey di «${user.displayName}»?\n\n'
          'Al prossimo accesso dovrà creare la Passkey da zero '
          '(dopo login con password).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final pw = await _askConfirmPassword(
      title: 'Digita la tua password admin per confermare il reset',
    );
    if (pw == null || pw.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-reset-passkeys',
        body: {
          'action': 'reset_passkeys',
          'auth_id': user.authId,
          'confirm_password': pw,
        },
      );
      final data = res.data;
      if (res.status != 200 || data is! Map) {
        throw StateError(
          (data is Map ? data['error'] : null)?.toString() ??
              'Reset fallito (${res.status})',
        );
      }
      if (data['error'] != null) {
        throw StateError(data['error'].toString());
      }
      final deleted = (data['deleted'] as num?)?.toInt() ?? 0;
      final found = (data['found'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ModifyFeedback.hint(
        context,
        found == 0
            ? 'Nessuna Passkey da eliminare.'
            : 'Reset ok: eliminate $deleted di $found.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminGenerale) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(
          context,
          AppBar(
            title: const ResponsiveAppBarTitle(title: 'Reset Passkey'),
          ),
        ),
        body: const Center(
          child: Text('Solo admin generale può usare questa pagina.'),
        ),
      );
    }

    if (!_unlocked) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(
          context,
          AppBar(
            title: const ResponsiveAppBarTitle(title: 'Reset Passkey'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rows = _filtered;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Reset Passkey'),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loadingUsers || _busy ? null : _loadUsers,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Elimina le Passkey lato server per un utente con problemi di accesso. '
              'Poi dovrà rientrare con password e crearne una nuova sul telefono.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Cerca nome, email, ruolo…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loadingUsers
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const Center(child: Text('Nessun utente trovato.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final u = rows[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  u.initials,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              title: Text(u.displayName),
                              subtitle: Text(
                                [
                                  if (u.email.isNotEmpty) u.email,
                                  if (u.role.isNotEmpty) u.role,
                                ].join(' · '),
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Vedi Passkey',
                                    onPressed: _busy ? null : () => _inspect(u),
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Reset Passkey',
                                    onPressed: _busy ? null : () => _reset(u),
                                    icon: const Icon(Icons.key_off_outlined),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserRow {
  final String authId;
  final String displayName;
  final String email;
  final String username;
  final String role;

  const _UserRow({
    required this.authId,
    required this.displayName,
    required this.email,
    required this.username,
    required this.role,
  });

  factory _UserRow.fromMap(Map<String, dynamic> m) {
    final full = (m['full_name'] ?? '').toString().trim();
    final user = (m['username'] ?? '').toString().trim();
    final email = (m['email'] ?? '').toString().trim();
    return _UserRow(
      authId: (m['auth_id'] ?? '').toString().trim(),
      displayName: full.isNotEmpty
          ? full
          : (user.isNotEmpty ? user : (email.isNotEmpty ? email : 'Utente')),
      email: email,
      username: user,
      role: (m['role'] ?? '').toString().trim(),
    );
  }

  String get initials {
    final parts = displayName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final chars = parts.take(2).map((e) => e[0].toUpperCase()).join();
    return chars.isEmpty ? '?' : chars;
  }
}

class _PasswordGateDialog extends StatefulWidget {
  const _PasswordGateDialog();

  @override
  State<_PasswordGateDialog> createState() => _PasswordGateDialogState();
}

class _PasswordGateDialogState extends State<_PasswordGateDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _ctrl.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Inserisci la password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email =
          (Supabase.instance.client.auth.currentUser?.email ?? '').trim();
      if (email.isEmpty) {
        throw StateError('Sessione senza email');
      }
      final res = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: pw);
      if (res.user == null) {
        throw StateError('Password non corretta');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _busy = false;
        _error = msg.contains('invalid') || msg.contains('password')
            ? 'Password non corretta'
            : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Accesso protetto'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Solo admin generale. Digita la tua password per aprire '
              'il reset Passkey.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'La tua password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sblocca'),
        ),
      ],
    );
  }
}

class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({required this.title});
  final String title;

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        obscureText: _obscure,
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text),
        decoration: InputDecoration(
          labelText: 'Password admin',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Conferma'),
        ),
      ],
    );
  }
}
