import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_open_tracker.dart';
import '../utils/date_formatters.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni → Accessi app: dipendenti con login e ultima entrata in app.
class AdminAccessiAppPage extends StatefulWidget {
  const AdminAccessiAppPage({super.key});

  @override
  State<AdminAccessiAppPage> createState() => _AdminAccessiAppPageState();
}

enum _AccessFilter { all, entered, never }

class _AdminAccessiAppPageState extends State<AdminAccessiAppPage> {
  bool _loading = true;
  String _query = '';
  _AccessFilter _filter = _AccessFilter.all;
  List<_AccessRow> _rows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<_AccessRow> list;
      try {
        final res =
            await Supabase.instance.client.rpc('admin_list_accessi_app') as List;
        list = [
          for (final raw in res)
            _AccessRow.fromRpc(Map<String, dynamic>.from(raw as Map)),
        ];
      } catch (_) {
        // Fallback se RPC non ancora migrata.
        list = await _loadFromUsersTable();
      }

      list.sort((a, b) {
        final at = a.lastSeenAt;
        final bt = b.lastSeenAt;
        if (at == null && bt == null) {
          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        }
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<_AccessRow>> _loadFromUsersTable() async {
    List res;
    try {
      res = await Supabase.instance.client
          .from('users')
          .select(
            'id, full_name, username, email, role, active, auth_id, last_app_open_at, last_app_open_platform, hidden_from_directory',
          )
          .not('auth_id', 'is', null)
          .order('full_name') as List;
    } catch (_) {
      try {
        res = await Supabase.instance.client
            .from('users')
            .select(
              'id, full_name, username, email, role, active, auth_id, last_app_open_at, last_app_open_platform',
            )
            .not('auth_id', 'is', null)
            .order('full_name') as List;
      } catch (_) {
        res = await Supabase.instance.client
            .from('users')
            .select(
              'id, full_name, username, email, role, active, auth_id, last_app_open_at',
            )
            .not('auth_id', 'is', null)
            .order('full_name') as List;
      }
    }
    return [
      for (final raw in res)
        _AccessRow.fromMap(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  Future<void> _setHiddenFromDirectory(_AccessRow row, bool hidden) async {
    try {
      await Supabase.instance.client.from('users').update({
        'hidden_from_directory': hidden,
      }).eq('id', row.id);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in _rows)
            if (r.id == row.id)
              r.copyWith(hiddenFromDirectory: hidden)
            else
              r,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hidden
                ? '${row.displayName}: nascosto dalle liste app'
                : '${row.displayName}: di nuovo visibile nelle liste',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    }
  }

  List<_AccessRow> get _filtered {
    var list = _rows;
    switch (_filter) {
      case _AccessFilter.entered:
        list = list.where((r) => r.lastSeenAt != null).toList(growable: false);
        break;
      case _AccessFilter.never:
        list = list.where((r) => r.lastSeenAt == null).toList(growable: false);
        break;
      case _AccessFilter.all:
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((r) {
      return r.displayName.toLowerCase().contains(q) ||
          r.username.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.role.toLowerCase().contains(q) ||
          r.roleLabel.toLowerCase().contains(q) ||
          r.platformLabel.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final withOpen = _rows.where((r) => r.lastSeenAt != null).length;
    final never = _rows.length - withOpen;

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Accessi app'),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: PageWithTopLogo(
        showLogo: true,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Utenti con account login (anche se non sono mai entrati). '
                '«Nascosto liste» toglie l’account da chat, selettori e elenchi '
                '(resta comunque qui e login/permessi restano attivi). '
                'La data è l’ultima apertura dell’app (heartbeat), non l’ultima '
                'richiesta biglietti. Se manca, si usa l’ultimo login. '
                '«Canale» indica Web, Android (APK) o Windows dell’ultimo heartbeat.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_rows.length} con login · $withOpen con almeno un accesso · '
                '$never mai entrati',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text('Tutti (${_rows.length})'),
                    selected: _filter == _AccessFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _AccessFilter.all),
                  ),
                  FilterChip(
                    label: Text('Entrati ($withOpen)'),
                    selected: _filter == _AccessFilter.entered,
                    onSelected: (_) =>
                        setState(() => _filter = _AccessFilter.entered),
                  ),
                  FilterChip(
                    label: Text('Mai entrati ($never)'),
                    selected: _filter == _AccessFilter.never,
                    onSelected: (_) =>
                        setState(() => _filter = _AccessFilter.never),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Cerca nome, username, email, ruolo…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(
                      'Errore caricamento: $_error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                const Expanded(
                  child: Center(child: Text('Nessun risultato.')),
                )
              else
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        if (!wide) {
                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final r = filtered[i];
                              return ListTile(
                                title: Text(
                                  r.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${r.roleLabel} · ${r.username.isEmpty ? r.email : r.username}'
                                  '${r.active ? '' : ' · disattivo'}'
                                  '${r.hiddenFromDirectory ? ' · nascosto liste' : ''}\n'
                                  '${r.lastOpenLabel} · ${r.platformLabel}',
                                ),
                                isThreeLine: true,
                                trailing: Switch(
                                  value: r.hiddenFromDirectory,
                                  onChanged: (v) =>
                                      unawaited(_setHiddenFromDirectory(r, v)),
                                ),
                              );
                            },
                          );
                        }
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowHeight: 44,
                                dataRowMinHeight: 40,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Nome')),
                                  DataColumn(label: Text('Username / email')),
                                  DataColumn(label: Text('Ruolo')),
                                  DataColumn(label: Text('Stato')),
                                  DataColumn(label: Text('Nascosto liste')),
                                  DataColumn(label: Text('Canale')),
                                  DataColumn(
                                    label: Text('Ultima entrata'),
                                  ),
                                ],
                                rows: [
                                  for (final r in filtered)
                                    DataRow(
                                      cells: [
                                        DataCell(Text(
                                          r.displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )),
                                        DataCell(Text(
                                          r.username.isNotEmpty
                                              ? r.username
                                              : r.email,
                                        )),
                                        DataCell(Text(r.roleLabel)),
                                        DataCell(Text(
                                          r.active ? 'Attivo' : 'Disattivo',
                                        )),
                                        DataCell(
                                          Switch(
                                            value: r.hiddenFromDirectory,
                                            onChanged: (v) => unawaited(
                                              _setHiddenFromDirectory(r, v),
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(r.platformLabel)),
                                        DataCell(Text(
                                          r.lastOpenLabel,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: r.lastSeenAt == null
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                : null,
                                          ),
                                        )),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessRow {
  _AccessRow({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    required this.role,
    required this.active,
    required this.hiddenFromDirectory,
    required this.lastAppOpenAt,
    required this.lastSignInAt,
    required this.lastSeenAt,
    required this.lastSeenSource,
    required this.lastSeenRaw,
    required this.lastAppOpenPlatform,
  });

  final int id;
  final String displayName;
  final String username;
  final String email;
  final String role;
  final bool active;
  final bool hiddenFromDirectory;
  final DateTime? lastAppOpenAt;
  final DateTime? lastSignInAt;
  final DateTime? lastSeenAt;
  /// `app` | `login` | null
  final String? lastSeenSource;
  final dynamic lastSeenRaw;
  final String lastAppOpenPlatform;

  String get platformLabel => cronosClientPlatformLabel(lastAppOpenPlatform);

  _AccessRow copyWith({bool? hiddenFromDirectory}) {
    return _AccessRow(
      id: id,
      displayName: displayName,
      username: username,
      email: email,
      role: role,
      active: active,
      hiddenFromDirectory: hiddenFromDirectory ?? this.hiddenFromDirectory,
      lastAppOpenAt: lastAppOpenAt,
      lastSignInAt: lastSignInAt,
      lastSeenAt: lastSeenAt,
      lastSeenSource: lastSeenSource,
      lastSeenRaw: lastSeenRaw,
      lastAppOpenPlatform: lastAppOpenPlatform,
    );
  }

  factory _AccessRow.fromRpc(Map<String, dynamic> m) {
    final name = (m['full_name'] ?? '').toString().trim();
    final username = (m['username'] ?? '').toString().trim();
    final email = (m['email'] ?? '').toString().trim();
    final display = name.isNotEmpty
        ? name
        : (username.isNotEmpty
            ? username
            : (email.isNotEmpty ? email : '#${m['id']}'));
    final hiddenRaw = m['hidden_from_directory'];
    final hidden = hiddenRaw is bool
        ? hiddenRaw
        : (hiddenRaw?.toString().trim().toLowerCase() == 'true' ||
            hiddenRaw?.toString().trim() == '1');
    final seenRaw = m['last_seen_at'] ?? m['last_app_open_at'];
    final source = (m['last_seen_source'] ?? '').toString().trim();
    return _AccessRow(
      id: (m['id'] as num?)?.toInt() ?? 0,
      displayName: display,
      username: username,
      email: email,
      role: (m['role'] ?? '').toString().trim(),
      active: m['active'] != false,
      hiddenFromDirectory: hidden,
      lastAppOpenAt: parseSupabaseTimestampToUtc(m['last_app_open_at']),
      lastSignInAt: parseSupabaseTimestampToUtc(m['last_sign_in_at']),
      lastSeenAt: parseSupabaseTimestampToUtc(seenRaw),
      lastSeenSource: source.isEmpty ? null : source,
      lastSeenRaw: seenRaw,
      lastAppOpenPlatform:
          (m['last_app_open_platform'] ?? '').toString().trim(),
    );
  }

  factory _AccessRow.fromMap(Map<String, dynamic> m) {
    final name = (m['full_name'] ?? '').toString().trim();
    final username = (m['username'] ?? '').toString().trim();
    final email = (m['email'] ?? '').toString().trim();
    final display = name.isNotEmpty
        ? name
        : (username.isNotEmpty
            ? username
            : (email.isNotEmpty ? email : '#${m['id']}'));
    final raw = m['last_app_open_at'];
    final hiddenRaw = m['hidden_from_directory'];
    final hidden = hiddenRaw is bool
        ? hiddenRaw
        : (hiddenRaw?.toString().trim().toLowerCase() == 'true' ||
            hiddenRaw?.toString().trim() == '1');
    final at = parseSupabaseTimestampToUtc(raw);
    return _AccessRow(
      id: (m['id'] as num?)?.toInt() ?? 0,
      displayName: display,
      username: username,
      email: email,
      role: (m['role'] ?? '').toString().trim(),
      active: m['active'] != false,
      hiddenFromDirectory: hidden,
      lastAppOpenAt: at,
      lastSignInAt: null,
      lastSeenAt: at,
      lastSeenSource: at == null ? null : 'app',
      lastSeenRaw: raw,
      lastAppOpenPlatform:
          (m['last_app_open_platform'] ?? '').toString().trim(),
    );
  }

  String get roleLabel {
    final r = role.toLowerCase().trim();
    switch (r) {
      case 'dipendente':
      case 'user':
        return 'Dipendente';
      case 'caposquadra':
        return 'Caposquadra';
      case 'dt':
        return 'DT';
      case 'assistente_dt':
        return 'Assistente DT';
      case 'admin':
      case 'admin_generale':
        return 'Admin generale';
      case 'admin_pernottamenti':
        return 'Admin pernottamenti';
      case 'admin_trenoaereo':
        return 'Admin treni/aerei';
      case 'logistica':
        return 'Logistica';
      case 'ristoratore':
        return 'Ristoratore';
      default:
        return role.isEmpty ? '—' : role;
    }
  }

  String get lastOpenLabel {
    if (lastSeenAt == null) return 'Mai entrato';
    final s = formatDateTimeItFromSupabase(lastSeenRaw);
    if (s.isEmpty) return 'Mai entrato';
    if (lastSeenSource == 'login') return '$s (login)';
    if (lastSeenSource == 'app') return s;
    return s;
  }
}
