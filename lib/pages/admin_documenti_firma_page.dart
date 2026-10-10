import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/doc_firma_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_page_chrome.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';

/// Admin: invio documenti da firmare e gestione scadenze/download.
class AdminDocumentiFirmaPage extends StatefulWidget {
  const AdminDocumentiFirmaPage({super.key, this.forceMobileLayout = false});

  final bool forceMobileLayout;

  @override
  State<AdminDocumentiFirmaPage> createState() =>
      _AdminDocumentiFirmaPageState();
}

enum _FirmaVista {
  documenti,
  inCorso,
  firmeMancanti,
  completati,
  verifica,
}

class _AdminDocumentiFirmaPageState extends State<AdminDocumentiFirmaPage> {
  bool _loading = true;
  String? _error;
  List<DocFirmaAssignment> _rows = const [];
  _FirmaVista _vista = _FirmaVista.documenti;
  String? _exportingBatchId;

  bool _verifyBusy = false;
  String? _verifyFileName;
  DocFirmaIntegrityResult? _verifyResult;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DocFirmaService.listAdminAssignments();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openNew() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NuovoInvioDialog(),
    );
    if (ok == true) await _reload();
  }

  /// Password documento: solo per admin (vista/scarico), mai per chi firma.
  Future<bool> _ensureAdminAccessPassword(
    String batchId,
    bool required,
  ) async {
    if (!required) return true;
    final ctrl = TextEditingController();
    var obscure = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('Password documento'),
                content: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Questo documento è protetto. Inserisci la password '
                        'per visualizzare o scaricare (solo admin).',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ctrl,
                        obscureText: obscure,
                        autofocus: true,
                        onSubmitted: (_) => Navigator.pop(ctx, true),
                        decoration: InputDecoration(
                          labelText: 'Password accesso',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setLocal(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
              );
            },
          );
        },
      );
      if (ok != true) return false;
      final pwd = ctrl.text.trim();
      if (pwd.isEmpty) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inserisci la password')),
        );
        return false;
      }
      final verified = await DocFirmaService.verifyAccessPassword(
        batchId: batchId,
        password: pwd,
      );
      if (!verified) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password non corretta'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
      return true;
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _cancel(DocFirmaAssignment a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancella documento'),
        content: Text(
          'Cancellare «${a.title}» per questo dipendente? '
          'L\'azione è consentita prima della scadenza download.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DocFirmaService.cancelAssignment(a.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento cancellato')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _download(DocFirmaAssignment a) async {
    try {
      if (!await _ensureAdminAccessPassword(a.batchId, a.requiresAccessPassword)) {
        return;
      }
      final bytes = await DocFirmaService.downloadSignedPdf(
        a,
        allowAdminOverride: true,
      );
      final name = a.title.replaceAll(RegExp(r'[^\w]+'), '_');
      await ExcelExportHelper.saveAndReveal(
        pageName: 'Firmato_$name',
        bytes: bytes,
        extension: 'pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadFinalBatch(_AdminBatchGroup g) async {
    if (_exportingBatchId != null) return;
    if (!await _ensureAdminAccessPassword(
      g.batchId,
      g.requiresAccessPassword,
    )) {
      return;
    }
    setState(() => _exportingBatchId = g.batchId);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Preparazione export finale...')),
            ],
          ),
        ),
      ),
    );
    try {
      final bytes = await DocFirmaService.downloadBatchFullySignedPdf(
        batchId: g.batchId,
      );
      final name = g.title.replaceAll(RegExp(r'[^\w]+'), '_');
      await ExcelExportHelper.saveAndReveal(
        pageName: 'Firme_complete_$name',
        bytes: bytes,
        extension: 'pdf',
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Export unico pronto: documento originale + quadro firme.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exportingBatchId = null);
    }
  }

  Future<void> _downloadEvidencePack(_AdminBatchGroup g) async {
    if (_exportingBatchId != null) return;
    if (!await _ensureAdminAccessPassword(
      g.batchId,
      g.requiresAccessPassword,
    )) {
      return;
    }
    setState(() => _exportingBatchId = g.batchId);
    try {
      final bytes = await DocFirmaService.buildEvidencePackJson(
        batchId: g.batchId,
      );
      final name = g.title.replaceAll(RegExp(r'[^\w]+'), '_');
      await ExcelExportHelper.saveAndReveal(
        pageName: 'Evidenze_firma_$name',
        bytes: bytes,
        extension: 'json',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pacchetto evidenze scaricato (timestamp server + HMAC). '
            'Non e conservazione AgID.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exportingBatchId = null);
    }
  }

  String _statusLabel(DocFirmaAssignment a) {
    switch (a.status) {
      case 'pending':
        return 'In attesa firma';
      case 'signed':
        return a.canDownload ? 'Firmato' : 'Firmato (scaduto download)';
      case 'expired':
        return 'Scaduto';
      case 'cancelled':
        return 'Cancellato';
      default:
        return a.status;
    }
  }

  Color _statusColor(DocFirmaAssignment a) {
    switch (a.status) {
      case 'pending':
        return Colors.orange.shade700;
      case 'signed':
        return a.canDownload ? Colors.green.shade700 : Colors.grey;
      case 'expired':
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  List<_AdminBatchGroup> get _groups {
    final map = <String, List<DocFirmaAssignment>>{};
    for (final a in _rows) {
      map.putIfAbsent(a.batchId, () => <DocFirmaAssignment>[]).add(a);
    }
    final out = map.entries.map((e) {
      final rows = e.value
        ..sort((a, b) => (a.sentAt ?? DateTime(1970)).compareTo(
              b.sentAt ?? DateTime(1970),
            ));
      return _AdminBatchGroup(batchId: e.key, rows: rows);
    }).toList()
      ..sort((a, b) => (b.lastUpdate ?? DateTime(1970)).compareTo(
            a.lastUpdate ?? DateTime(1970),
          ));
    return out;
  }

  int get _totalDocs => _groups.length;
  int get _docsComplete => _groups.where((g) => g.allSigned).length;
  int get _docsInProgress =>
      _groups.where((g) => !g.allSigned && g.pendingCount > 0).length;
  int get _pendingSignatures =>
      _groups.fold<int>(0, (sum, g) => sum + g.pendingCount);

  List<_AdminBatchGroup> get _filteredGroups {
    switch (_vista) {
      case _FirmaVista.documenti:
        return _groups;
      case _FirmaVista.inCorso:
        return _groups
            .where((g) => !g.allSigned && g.pendingCount > 0)
            .toList(growable: false);
      case _FirmaVista.firmeMancanti:
        return _groups
            .where((g) => g.pendingCount > 0)
            .toList(growable: false);
      case _FirmaVista.completati:
        return _groups.where((g) => g.allSigned).toList(growable: false);
      case _FirmaVista.verifica:
        return const [];
    }
  }

  List<DocFirmaAssignment> get _pendingAssignments {
    return _rows
        .where((a) => a.status == 'pending')
        .toList(growable: false)
      ..sort((a, b) => (a.signDeadline ?? DateTime(2099))
          .compareTo(b.signDeadline ?? DateTime(2099)));
  }

  String get _vistaTitle {
    switch (_vista) {
      case _FirmaVista.documenti:
        return 'Tutti i documenti';
      case _FirmaVista.inCorso:
        return 'Documenti in corso';
      case _FirmaVista.firmeMancanti:
        return 'Firme ancora da raccogliere';
      case _FirmaVista.completati:
        return 'Documenti completati';
      case _FirmaVista.verifica:
        return 'Verifica integrita documento';
    }
  }

  String get _vistaSubtitle {
    switch (_vista) {
      case _FirmaVista.documenti:
        return 'Elenco in 2 colonne: singoli e congiunti';
      case _FirmaVista.inCorso:
        return 'Documenti con almeno una firma ancora in attesa';
      case _FirmaVista.firmeMancanti:
        return 'Persone che devono ancora firmare, raggruppate per urgenza';
      case _FirmaVista.completati:
        return 'Documenti firmati da tutti — disponibili per export finale';
      case _FirmaVista.verifica:
        return 'Carica un PDF firmato e confrontalo con hash ed evidenze CRONOS';
    }
  }

  Future<void> _pickAndVerifyIntegrity() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
        ),
      ],
    );
    if (file == null) return;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.pdf')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona un file PDF'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _verifyBusy = true;
      _verifyError = null;
      _verifyResult = null;
      _verifyFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final result = await DocFirmaService.verifyIntegrity(bytes);
      if (!mounted) return;
      setState(() {
        _verifyResult = result;
        _verifyBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifyBusy = false;
        _verifyError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Firma digitale';
    final actions = <Widget>[
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _reload,
        icon: const Icon(Icons.refresh),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.icon(
          onPressed: _openNew,
          icon: const Icon(Icons.upload_file),
          label: const Text('Nuovo invio'),
        ),
      ),
    ];
    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: pageTitle),
          actions: actions,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade50,
                              Colors.indigo.shade50,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestione firme digitali',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Usa i pulsanti sotto per navigare. '
                              'Carica un PDF e scegli i firmatari: '
                              '${DocFirmaService.signWindowDays} giorni per firmare '
                              '(Passkey + OTP + firma + timestamp server) e '
                              '${DocFirmaService.downloadWindowDays} per scaricare; '
                              'poi i PDF scaduti vengono eliminati (le evidenze HMAC restano). '
                              'SES interna: non eIDAS / non TSA / non conservazione AgID.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Aree operative',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.blueGrey.shade800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 720;
                          final cards = [
                            _KpiCard(
                              icon: Icons.folder_outlined,
                              label: 'Documenti',
                              value: '$_totalDocs',
                              subtitle: 'Tutti gli invii',
                              color: Colors.indigo,
                              selected: _vista == _FirmaVista.documenti,
                              onTap: () => setState(
                                () => _vista = _FirmaVista.documenti,
                              ),
                            ),
                            _KpiCard(
                              icon: Icons.hourglass_top_rounded,
                              label: 'In corso',
                              value: '$_docsInProgress',
                              subtitle: 'Da completare',
                              color: Colors.orange,
                              selected: _vista == _FirmaVista.inCorso,
                              onTap: () => setState(
                                () => _vista = _FirmaVista.inCorso,
                              ),
                            ),
                            _KpiCard(
                              icon: Icons.pending_actions_outlined,
                              label: 'Firme mancanti',
                              value: '$_pendingSignatures',
                              subtitle: 'Persone in attesa',
                              color: Colors.redAccent,
                              selected: _vista == _FirmaVista.firmeMancanti,
                              onTap: () => setState(
                                () => _vista = _FirmaVista.firmeMancanti,
                              ),
                            ),
                            _KpiCard(
                              icon: Icons.verified_outlined,
                              label: 'Completati',
                              value: '$_docsComplete',
                              subtitle: 'Pronti export',
                              color: Colors.green,
                              selected: _vista == _FirmaVista.completati,
                              onTap: () => setState(
                                () => _vista = _FirmaVista.completati,
                              ),
                            ),
                            _KpiCard(
                              icon: Icons.policy_outlined,
                              label: 'Verifica',
                              value: 'PDF',
                              subtitle: 'Integrita / manomissione',
                              color: Colors.teal,
                              selected: _vista == _FirmaVista.verifica,
                              onTap: () => setState(
                                () => _vista = _FirmaVista.verifica,
                              ),
                            ),
                          ];
                          if (wide) {
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: cards
                                  .map(
                                    (c) => SizedBox(
                                      width: (constraints.maxWidth - 20) / 3,
                                      child: c,
                                    ),
                                  )
                                  .toList(growable: false),
                            );
                          }
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: cards
                                .map(
                                  (c) => SizedBox(
                                    width: (constraints.maxWidth - 10) / 2,
                                    child: c,
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: CronosAppThemes.cardOf(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: CronosAppThemes.hairlineOf(context)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.view_list_rounded,
                              color: Colors.blueGrey.shade600,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _vistaTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    _vistaSubtitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.blueGrey.shade600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_vista == _FirmaVista.verifica)
                        _buildVerificaIntegritaPanel(context)
                      else if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('Nessun documento inviato.'),
                          ),
                        )
                      else if (_vista == _FirmaVista.firmeMancanti)
                        ..._buildFirmeMancantiSection(context)
                      else if (_filteredGroups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              _vista == _FirmaVista.completati
                                  ? 'Nessun documento completato.'
                                  : 'Nessun documento in questa area.',
                            ),
                          ),
                        )
                      else
                        _buildTwoColumnDocs(context, _filteredGroups),
                    ],
                  ),
                ),
    );
  }

  Widget _buildVerificaIntegritaPanel(BuildContext context) {
    final result = _verifyResult;
    Color? bannerColor;
    IconData bannerIcon = Icons.policy_outlined;
    if (result != null) {
      if (result.isIntegro) {
        bannerColor = Colors.green.shade700;
        bannerIcon = Icons.verified_user;
      } else if (result.verdict == 'manomesso') {
        bannerColor = Colors.red.shade800;
        bannerIcon = Icons.gpp_bad_outlined;
      } else {
        bannerColor = Colors.orange.shade800;
        bannerIcon = Icons.warning_amber_rounded;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verifica integrita PDF firmato',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Carica un PDF firmato (quello scaricato da admin o dipendente). '
              'CRONOS calcola lo SHA-256 e lo confronta con i documenti registrati '
              'e con il ledger evidenze HMAC. '
              'Se il file e stato modificato, l\'hash non coincide.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _verifyBusy ? null : _pickAndVerifyIntegrity,
              icon: _verifyBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _verifyBusy ? 'Verifica in corso...' : 'Carica PDF da verificare',
              ),
            ),
            if (_verifyFileName != null) ...[
              const SizedBox(height: 8),
              Text(
                'File: $_verifyFileName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_verifyError != null) ...[
              const SizedBox(height: 12),
              Text(
                _verifyError!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (bannerColor ?? Colors.blueGrey).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: bannerColor ?? Colors.blueGrey,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(bannerIcon, color: bannerColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.isIntegro
                                ? 'VERITIERO / INTEGRO'
                                : (result.verdict == 'manomesso'
                                    ? 'MANOMESSO'
                                    : 'SCONOSCIUTO O MANOMESSO'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: bannerColor,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(result.message),
                          const SizedBox(height: 6),
                          SelectableText(
                            'SHA-256: ${result.fileSha256}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final m in result.matches) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CronosAppThemes.hairlineOf(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (m['batch_title'] ?? 'Documento').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('Firmatario: ${m['signer_name'] ?? '-'}'),
                      Text('Email: ${m['signer_email'] ?? '-'}'),
                      Text('Sigillo: ${m['document_seal'] ?? '-'}'),
                      Text('Timestamp server: ${m['server_timestamp'] ?? '-'}'),
                      Text(
                        'HMAC evidenze: ${m['evidence_hmac_ok'] == true ? 'OK' : (m['evidence_hmac_ok'] == false ? 'NON VALIDO' : 'n/d')}',
                      ),
                      Text('Assignment: ${m['assignment_id'] ?? '-'}'),
                      if (m['page_codes'] is Map) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Codici pagina registrati: ${(m['page_codes'] as Map).length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFirmeMancantiSection(BuildContext context) {
    final pending = _pendingAssignments;
    if (pending.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Nessuna firma mancante.')),
        ),
      ];
    }
    return [
      for (final a in pending)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0.6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade50,
              child: Icon(Icons.edit_outlined, color: Colors.orange.shade800),
            ),
            title: Text(
              a.recipientLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Documento: ${a.title}\n'
              'Scadenza firma: ${formatDateDdMmYyyy(a.signDeadline)}',
            ),
            isThreeLine: true,
            trailing: _badge('Da firmare', Colors.orange.shade800),
          ),
        ),
    ];
  }

  Widget _buildTwoColumnDocs(
    BuildContext context,
    List<_AdminBatchGroup> groups,
  ) {
    final singoli =
        groups.where((g) => !g.isJointSignature).toList(growable: false);
    final congiunti =
        groups.where((g) => g.isJointSignature).toList(growable: false);

    Widget column({
      required String title,
      required String subtitle,
      required Color accent,
      required IconData icon,
      required List<_AdminBatchGroup> items,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: CronosAppThemes.cardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: accent.withValues(alpha: 0.15),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.blueGrey.shade700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _badge('${items.length}', accent),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Nessun documento in questa colonna',
                          style: TextStyle(color: Colors.blueGrey.shade500),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final g in items) _buildBatchCard(context, g),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 980;
        final left = column(
          title: 'Documenti singoli',
          subtitle: 'Un firmatario per documento',
          accent: Colors.blueGrey.shade700,
          icon: Icons.person_outline,
          items: singoli,
        );
        final right = column(
          title: 'Documenti congiunti',
          subtitle: 'Stesso documento, più firmatari',
          accent: Colors.indigo,
          icon: Icons.groups_outlined,
          items: congiunti,
        );
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          children: [
            left,
            const SizedBox(height: 12),
            right,
          ],
        );
      },
    );
  }

  Widget _buildBatchCard(BuildContext context, _AdminBatchGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0.8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            g.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _typeChip(g),
                          if (g.requiresAccessPassword)
                            _badge('Password admin', Colors.amber.shade800),
                          if (g.allSigned) _badge('Completato', Colors.green),
                          if (!g.allSigned && g.pendingCount > 0)
                            _badge('In corso', Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: g.totalCount == 0
                            ? 0
                            : g.signedCount / g.totalCount,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          g.allSigned ? Colors.green : Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Firmato ${g.signedCount}/${g.totalCount} · Mancano ${g.pendingCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blueGrey.shade700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: g.allSigned && _exportingBatchId == null
                          ? () => _downloadFinalBatch(g)
                          : null,
                      icon: _exportingBatchId == g.batchId
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _exportingBatchId == g.batchId
                            ? 'Export...'
                            : 'Export finale',
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: g.signedCount > 0 && _exportingBatchId == null
                          ? () => _downloadEvidencePack(g)
                          : null,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('Evidenze'),
                    ),
                  ],
                ),
              ],
            ),
            if (g.pendingNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Mancano: ${g.pendingNames.join(', ')}',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 14),
            ...g.rows.map((a) => _buildRecipientRow(context, a)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientRow(BuildContext context, DocFirmaAssignment a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_outline, color: _statusColor(a)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      a.recipientLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    _badge(_statusLabel(a), _statusColor(a)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Invio: ${formatDateDdMmYyyy(a.sentAt)} · Scadenza firma: ${formatDateDdMmYyyy(a.signDeadline)}'
                  '${a.downloadUntil != null ? ' · Download fino: ${formatDateDdMmYyyy(a.downloadUntil)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 4,
            children: [
              if (a.canDownload)
                IconButton(
                  tooltip: 'Scarica PDF firmato',
                  onPressed: () => _download(a),
                  icon: const Icon(Icons.download_rounded),
                ),
              if (a.canCancelAdmin)
                IconButton(
                  tooltip: 'Cancella',
                  onPressed: () => _cancel(a),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeChip(_AdminBatchGroup g) => _badge(
        g.isJointSignature ? 'Congiunta' : 'Singola',
        g.isJointSignature ? Colors.indigo : Colors.blueGrey,
      );

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.25),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey.shade600,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? color : Colors.blueGrey.shade300,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminBatchGroup {
  _AdminBatchGroup({required this.batchId, required this.rows});

  final String batchId;
  final List<DocFirmaAssignment> rows;

  String get title => rows.isEmpty ? 'Documento' : rows.first.title;
  int get totalCount => rows.length;
  int get signedCount => rows.where((a) => a.status == 'signed').length;
  int get pendingCount => rows.where((a) => a.status == 'pending').length;
  bool get allSigned => rows.isNotEmpty && rows.every((a) => a.status == 'signed');
  DateTime? get lastUpdate => rows
      .map((a) => a.signedAt ?? a.sentAt)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (p, n) => p == null || n.isAfter(p) ? n : p);

  List<String> get pendingNames => rows
      .where((a) => a.status == 'pending')
      .map((a) => a.recipientLabel)
      .toList(growable: false);

  List<String> get signedNames => rows
      .where((a) => a.status == 'signed')
      .map((a) => a.recipientLabel)
      .toList(growable: false);

  bool get isJointSignature => rows.length > 1;
  bool get requiresAccessPassword =>
      rows.any((a) => a.requiresAccessPassword);
}

class _NuovoInvioDialog extends StatefulWidget {
  const _NuovoInvioDialog();

  @override
  State<_NuovoInvioDialog> createState() => _NuovoInvioDialogState();
}

class _NuovoInvioDialogState extends State<_NuovoInvioDialog> {
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  bool _loadingPeople = true;
  bool _obscurePassword = true;
  String? _fileName;
  String? _mime;
  Uint8List? _bytes;
  List<Map<String, dynamic>> _people = const [];
  final Set<int> _selected = {};
  bool _jointSignature = false;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    try {
      final list = await DocFirmaService.loadSelectableDipendenti();
      list.sort((a, b) {
        final an = (a['full_name'] ?? a['users_full_name'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        final bn = (b['full_name'] ?? b['users_full_name'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        return an.compareTo(bn);
      });
      if (!mounted) return;
      setState(() {
        _people = list;
        _loadingPeople = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPeople = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dipendenti: $e'), backgroundColor: Colors.red),
      );
    }
  }

  bool _isPdfFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.pdf');
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('gotenberg_not_configured') ||
        raw.contains('GOTENBERG_URL') ||
        raw.contains('Conversione Word/Excel')) {
      return 'Per ora è supportato solo il caricamento PDF.';
    }
    final details = RegExp(r'details:\s*(.+?)(?:,\s*reasonPhrase|$)')
        .firstMatch(raw)
        ?.group(1);
    if (details != null && details.trim().isNotEmpty) {
      return details
          .replaceAll(RegExp(r'[{}]'), '')
          .replaceAll('error: ', '')
          .replaceAll('details: ', '')
          .trim();
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!_isPdfFile(file.name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caricamento PDF obbligatorio.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _fileName = file.name;
      _mime = file.mimeType ?? 'application/pdf';
      _bytes = bytes;
      if (_titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final base = q.isEmpty
        ? List<Map<String, dynamic>>.from(_people)
        : _people.where((p) {
            final name = (p['full_name'] ?? '').toString().toLowerCase();
            final email =
                (p['email'] ?? p['users_email'] ?? '').toString().toLowerCase();
            final mat = (p['matricola'] ?? '').toString().toLowerCase();
            return name.contains(q) || email.contains(q) || mat.contains(q);
          }).toList();
    base.sort((a, b) {
      final an = (a['full_name'] ?? '').toString().toLowerCase().trim();
      final bn = (b['full_name'] ?? '').toString().toLowerCase().trim();
      return an.compareTo(bn);
    });
    return base;
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _bytes == null || _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titolo e PDF obbligatori')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno un dipendente')),
      );
      return;
    }
    if (!_isPdfFile(_fileName!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caricamento PDF obbligatorio.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final recipients = _people
        .where((p) =>
            _selected.contains(int.tryParse((p['recipient_user_id'] ?? '').toString()) ?? -1))
        .toList();
    setState(() => _busy = true);
    try {
      await DocFirmaService.createAndSend(
        title: title,
        originalFileName: _fileName!,
        originalMime: _mime,
        fileBytes: _bytes!,
        recipients: recipients,
        accessPassword: _passwordCtrl.text.trim().isEmpty
            ? null
            : _passwordCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedPeople = _people
        .where((p) => _selected.contains(
              int.tryParse((p['recipient_user_id'] ?? '').toString()) ?? -1,
            ))
        .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Material(
          color: const Color(0xFFF7F9FC),
          elevation: 12,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F2744), Color(0xFF1B4F86)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nuovo invio documento',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Invia un PDF per firma digitale (Passkey + OTP + firma)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Chiudi',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionCard(
                        title: 'Documento',
                        icon: Icons.description_outlined,
                        child: Column(
                          children: [
                            TextField(
                              controller: _titleCtrl,
                              decoration: InputDecoration(
                                labelText: 'Titolo documento',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: _busy ? null : _pickFile,
                              borderRadius: BorderRadius.circular(12),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _fileName == null
                                      ? const Color(0xFFEFF5FF)
                                      : const Color(0xFFE8F7EE),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _fileName == null
                                        ? const Color(0xFFB8D0F5)
                                        : const Color(0xFF9DCFB0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _fileName == null
                                          ? Icons.upload_file_outlined
                                          : Icons.picture_as_pdf_outlined,
                                      color: _fileName == null
                                          ? cs.primary
                                          : Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _fileName ?? 'Carica file PDF',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: _fileName == null
                                                  ? cs.primary
                                                  : Colors.green.shade800,
                                            ),
                                          ),
                                          Text(
                                            _fileName == null
                                                ? 'Solo PDF · obbligatorio'
                                                : 'File pronto per l\'invio',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: Colors.blueGrey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_fileName != null)
                                      IconButton(
                                        tooltip: 'Cambia file',
                                        onPressed: _busy ? null : _pickFile,
                                        icon: const Icon(Icons.swap_horiz),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password accesso admin (opzionale)',
                                hintText: 'Solo per vista/scarico admin',
                                helperText:
                                    'Se impostata, serve agli admin per scaricare o esportare il documento. '
                                    'Chi firma non la vede e non deve inserirla.',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip:
                                      _obscurePassword ? 'Mostra' : 'Nascondi',
                                  onPressed: () => setState(
                                    () =>
                                        _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        title: 'Modalità firma',
                        icon: Icons.how_to_reg_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text('Firma singola'),
                                  icon: Icon(Icons.person_outline),
                                ),
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text('Firma congiunta'),
                                  icon: Icon(Icons.group_outlined),
                                ),
                              ],
                              selected: {_jointSignature},
                              onSelectionChanged: _busy
                                  ? null
                                  : (s) => setState(() {
                                        _jointSignature = s.first;
                                        if (!_jointSignature &&
                                            _selected.length > 1) {
                                          final keep = _selected.first;
                                          _selected
                                            ..clear()
                                            ..add(keep);
                                        }
                                      }),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                labelText: 'Cerca dipendente',
                                hintText: 'Nome, email o matricola',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.sort_by_alpha,
                                  size: 16,
                                  color: Colors.blueGrey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _jointSignature
                                        ? 'Selezionati: ${_selected.length} · elenco A→Z'
                                        : 'Selezionato: ${_selected.length}/1 · elenco A→Z',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: Colors.blueGrey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (selectedPeople.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: selectedPeople
                                    .map(
                                      (p) => Chip(
                                        avatar:
                                            const Icon(Icons.person, size: 16),
                                        label: Text(
                                          (p['full_name'] ??
                                                  p['users_full_name'] ??
                                                  '')
                                              .toString(),
                                        ),
                                        backgroundColor:
                                            const Color(0xFFE8F0FE),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: CronosAppThemes.cardOf(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CronosAppThemes.hairlineOf(context)),
                          ),
                          child: _loadingPeople
                              ? const Center(child: CircularProgressIndicator())
                              : _filtered.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Nessun dipendente trovato',
                                        style: TextStyle(
                                          color: Colors.blueGrey.shade500,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      itemCount: _filtered.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 1,
                                        color: Colors.blueGrey.shade50,
                                      ),
                                      itemBuilder: (ctx, i) {
                                        final p = _filtered[i];
                                        final uid = int.tryParse(
                                              (p['recipient_user_id'] ?? '')
                                                  .toString(),
                                            ) ??
                                            0;
                                        final checked = _selected.contains(uid);
                                        final name =
                                            (p['full_name'] ?? '').toString();
                                        final subtitle = [
                                          if ((p['matricola'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                            'Mat. ${p['matricola']}',
                                          (p['email'] ??
                                                  p['users_email'] ??
                                                  '')
                                              .toString(),
                                        ]
                                            .where((s) => s.trim().isNotEmpty)
                                            .join(' · ');
                                        return Material(
                                          color: checked
                                              ? const Color(0xFFF0F6FF)
                                              : Colors.transparent,
                                          child: CheckboxListTile(
                                            value: checked,
                                            controlAffinity:
                                                ListTileControlAffinity.trailing,
                                            secondary: CircleAvatar(
                                              radius: 18,
                                              backgroundColor: checked
                                                  ? cs.primary
                                                  : const Color(0xFFE6EEF8),
                                              foregroundColor: checked
                                                  ? Colors.white
                                                  : cs.primary,
                                              child: Text(
                                                name.isEmpty
                                                    ? '?'
                                                    : name.trim()[0].toUpperCase(),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: subtitle.isEmpty
                                                ? null
                                                : Text(subtitle),
                                            onChanged: uid <= 0
                                                ? null
                                                : (v) => setState(() {
                                                      if (v == true) {
                                                        if (_jointSignature) {
                                                          _selected.add(uid);
                                                        } else {
                                                          _selected
                                                            ..clear()
                                                            ..add(uid);
                                                        }
                                                      } else {
                                                        _selected.remove(uid);
                                                      }
                                                    }),
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
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                decoration: BoxDecoration(
                  color: CronosAppThemes.cardOf(context),
                  border: Border(
                    top: BorderSide(color: CronosAppThemes.hairlineOf(context)),
                  ),
                ),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Annulla'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Invia documento'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: CronosAppThemes.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CronosAppThemes.hairlineOf(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F2744),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF1B4F86)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F2744),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
