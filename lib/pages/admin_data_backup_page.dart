import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_data_backup_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni → Backup dati (solo admin generale, protetto da password).
class AdminDataBackupPage extends StatefulWidget {
  const AdminDataBackupPage({super.key});

  @override
  State<AdminDataBackupPage> createState() => _AdminDataBackupPageState();
}

class _AdminDataBackupPageState extends State<AdminDataBackupPage> {
  bool _unlocked = false;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  List<DataBackupRun> _runs = const [];

  final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

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
      builder: (ctx) => const _PasswordGateDialog(
        message:
            'Solo admin generale. Digita la tua password per aprire '
            'la gestione backup dati.',
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() => _unlocked = true);
      await _load();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runs = await AdminDataBackupService.listRuns();
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<String?> _askPassword({required String title}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _ConfirmPasswordDialog(title: title),
    );
  }

  Future<void> _runBackup() async {
    final pw = await _askPassword(
      title: 'Digita la password admin per avviare un backup ora',
    );
    if (pw == null || pw.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await AdminDataBackupService.runBackup(confirmPassword: pw);
      if (!mounted) return;
      final date = (res['backup_date'] ?? '').toString();
      final tables = res['tables_count'];
      final rows = res['rows_count'];
      ModifyFeedback.hint(
        context,
        'Backup ${date.isEmpty ? 'completato' : date}: '
        '$tables tabelle · $rows righe.',
      );
      await _load();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showManifest(
    DataBackupRun run, {
    BackupCopySource source = BackupCopySource.primary,
  }) async {
    final pw = await _askPassword(
      title:
          'Password per vedere la ${source.labelIt} del backup ${run.backupDate}',
    );
    if (pw == null || pw.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await AdminDataBackupService.loadManifest(
        backupDate: run.backupDate,
        confirmPassword: pw,
        source: source,
      );
      if (!mounted) return;
      final sourceLabel =
          (res['source_label'] ?? source.labelIt).toString();
      final manifest = res['manifest'];
      final tables = manifest is Map
          ? (manifest['tables'] as List?) ?? const []
          : const [];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Backup ${run.backupDate}\n$sourceLabel'),
          content: SizedBox(
            width: 420,
            child: tables.isEmpty
                ? const Text('Manifest senza elenco tabelle.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tables.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = Map<String, dynamic>.from(tables[i] as Map);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${t['table'] ?? ''}'),
                          trailing: Text('${t['rows'] ?? 0} righe'),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
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

  Future<void> _restore(
    DataBackupRun run, {
    BackupCopySource source = BackupCopySource.primary,
  }) async {
    if (!run.isSuccess) {
      ModifyFeedback.hint(
        context,
        'Puoi ripristinare solo un backup completato con successo.',
      );
      return;
    }
    if (source == BackupCopySource.secondary && !run.hasSecondaryCopy) {
      ModifyFeedback.hint(
        context,
        'Questo run non ha una copia secondaria OK.',
      );
      return;
    }

    final warn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ripristino da ${source.labelIt}'),
        content: Text(
          'Questa operazione SOVRASCRIVE i dati attuali con la '
          '${source.labelIt} del ${run.backupDate}.\n\n'
          'Tutte le tabelle applicative verranno svuotate e ricaricate. '
          'L’operazione può richiedere diversi minuti e non è annullabile.\n\n'
          'Continuare?',
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
    if (warn != true || !mounted) return;

    final confirmed = await showDialog<_RestoreConfirm?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RestoreConfirmDialog(
        backupDate: run.backupDate,
        sourceLabel: source.labelIt,
      ),
    );
    if (confirmed == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await AdminDataBackupService.restoreBackup(
        backupDate: run.backupDate,
        confirmPassword: confirmed.password,
        confirmPhrase: confirmed.phrase,
        source: source,
      );
      if (!mounted) return;
      final okCount = res['tables_ok'];
      final failCount = res['tables_failed'] ?? 0;
      final errors = res['errors'];
      final used =
          (res['source_label'] ?? source.labelIt).toString();
      if (failCount == 0) {
        ModifyFeedback.hint(
          context,
          'Ripristino completato da $used: $okCount tabelle '
          '(${run.backupDate}).',
        );
      } else {
        final detail = errors is List && errors.isNotEmpty
            ? '\n${errors.take(3).map((e) => e is Map ? e['table'] : e).join(', ')}…'
            : '';
        ModifyFeedback.error(
          context,
          'Ripristino parziale da $used: $okCount ok, $failCount errori.$detail',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(DataBackupRun r) {
    if (r.isRunning) return 'In corso…';
    if (r.isSuccess) return 'OK';
    if (r.isFailed) return 'Errore';
    return '—';
  }

  Color _statusColor(DataBackupRun r, ColorScheme cs) {
    if (r.isRunning) return cs.tertiary;
    if (r.isSuccess) return Colors.green.shade700;
    if (r.isFailed) return cs.error;
    return cs.outline;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminGenerale) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(
          context,
          AppBar(
            title: const ResponsiveAppBarTitle(title: 'Backup dati'),
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
            title: const ResponsiveAppBarTitle(title: 'Backup dati'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Backup dati'),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading || _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _runBackup,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.backup_outlined),
        label: const Text('Avvia backup'),
      ),
      body: PageWithTopLogo(
        showLogo: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Backup automatici ogni notte (retention 60 giorni). '
                    'Da qui puoi avviarne uno manuale o ripristinare i dati '
                    'da uno snapshot riuscito.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.blueGrey.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Copia secondaria (regola 3-2-1)',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.blueGrey.shade900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Attiva in automatico sul bucket replica Supabase '
                            '(cronos_data_backups_replica). '
                            'Opzionale off-site: Cloudflare R2 / B2 / S3 — secret '
                            'BACKUP_S3_* in Edge Functions.\n'
                            'Backup notturno: ogni giorno ≈ 03:15 (Europe/Rome). '
                            'Sui pulsanti verdi/arancio sotto ogni data apri o '
                            'ripristina la copia primaria o la secondaria.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                          if (_runs.any((r) => r.secondaryOk == true)) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Copia secondaria attiva su almeno un backup recente.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ] else if (_runs.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Nessuna copia secondaria OK negli ultimi run: '
                              'avvia un backup oppure verifica i log.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _runs.isEmpty
                      ? const Center(
                          child: Text('Nessun backup registrato ancora.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                          itemCount: _runs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = _runs[i];
                            final cs = Theme.of(context).colorScheme;
                            final when = r.finishedAt ?? r.startedAt;
                            final meta = <String>[
                              if (r.tablesCount != null)
                                '${r.tablesCount} tabelle',
                              if (r.rowsCount != null) '${r.rowsCount} righe',
                              if (when != null) _dtFmt.format(when.toLocal()),
                              if (r.triggerSource != null) r.triggerLabelIt,
                            ].join(' · ');
                            final secondaryOk = r.hasSecondaryCopy;
                            final secondaryFail = r.secondaryOk == false;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 8, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    ListTile(
                                      contentPadding:
                                          const EdgeInsets.fromLTRB(12, 4, 4, 0),
                                      leading: Icon(
                                        r.isSuccess
                                            ? Icons.check_circle_outline
                                            : r.isFailed
                                                ? Icons.error_outline
                                                : Icons.hourglass_top_outlined,
                                        color: _statusColor(r, cs),
                                      ),
                                      title: Text(
                                        r.backupDate,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          _statusLabel(r),
                                          if (meta.isNotEmpty) meta,
                                          if (r.errorMessage != null)
                                            r.errorMessage!,
                                        ].join('\n'),
                                      ),
                                      isThreeLine: r.errorMessage != null,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        8,
                                        0,
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            avatar: Icon(
                                              Icons.cloud_outlined,
                                              size: 16,
                                              color: Colors.blue.shade800,
                                            ),
                                            label: const Text('1ª primaria'),
                                            backgroundColor:
                                                Colors.blue.shade50,
                                          ),
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            avatar: Icon(
                                              secondaryOk
                                                  ? Icons.cloud_done_outlined
                                                  : secondaryFail
                                                      ? Icons.cloud_off_outlined
                                                      : Icons.cloud_queue_outlined,
                                              size: 16,
                                              color: secondaryOk
                                                  ? Colors.green.shade800
                                                  : secondaryFail
                                                      ? Colors.red.shade800
                                                      : Colors.orange.shade800,
                                            ),
                                            label: Text(
                                              secondaryOk
                                                  ? '2ª OK'
                                                      '${r.secondaryProvider != null ? ' (${r.secondaryProvider})' : ''}'
                                                  : secondaryFail
                                                      ? '2ª fallita'
                                                      : '2ª assente',
                                            ),
                                            backgroundColor: secondaryOk
                                                ? Colors.green.shade50
                                                : secondaryFail
                                                    ? Colors.red.shade50
                                                    : Colors.orange.shade50,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _busy || !r.isSuccess
                                                ? null
                                                : () => unawaited(
                                                      _showManifest(
                                                        r,
                                                        source: BackupCopySource
                                                            .primary,
                                                      ),
                                                    ),
                                            icon: const Icon(
                                              Icons.list_alt_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('Vedi 1ª'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _busy ||
                                                    !r.isSuccess ||
                                                    !secondaryOk
                                                ? null
                                                : () => unawaited(
                                                      _showManifest(
                                                        r,
                                                        source: BackupCopySource
                                                            .secondary,
                                                      ),
                                                    ),
                                            icon: const Icon(
                                              Icons.list_alt,
                                              size: 18,
                                            ),
                                            label: const Text('Vedi 2ª'),
                                          ),
                                          FilledButton.tonalIcon(
                                            onPressed: _busy || !r.isSuccess
                                                ? null
                                                : () => unawaited(
                                                      _restore(
                                                        r,
                                                        source: BackupCopySource
                                                            .primary,
                                                      ),
                                                    ),
                                            icon: const Icon(
                                              Icons.restore_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('Ripristina 1ª'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _busy ||
                                                    !r.isSuccess ||
                                                    !secondaryOk
                                                ? null
                                                : () => unawaited(
                                                      _restore(
                                                        r,
                                                        source: BackupCopySource
                                                            .secondary,
                                                      ),
                                                    ),
                                            icon: const Icon(
                                              Icons.settings_backup_restore,
                                              size: 18,
                                            ),
                                            label: const Text('Ripristina 2ª'),
                                          ),
                                        ],
                                      ),
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
      ),
    );
  }
}

class _RestoreConfirm {
  const _RestoreConfirm({required this.password, required this.phrase});
  final String password;
  final String phrase;
}

class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({
    required this.backupDate,
    this.sourceLabel = 'copia primaria',
  });
  final String backupDate;
  final String sourceLabel;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final _pwCtrl = TextEditingController();
  final _phraseCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _phraseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Conferma ripristino ${widget.backupDate}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stai ripristinando dalla ${widget.sourceLabel}.\n'
              'Scrivi RIPRISTINA e la tua password admin per procedere.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phraseCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Digita RIPRISTINA',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              obscureText: _obscure,
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final phrase = _phraseCtrl.text.trim();
            final pw = _pwCtrl.text;
            if (phrase.toUpperCase() != 'RIPRISTINA' || pw.isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              _RestoreConfirm(password: pw, phrase: phrase),
            );
          },
          child: const Text('Ripristina ora'),
        ),
      ],
    );
  }
}

class _PasswordGateDialog extends StatefulWidget {
  const _PasswordGateDialog({required this.message});
  final String message;

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
            Text(widget.message),
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
      content: SizedBox(
        width: 360,
        child: TextField(
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
