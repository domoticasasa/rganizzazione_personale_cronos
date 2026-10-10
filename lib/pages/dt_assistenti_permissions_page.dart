import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';

import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

class DtAssistentiPermissionsPage extends StatefulWidget {
  final String fullName;

  const DtAssistentiPermissionsPage({
    super.key,
    required this.fullName,
  });

  @override
  State<DtAssistentiPermissionsPage> createState() =>
      _DtAssistentiPermissionsPageState();
}

class _DtAssistentiPermissionsPageState
    extends State<DtAssistentiPermissionsPage> {
  bool _loading = true;
  bool _busy = false;
  bool _canManage = false;

  int? _currentUserId; // users.id del profilo loggato
  String _currentRole = '';
  String? _dtUserUuid; // users.id_uuid
  String _dtDisplayName = '';

  final List<Map<String, dynamic>> _assistants = [];
  final Map<int, bool> _allowed = {}; // assistant_user_id -> allowed

  int _compareAssistantsByLabel(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final al = ((a['full_name'] ?? a['username'] ?? '') as Object)
        .toString()
        .trim()
        .toLowerCase();
    final bl = ((b['full_name'] ?? b['username'] ?? '') as Object)
        .toString()
        .trim()
        .toLowerCase();
    return al.compareTo(bl);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final session = SupabaseService.client.auth.currentSession;
      final authId = session?.user.id;
      if (authId == null || authId.isEmpty) {
        throw Exception('Sessione non valida');
      }

      final me = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, full_name, username, role')
          .eq('auth_id', authId)
          .maybeSingle();

      final roleRaw = (me?['role'] ?? '').toString().trim();
      final role = roleRaw.toLowerCase();
      _currentRole = roleRaw;
      _canManage = role == 'dt';
      _currentUserId = me?['id'] as int?;
      _dtUserUuid = (me?['id_uuid'] ?? '').toString().trim();
      final meName = (me?['full_name'] ?? me?['username'] ?? '')
          .toString()
          .trim();
      _dtDisplayName = meName.isNotEmpty ? meName : widget.fullName;

      final assistantsRes = await SupabaseService.client
          .from('users')
          .select('id, full_name, username, id_uuid, active, role')
          .eq('role', 'assistente_dt')
          .eq('active', true)
          .order('full_name');

      final assistants = assistantsRes as List;
      _assistants
        ..clear()
        ..addAll(assistants.map((e) => e as Map<String, dynamic>))
        ..sort(_compareAssistantsByLabel);

      // Carica permessi esistenti
      final permsRes = await SupabaseService.client
          .from('assistente_dt_permissions')
          .select('assistant_user_id')
          .eq('grantor_dt_user_id', _currentUserId ?? -1);

      final perms = permsRes as List;
      final allowedSet = <int>{};
      for (final p in perms) {
        final v = (p['assistant_user_id']);
        if (v is int) allowedSet.add(v);
        final v2 = int.tryParse(v.toString());
        if (v2 != null) allowedSet.add(v2);
      }

      _allowed
        ..clear()
        ..addAll({
          for (final a in _assistants)
            (a['id'] as int): allowedSet.contains(a['id'] as int)
        });
    } catch (e) {
      // Se tabella permessi non esiste ancora, mostriamo comunque la lista assistenti.
      // (Il permesso verrà gestito correttamente solo dopo db push.)
      _toast('Permessi non caricati: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setPermission(int assistantUserId, bool enable) async {
    if (_busy) return;
    if (!_canManage) {
      _toast('Solo un account DT puo modificare questi permessi.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_currentUserId == null || _dtUserUuid == null || _dtUserUuid!.isEmpty) {
        setState(() => _busy = false);
        return;
      }

      if (enable) {
        // Insert idempotente gestito dal UNIQUE
        await SupabaseService.client
            .from('assistente_dt_permissions')
            .insert({
              'grantor_dt_user_id': _currentUserId,
              'grantor_dt_user_uuid': _dtUserUuid,
              'assistant_user_id': assistantUserId,
            });
      } else {
        await SupabaseService.client
            .from('assistente_dt_permissions')
            .delete()
            .eq('grantor_dt_user_id', _currentUserId ?? -1)
            .eq('assistant_user_id', assistantUserId);
      }
    } catch (e) {
      _toast('Errore aggiornamento permesso: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      await _bootstrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Permessi Assistenti DT',
          desktopLogoSize: 40,
        ),
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'DT: ${_dtDisplayName.isNotEmpty ? _dtDisplayName : widget.fullName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_canManage) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Account non autorizzato (ruolo: ${_currentRole.isEmpty ? 'N/D' : _currentRole}): accesso in sola lettura.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _assistants.isEmpty
                        ? const Center(child: Text('Nessun Assistente DT attivo'))
                        : ListView.separated(
                            itemCount: _assistants.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final a = _assistants[i];
                              final assistantId = a['id'] as int;
                              final label = (a['full_name'] ?? a['username'] ?? '')
                                  .toString()
                                  .trim();
                              final enabled = _allowed[assistantId] ?? false;

                              return SwitchListTile(
                                title: Text(label.isNotEmpty ? label : assistantId.toString()),
                                subtitle: Text('id: $assistantId'),
                                value: enabled,
                                onChanged: _canManage ? (v) async {
                                  await _setPermission(assistantId, v);
                                } : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

