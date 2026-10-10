import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_multicard_mdo_assegnazioni_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Logistica → PDF assegnazione per Multicard con Assegnazione = MDO.
/// La lista segue l'anagrafica: nuova MDO compare, uscita da MDO sparisce
/// (i PDF vengono cancellati dal DB/storage con trigger).
class AdminLogisticaMulticardMdoAssegnazioniPage extends StatefulWidget {
  const AdminLogisticaMulticardMdoAssegnazioniPage({
    super.key,
    this.forceMobileLayout = false,
  });

  final bool forceMobileLayout;

  @override
  State<AdminLogisticaMulticardMdoAssegnazioniPage> createState() =>
      _AdminLogisticaMulticardMdoAssegnazioniPageState();
}

class _AdminLogisticaMulticardMdoAssegnazioniPageState
    extends State<AdminLogisticaMulticardMdoAssegnazioniPage> {
  bool _loadingList = true;
  bool _loadingDocs = false;
  bool _uploading = false;
  String? _error;
  String _search = '';
  List<MulticardMdoRef> _cards = const [];
  Map<String, int> _counts = const {};
  MulticardMdoRef? _selected;
  List<MulticardMdoAssegnazioneFile> _docs = const [];

  bool get _canWrite {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) return false;
    final r = normalizeRole(role);
    if (r == 'dt' || r == 'assistente_dt') return false;
    return canMutateAsAdmin(role) || r == 'logistica';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCards());
  }

  Future<void> _loadCards() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final cards = await LogisticaMulticardMdoAssegnazioniService.listMulticardMdo();
      Map<String, int> counts = const {};
      try {
        counts = await LogisticaMulticardMdoAssegnazioniService.countByMulticard();
      } catch (_) {}
      if (!mounted) return;
      MulticardMdoRef? selected;
      final prevId = _selected?.id;
      if (prevId != null) {
        for (final c in cards) {
          if (c.id == prevId) {
            selected = c;
            break;
          }
        }
      }
      setState(() {
        _cards = cards;
        _counts = counts;
        _selected = selected;
        if (selected == null) _docs = const [];
        _loadingList = false;
      });
      if (selected != null) await _loadDocs(selected.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshCounts() async {
    try {
      final counts =
          await LogisticaMulticardMdoAssegnazioniService.countByMulticard();
      if (!mounted) return;
      setState(() => _counts = counts);
    } catch (_) {}
  }

  Future<void> _select(MulticardMdoRef card) async {
    setState(() => _selected = card);
    await _loadDocs(card.id);
  }

  Future<void> _loadDocs(String multicardId) async {
    setState(() => _loadingDocs = true);
    try {
      final docs = await LogisticaMulticardMdoAssegnazioniService.listForMulticard(
        multicardId,
      );
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loadingDocs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDocs = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Documenti: $e')),
      );
    }
  }

  List<MulticardMdoRef> get _filtered {
    final k = _search.trim().toLowerCase();
    if (k.isEmpty) return _cards;
    return _cards.where((c) {
      final blob = '${c.multicard} ${c.assegnatario} ${c.limiteSpesa ?? ''} mdo'
          .toLowerCase();
      return blob.contains(k);
    }).toList(growable: false);
  }

  Future<void> _upload() async {
    final card = _selected;
    if (card == null || !_canWrite || _uploading) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaMulticardMdoAssegnazioniService.upload(
        multicardId: card.id,
        originalFileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      await _loadDocs(card.id);
      await _refreshCounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF caricato')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(MulticardMdoAssegnazioneFile row) async {
    if (!_canWrite) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina PDF'),
        content: Text('Eliminare «${row.fileName}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await LogisticaMulticardMdoAssegnazioniService.delete(row);
      if (!mounted) return;
      final id = _selected?.id;
      if (id != null) await _loadDocs(id);
      await _refreshCounts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eliminazione: $e')),
      );
    }
  }

  Future<void> _open(MulticardMdoAssegnazioneFile row) async {
    try {
      final url = await LogisticaMulticardMdoAssegnazioniService.signedUrl(row);
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il file')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apertura: $e')),
      );
    }
  }

  Future<void> _download(MulticardMdoAssegnazioneFile row) async {
    try {
      final bytes =
          await LogisticaMulticardMdoAssegnazioniService.downloadBytes(row);
      final original = row.fileName.trim();
      var base = original;
      var ext = 'pdf';
      final dot = original.lastIndexOf('.');
      if (dot > 0 && dot < original.length - 1) {
        base = original.substring(0, dot);
        ext = original.substring(dot + 1);
      }
      if (base.isEmpty) base = 'assegnazione_multicard_mdo';
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: base,
        bytes: bytes,
        extension: ext,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? (ExcelExportHelper.lastSavedPath?.isNotEmpty == true
                    ? 'Download: ${ExcelExportHelper.lastSavedPath}'
                    : 'Download completato')
                : 'Download annullato',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(
            title: 'Assegnazioni Multicard MDO',
          ),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loadingList ? null : _loadCards,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: PageWithTopLogo(
        showLogo: true,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        'Errore: $_error',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final split =
                            c.maxWidth >= 880 && !widget.forceMobileLayout;
                        if (!split) {
                          if (_selected == null) return _listPane();
                          return Column(
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => setState(() {
                                    _selected = null;
                                    _docs = const [];
                                  }),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Tutte le multicard MDO'),
                                ),
                              ),
                              Expanded(child: _docsPane()),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 360, child: _listPane()),
                            const VerticalDivider(width: 16),
                            Expanded(child: _docsPane()),
                          ],
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _listPane() {
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Cerca numero carta, dipendente…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        Text(
          '${list.length} multicard con assegnazione MDO',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Se una carta viene assegnata a un mezzo stradale, sparisce da qui '
          'e i PDF di assegnazione vengono cancellati automaticamente.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('Nessuna multicard con assegnazione MDO.'),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final selected = _selected?.id == m.id;
                    final n = _counts[m.id] ?? 0;
                    return ListTile(
                      selected: selected,
                      leading: Icon(
                        Icons.credit_card_outlined,
                        color: n > 0 ? const Color(0xFF2E7D32) : null,
                      ),
                      title: Text(m.title),
                      subtitle: m.subtitle.isEmpty ? null : Text(m.subtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusDot(present: n > 0),
                          if (n > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '$n',
                              style: const TextStyle(
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => unawaited(_select(m)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _docsPane() {
    final card = _selected;
    if (card == null) {
      return const Center(
        child: Text(
          'Seleziona una multicard MDO a sinistra per caricare i PDF di assegnazione.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(card.title, style: Theme.of(context).textTheme.titleLarge),
        if (card.subtitle.isNotEmpty)
          Text(
            card.subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        const SizedBox(height: 6),
        Text(
          'Carica uno o più PDF di assegnazione verso il dipendente. '
          'Restano disponibili finché la carta resta su MDO.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (_canWrite) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _uploading ? null : () => unawaited(_upload()),
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_uploading ? 'Caricamento…' : 'Carica PDF'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (_loadingDocs) const LinearProgressIndicator(),
        Expanded(
          child: _docs.isEmpty
              ? const Center(child: Text('Nessun PDF caricato.'))
              : ListView.separated(
                  itemCount: _docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = _docs[i];
                    final sizeKb = d.fileSize == null
                        ? null
                        : (d.fileSize! / 1024).toStringAsFixed(0);
                    return ListTile(
                      leading: const Icon(
                        Icons.picture_as_pdf,
                        color: Color(0xFFC62828),
                      ),
                      title: Text(d.fileName),
                      subtitle: Text(
                        [
                          formatDateDdMmYyyyFromDate(d.uploadedAt),
                          if (sizeKb != null) '$sizeKb KB',
                          if ((d.note ?? '').isNotEmpty) d.note!,
                        ].join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Apri',
                            onPressed: () => unawaited(_open(d)),
                            icon: const Icon(Icons.open_in_new),
                          ),
                          IconButton(
                            tooltip: 'Scarica',
                            onPressed: () => unawaited(_download(d)),
                            icon: const Icon(Icons.download_outlined),
                          ),
                          if (_canWrite)
                            IconButton(
                              tooltip: 'Elimina',
                              onPressed: () => unawaited(_delete(d)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.present});

  final bool present;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: present
            ? const Color(0xFF2E7D32)
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
      ),
    );
  }
}
