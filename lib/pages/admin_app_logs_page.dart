import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_activity_log_service.dart';
import '../utils/date_formatters.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni → Log app: accessi, inserimenti, modifiche, cancellazioni, export (14 giorni).
class AdminAppLogsPage extends StatefulWidget {
  const AdminAppLogsPage({super.key});

  @override
  State<AdminAppLogsPage> createState() => _AdminAppLogsPageState();
}

class _AdminAppLogsPageState extends State<AdminAppLogsPage> {
  bool _loading = true;
  String? _error;
  List<AppActivityLog> _rows = const [];

  final _nameCtrl = TextEditingController();
  String? _role;
  String? _action;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;

  @override
  void initState() {
    super.initState();
    final today = italyNow();
    _dateTo = DateTime(today.year, today.month, today.day);
    _dateFrom = _dateTo!.subtract(const Duration(days: 13));
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  DateTime get _minDate {
    final today = italyNow();
    return DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 13));
  }

  DateTime get _maxDate {
    final today = italyNow();
    return DateTime(today.year, today.month, today.day);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = _dateFrom ?? _minDate;
      final to = _dateTo ?? _maxDate;
      final list = await AppActivityLogService.list(
        fromUtc: DateTime.parse(
          supabaseFilterItalyDayStartUtcIso(from.year, from.month, from.day),
        ),
        toUtc: DateTime.parse(
          supabaseFilterItalyDayEndUtcIso(to.year, to.month, to.day),
        ),
      );
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppActivityLogService.formatLoadError(e);
      });
    }
  }

  List<AppActivityLog> get _filtered {
    final q = _nameCtrl.text.trim().toLowerCase();
    final role = (_role ?? '').trim().toLowerCase();
    final fromM = _minutesOf(_timeFrom);
    final toM = _minutesOf(_timeTo);
    return _rows.where((r) {
      if (q.isNotEmpty) {
        final hay =
            '${r.fullName} ${r.username} ${r.detail} ${_actionLabel(r.action)}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (role.isNotEmpty && r.role.toLowerCase() != role) return false;
      if ((_action ?? '').isNotEmpty &&
          r.action.toLowerCase() != _action!.toLowerCase()) {
        return false;
      }
      if (fromM == null && toM == null) return true;
      final it = parseSupabaseTimestampToItaly(r.createdAtRaw);
      if (it == null) return false;
      final m = it.hour * 60 + it.minute;
      if (fromM != null && m < fromM) return false;
      if (toM != null && m > toM) return false;
      return true;
    }).toList(growable: false);
  }

  int? _minutesOf(TimeOfDay? t) => t == null ? null : t.hour * 60 + t.minute;

  List<String> get _roleOptions {
    final set = <String>{};
    for (final r in _rows) {
      if (r.role.isNotEmpty) set.add(r.role);
    }
    if (_role != null && _role!.isNotEmpty) set.add(_role!);
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _actionOptions {
    const known = <String>[
      'app_open',
      'insert',
      'update',
      'delete',
      'user_create',
      'user_delete',
      'export',
    ];
    final set = <String>{...known};
    for (final r in _rows) {
      if (r.action.isNotEmpty) set.add(r.action);
    }
    if (_action != null && _action!.isNotEmpty) set.add(_action!);
    final extra = set.where((a) => !known.contains(a)).toList()..sort();
    return [...known, ...extra];
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _minDate,
      lastDate: _maxDate,
      initialDateRange: DateTimeRange(
        start: _dateFrom ?? _minDate,
        end: _dateTo ?? _maxDate,
      ),
      helpText: 'Periodo',
      saveText: 'OK',
    );
    if (picked == null) return;
    setState(() {
      _dateFrom = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _dateTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    unawaited(_load());
  }

  Future<void> _pickTimeRange() async {
    final from = await showTimePicker(
      context: context,
      initialTime: _timeFrom ?? const TimeOfDay(hour: 0, minute: 0),
      helpText: 'Dalle ore',
    );
    if (from == null || !mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime: _timeTo ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Alle ore',
    );
    if (to == null || !mounted) return;
    setState(() {
      _timeFrom = from;
      _timeTo = to;
    });
  }

  void _clearFilters() {
    final today = italyNow();
    setState(() {
      _nameCtrl.clear();
      _role = null;
      _action = null;
      _dateTo = DateTime(today.year, today.month, today.day);
      _dateFrom = _dateTo!.subtract(const Duration(days: 13));
      _timeFrom = null;
      _timeTo = null;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Log app'),
          actions: [
            IconButton(
              tooltip: 'Azzera filtri',
              onPressed: _loading ? null : _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
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
                'Storico azioni in app (accessi, inserimenti, modifiche, cancellazioni, export). '
                'I log si cancellano in automatico dopo 2 settimane.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_search_outlined),
                  labelText: 'Nome',
                  hintText: 'Cerca per nome, azione o dettaglio',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  final roleField = InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ruolo',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _role,
                        hint: const Text('Tutti i ruoli'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tutti i ruoli'),
                          ),
                          for (final r in _roleOptions)
                            DropdownMenuItem<String?>(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _role = v);
                        },
                      ),
                    ),
                  );
                  final actionField = InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Azione',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.playlist_add_check_outlined),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _action,
                        hint: const Text('Tutte le azioni'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tutte le azioni'),
                          ),
                          for (final a in _actionOptions)
                            DropdownMenuItem<String?>(
                              value: a,
                              child: Text(_actionLabel(a)),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _action = v);
                        },
                      ),
                    ),
                  );
                  final dateRow = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChipButton(
                        icon: Icons.event_outlined,
                        label:
                            '${_fmtDate(_dateFrom)} – ${_fmtDate(_dateTo)}',
                        onTap: () => unawaited(_pickDateRange()),
                      ),
                      _FilterChipButton(
                        icon: Icons.schedule_outlined,
                        label: _timeFrom == null && _timeTo == null
                            ? 'Tutte le ore'
                            : '${_fmtTime(_timeFrom) ?? '00:00'} – ${_fmtTime(_timeTo) ?? '23:59'}',
                        onTap: () => unawaited(_pickTimeRange()),
                        onClear: _timeFrom == null && _timeTo == null
                            ? null
                            : () => setState(() {
                                  _timeFrom = null;
                                  _timeTo = null;
                                }),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : () => unawaited(_load()),
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Applica'),
                      ),
                    ],
                  );
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        roleField,
                        const SizedBox(height: 10),
                        actionField,
                        const SizedBox(height: 10),
                        dateRow,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 260, child: roleField),
                          const SizedBox(width: 12),
                          SizedBox(width: 260, child: actionField),
                        ],
                      ),
                      const SizedBox(height: 10),
                      dateRow,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                _loading
                    ? 'Caricamento…'
                    : '${filtered.length} log'
                        '${filtered.length != _rows.length ? ' (su ${_rows.length} nel periodo)' : ''}',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Nessun log nel periodo selezionato.',
                    ),
                  ),
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
                                leading: Icon(_actionIcon(r.action)),
                                title: Text(
                                  r.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_roleLabel(r.role)} · ${_actionLabel(r.action)}'
                                  '${r.detail.isEmpty ? '' : ' · ${r.detail}'}\n'
                                  '${_fmtDateTime(r)}',
                                ),
                                isThreeLine: true,
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
                                  DataColumn(label: Text('Data e ora')),
                                  DataColumn(label: Text('Nome')),
                                  DataColumn(label: Text('Ruolo')),
                                  DataColumn(label: Text('Azione')),
                                  DataColumn(label: Text('Dettaglio')),
                                ],
                                rows: [
                                  for (final r in filtered)
                                    DataRow(
                                      cells: [
                                        DataCell(Text(_fmtDateTime(r))),
                                        DataCell(
                                          Text(
                                            r.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(_roleLabel(r.role))),
                                        DataCell(Text(_actionLabel(r.action))),
                                        DataCell(
                                          SizedBox(
                                            width: 360,
                                            child: Text(
                                              r.detail.isEmpty ? '—' : r.detail,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
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

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : formatDateDdMmYyyyFromDate(d);

  String? _fmtTime(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(AppActivityLog r) {
    final s = formatDateTimeItFromSupabase(r.createdAtRaw);
    return s.isEmpty ? '—' : s;
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      onDeleted: onClear,
    );
  }
}

String _roleLabel(String role) {
  switch (role.toLowerCase().trim()) {
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
    case 'admin_vista':
      return 'Admin vista';
    case 'admin_pernottamenti':
      return 'Admin pernottamenti';
    case 'admin_trenoaereo':
    case 'admin_treno_aereo':
      return 'Admin treni/aerei';
    case 'admin_dpi':
      return 'Admin DPI';
    case 'admin_formazione':
      return 'Admin formazione';
    case 'logistica':
      return 'Logistica';
    case 'ristoratore':
      return 'Ristoratore';
    default:
      return role.isEmpty ? '—' : role;
  }
}

String _actionLabel(String action) {
  switch (action.toLowerCase().trim()) {
    case 'app_open':
      return 'Accesso app';
    case 'login':
      return 'Login';
    case 'insert':
      return 'Inserimento';
    case 'update':
      return 'Modifica salvata';
    case 'delete':
      return 'Cancellazione';
    case 'export':
      return 'Export';
    case 'user_create':
      return 'Nuovo utente';
    case 'user_delete':
      return 'Cancellazione utente';
    default:
      return action.isEmpty ? 'Accesso app' : action;
  }
}

IconData _actionIcon(String action) {
  switch (action.toLowerCase().trim()) {
    case 'insert':
      return Icons.add_circle_outline;
    case 'update':
      return Icons.edit_outlined;
    case 'delete':
      return Icons.delete_outline;
    case 'export':
      return Icons.download_outlined;
    case 'user_create':
      return Icons.person_add_alt_1_outlined;
    case 'user_delete':
      return Icons.person_off_outlined;
    case 'login':
    case 'app_open':
      return Icons.login_outlined;
    default:
      return Icons.history_outlined;
  }
}
