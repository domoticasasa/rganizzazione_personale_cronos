import 'package:flutter/material.dart';

import '../services/supabase_usage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni App → spazio ancora disponibile su Supabase.
class AdminSupabaseUsagePage extends StatefulWidget {
  const AdminSupabaseUsagePage({super.key});

  @override
  State<AdminSupabaseUsagePage> createState() => _AdminSupabaseUsagePageState();
}

class _AdminSupabaseUsagePageState extends State<AdminSupabaseUsagePage> {
  bool _loading = true;
  String? _error;
  SupabaseUsageSnapshot? _data;
  SupabasePlanRef _plan = SupabasePlanRef.pro;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final plan = await SupabaseUsageService.loadPlan();
    if (mounted) setState(() => _plan = plan);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseUsageService.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _setPlan(SupabasePlanRef plan) async {
    setState(() => _plan = plan);
    await SupabaseUsageService.savePlan(plan);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Spazio Supabase'),
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
          child: _loading && data == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null && data == null
                  ? _ErrorBody(message: _error!, onRetry: _load)
                  : _UsageBody(
                      data: data!,
                      plan: _plan,
                      loading: _loading,
                      error: _error,
                      onPlan: _setPlan,
                    ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final missingFn = message.contains('admin_supabase_usage') ||
        message.toLowerCase().contains('could not find the function') ||
        message.toLowerCase().contains('schema cache');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              missingFn
                  ? 'La funzione sul database non è ancora attiva. '
                      'Applica la migration '
                      '«admin_supabase_usage» e riprova.'
                  : 'Impossibile leggere l’utilizzo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({
    required this.data,
    required this.plan,
    required this.loading,
    required this.error,
    required this.onPlan,
  });

  final SupabaseUsageSnapshot data;
  final SupabasePlanRef plan;
  final bool loading;
  final String? error;
  final ValueChanged<SupabasePlanRef> onPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dbLimit = plan.databaseLimitBytes;
    final stLimit = plan.storageLimitBytes;
    final dbLeft = (dbLimit - data.databaseBytes).clamp(0, dbLimit);
    final stLeft = (stLimit - data.storageBytes).clamp(0, stLimit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Spazio ancora disponibile sul progetto Supabase: database Postgres '
          'e file in Storage. Scegli il piano come riferimento delle quote incluse.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Piano:', style: theme.textTheme.labelLarge),
            for (final p in SupabasePlanRef.values)
              ChoiceChip(
                label: Text(p.label),
                selected: plan == p,
                onSelected: (_) => onPlan(p),
              ),
            if (data.checkedAt != null)
              Text(
                'Aggiornato ${_fmtTime(data.checkedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 900;
                  final cards = [
                    _QuotaCard(
                      title: 'Database',
                      icon: Icons.storage_outlined,
                      used: data.databaseBytes,
                      limit: dbLimit,
                      remaining: dbLeft,
                      hint: 'Dati Postgres (tabelle, indici). Quota disco inclusa nel piano.',
                    ),
                    _QuotaCard(
                      title: 'Storage file',
                      icon: Icons.folder_outlined,
                      used: data.storageBytes,
                      limit: stLimit,
                      remaining: stLeft,
                      hint: 'Foto, PDF, allegati nei bucket Storage.',
                    ),
                  ];
                  if (!wide) {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 12),
                        cards[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Utenti',
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      label: 'Account Auth',
                      value: '${data.authUsers}',
                      detail: 'Limite MAU piano ${plan.label}: ${_fmtInt(plan.authMauLimit)}',
                    ),
                    _StatChip(
                      label: 'Utenti in app',
                      value: '${data.appUsers}',
                      detail: 'Righe in anagrafica',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Bucket Storage',
                child: data.buckets.isEmpty
                    ? const Text('Nessun file nei bucket, oppure Storage non leggibile.')
                    : Column(
                        children: [
                          for (final b in data.buckets)
                            _BarRow(
                              label: b.id.isEmpty ? '(senza nome)' : b.id,
                              trailing:
                                  '${formatStorageBytes(b.bytes)} · ${b.files} file',
                              value: stLimit <= 0
                                  ? 0
                                  : (b.bytes / stLimit).clamp(0.0, 1.0),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Tabelle più grandi',
                child: data.tables.isEmpty
                    ? const Text('Nessuna tabella pubblica.')
                    : Column(
                        children: [
                          for (final t in data.tables)
                            _BarRow(
                              label: t.name,
                              trailing:
                                  '${formatStorageBytes(t.bytes)} · ~${_fmtInt(t.estRows)} righe',
                              value: dbLimit <= 0
                                  ? 0
                                  : (t.bytes / dbLimit).clamp(0.0, 1.0),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                'Egress, funzioni Edge e messaggi Realtime non si misurano da qui: '
                'sono nel pannello Supabase → Settings → Usage. '
                'Se il piano ha già allargato il disco oltre i GB inclusi, '
                'lo spazio reale può essere maggiore.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _fmtInt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({
    required this.title,
    required this.icon,
    required this.used,
    required this.limit,
    required this.remaining,
    required this.hint,
  });

  final String title;
  final IconData icon;
  final int used;
  final int limit;
  final int remaining;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final color = ratio >= 0.9
        ? theme.colorScheme.error
        : ratio >= 0.7
            ? Colors.orange.shade800
            : theme.colorScheme.primary;
    final over = used > limit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              over
                  ? 'Oltre la quota inclusa: ${formatStorageBytes(used - limit)}'
                  : 'Ancora disponibile: ${formatStorageBytes(remaining)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Usati ${formatStorageBytes(used)} di ${formatStorageBytes(limit)} '
              '(${(ratio * 100).toStringAsFixed(1)}%)',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        Text(value, style: theme.textTheme.headlineSmall),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.trailing,
    required this.value,
  });

  final String label;
  final String trailing;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              Text(
                trailing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
