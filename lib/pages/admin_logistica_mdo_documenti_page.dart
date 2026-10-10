import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_mdo_documenti_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Logistica → documenti per ogni mezzo d'opera ferroviario già in anagrafica.
class AdminLogisticaMdoDocumentiPage extends StatefulWidget {
  const AdminLogisticaMdoDocumentiPage({
    super.key,
    this.forceMobileLayout = false,
  });

  final bool forceMobileLayout;

  @override
  State<AdminLogisticaMdoDocumentiPage> createState() =>
      _AdminLogisticaMdoDocumentiPageState();
}

class _AdminLogisticaMdoDocumentiPageState
    extends State<AdminLogisticaMdoDocumentiPage> {
  bool _loadingMezzi = true;
  bool _loadingDocs = false;
  String? _error;
  String _search = '';
  List<MdoFerroviarioRef> _mezzi = const [];
  Map<String, int> _counts = const {};
  MdoFerroviarioRef? _selected;
  List<MdoDocumentoFile> _docs = const [];
  String? _uploadingTipo;

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
    unawaited(_loadMezzi());
  }

  Future<void> _loadMezzi() async {
    setState(() {
      _loadingMezzi = true;
      _error = null;
    });
    try {
      final mezzi = await LogisticaMdoDocumentiService.listMezzi();
      Map<String, int> counts = const {};
      try {
        counts = await LogisticaMdoDocumentiService.countByMezzo();
      } catch (_) {}
      if (!mounted) return;
      MdoFerroviarioRef? selected;
      final prevId = _selected?.id;
      if (prevId != null) {
        for (final m in mezzi) {
          if (m.id == prevId) {
            selected = m;
            break;
          }
        }
      }
      setState(() {
        _mezzi = mezzi;
        _counts = counts;
        _selected = selected;
        _loadingMezzi = false;
      });
      if (selected != null) await _loadDocs(selected.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMezzi = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshCounts() async {
    try {
      final counts = await LogisticaMdoDocumentiService.countByMezzo();
      if (!mounted) return;
      setState(() => _counts = counts);
    } catch (_) {}
  }

  Future<void> _loadDocs(String mdoId) async {
    setState(() {
      _loadingDocs = true;
    });
    try {
      final docs = await LogisticaMdoDocumentiService.listDocumenti(mdoId);
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loadingDocs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDocs = false;
        _docs = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Documenti: $e')),
      );
    }
  }

  List<MdoFerroviarioRef> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _mezzi;
    return _mezzi.where((m) {
      return m.matricolaInterna.toLowerCase().contains(q) ||
          m.targaRfi.toLowerCase().contains(q) ||
          m.descrizione.toLowerCase().contains(q) ||
          m.modello.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _select(MdoFerroviarioRef m) async {
    setState(() => _selected = m);
    await _loadDocs(m.id);
  }

  bool _guardWrite() {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
      return false;
    }
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo admin o logistica possono caricare.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _upload(
    String docTipo, {
    String? customTitolo,
    String? customDescrizione,
  }) async {
    if (!_guardWrite()) return;
    final mezzo = _selected;
    if (mezzo == null) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documenti',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    if (!LogisticaMdoDocumentiService.isAllowedFileName(file.name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato non supportato. Usa PDF, JPG, PNG o WEBP.'),
        ),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > LogisticaMdoDocumentiService.maxFileBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il file supera i 200 MB')),
      );
      return;
    }
    final uploadKey = docTipo == kMdoDocTipoAltro
        ? '$kMdoDocTipoAltro:${(customTitolo ?? '').trim().toLowerCase()}'
        : docTipo;
    setState(() => _uploadingTipo = uploadKey);
    try {
      await LogisticaMdoDocumentiService.upload(
        mdoId: mezzo.id,
        docTipo: docTipo,
        originalFileName: file.name,
        mimeType: file.mimeType,
        bytes: bytes,
        customTitolo: customTitolo,
        customDescrizione: customDescrizione,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Documento aggiunto. I file già presenti restano: cancellali tu se non servono più.',
          ),
        ),
      );
      await _loadDocs(mezzo.id);
      unawaited(_refreshCounts());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caricamento: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingTipo = null);
    }
  }

  Future<void> _addAltroDocumento() async {
    if (!_guardWrite()) return;
    final mezzo = _selected;
    if (mezzo == null) return;
    final titoloCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Altro documento'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titoloCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome documento',
                  hintText: 'Es. Certificato rumore, libretto…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descrizione (opzionale)',
                  hintText: 'Note, scadenza, riferimento…',
                  border: OutlineInputBorder(),
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
            child: const Text('Scegli file'),
          ),
        ],
      ),
    );
    final titolo = titoloCtrl.text.trim();
    final desc = descCtrl.text.trim();
    titoloCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || titolo.isEmpty) {
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inserisci il nome del documento.')),
        );
      }
      return;
    }
    await _upload(
      kMdoDocTipoAltro,
      customTitolo: titolo,
      customDescrizione: desc,
    );
  }

  List<(MdoDocumentoTipo tipo, List<MdoDocumentoFile> files)>
      _customSections() {
    final order = <String>[];
    final map = <String, List<MdoDocumentoFile>>{};
    for (final d in _docs) {
      if (!d.isAltro) continue;
      final titolo = (d.customTitolo ?? '').trim();
      if (titolo.isEmpty) continue;
      final k = titolo.toLowerCase();
      if (!map.containsKey(k)) order.add(k);
      map.putIfAbsent(k, () => []).add(d);
    }
    return [
      for (final k in order)
        (
          MdoDocumentoTipo(
            key: '$kMdoDocTipoAltro:$k',
            label: map[k]!.first.customTitolo ?? 'Altro',
            description: () {
              for (final e in map[k]!) {
                final d = (e.customDescrizione ?? '').trim();
                if (d.isNotEmpty) return d;
              }
              return null;
            }(),
          ),
          map[k]!,
        ),
    ];
  }

  Future<void> _delete(MdoDocumentoFile row) async {
    if (!_guardWrite()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina documento'),
        content: Text('Eliminare «${row.fileName}»? I vecchi file non si cancellano da soli.'),
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
      await LogisticaMdoDocumentiService.delete(row);
      if (!mounted) return;
      final mezzo = _selected;
      if (mezzo != null) {
        await _loadDocs(mezzo.id);
        unawaited(_refreshCounts());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eliminazione: $e')),
      );
    }
  }

  Future<void> _open(MdoDocumentoFile row) async {
    try {
      final url = await LogisticaMdoDocumentiService.signedUrl(row);
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

  Future<void> _download(MdoDocumentoFile row) async {
    try {
      final bytes = await LogisticaMdoDocumentiService.downloadBytes(row);
      final original = row.fileName.trim();
      var base = original;
      var ext = 'bin';
      final dot = original.lastIndexOf('.');
      if (dot > 0 && dot < original.length - 1) {
        base = original.substring(0, dot);
        ext = original.substring(dot + 1);
      }
      if (base.isEmpty) base = 'documento_mdo';
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
            title: 'Documenti MDO ferroviari',
          ),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loadingMezzi ? null : _loadMezzi,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: PageWithTopLogo(
        showLogo: true,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loadingMezzi
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
                        final split = c.maxWidth >= 880 && !widget.forceMobileLayout;
                        if (!split) {
                          if (_selected == null) return _mezziPane();
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
                                  label: const Text('Tutti i mezzi'),
                                ),
                              ),
                              Expanded(child: _docsPane()),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 340, child: _mezziPane()),
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

  Widget _mezziPane() {
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Cerca matricola, targa RFI, mezzo…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        Text(
          '${list.length} mezzi',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Nessun mezzo ferroviario.'))
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
                        Icons.train_outlined,
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
    final mezzo = _selected;
    if (mezzo == null) {
      return const Center(
        child: Text('Seleziona un mezzo a sinistra per vedere e caricare i documenti.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(mezzo.title, style: Theme.of(context).textTheme.titleLarge),
        if (mezzo.subtitle.isNotEmpty)
          Text(
            mezzo.subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        const SizedBox(height: 6),
        Text(
          'Puoi caricare più file per lo stesso tipo. I documenti vecchi restano '
          'finché non li elimini tu. Con «Aggiungi altro documento» puoi inserire '
          'un tipo non in elenco, con nome e descrizione.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (_canWrite) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => unawaited(_addAltroDocumento()),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi altro documento'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (_loadingDocs) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            children: [
              for (final tipo in kMdoDocumentoTipi)
                _TipoSection(
                  tipo: tipo,
                  files: _docs.where((d) => d.docTipo == tipo.key).toList(),
                  canWrite: _canWrite,
                  uploading: _uploadingTipo == tipo.key,
                  onUpload: () => unawaited(_upload(tipo.key)),
                  onOpen: _open,
                  onDownload: _download,
                  onDelete: _delete,
                ),
              for (final section in _customSections())
                _TipoSection(
                  tipo: section.$1,
                  files: section.$2,
                  canWrite: _canWrite,
                  uploading: _uploadingTipo == section.$1.key,
                  onUpload: () => unawaited(
                    _upload(
                      kMdoDocTipoAltro,
                      customTitolo: section.$1.label,
                      customDescrizione: section.$1.description,
                    ),
                  ),
                  onOpen: _open,
                  onDownload: _download,
                  onDelete: _delete,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TipoSection extends StatelessWidget {
  const _TipoSection({
    required this.tipo,
    required this.files,
    required this.canWrite,
    required this.uploading,
    required this.onUpload,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  });

  final MdoDocumentoTipo tipo;
  final List<MdoDocumentoFile> files;
  final bool canWrite;
  final bool uploading;
  final VoidCallback onUpload;
  final Future<void> Function(MdoDocumentoFile row) onOpen;
  final Future<void> Function(MdoDocumentoFile row) onDownload;
  final Future<void> Function(MdoDocumentoFile row) onDelete;

  @override
  Widget build(BuildContext context) {
    final hasFiles = files.isNotEmpty;
    const present = Color(0xFF2E7D32);
    final missing = Theme.of(context).colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: hasFiles ? present.withValues(alpha: 0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasFiles ? present : missing.withValues(alpha: 0.35),
          width: hasFiles ? 1.6 : 1,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: hasFiles,
        leading: _StatusDot(present: hasFiles),
        title: Text(
          tipo.label,
          style: TextStyle(
            fontWeight: hasFiles ? FontWeight.w700 : FontWeight.w500,
            color: hasFiles ? present : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasFiles
                  ? (files.length == 1
                      ? 'Presente · 1 file'
                      : 'Presente · ${files.length} file')
                  : 'Mancante',
              style: TextStyle(
                color: hasFiles ? present : missing,
                fontWeight: hasFiles ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if ((tipo.description ?? '').trim().isNotEmpty)
              Text(
                tipo.description!.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        children: [
          if (canWrite)
            ListTile(
              dense: true,
              leading: uploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              title: const Text('Carica documento'),
              subtitle: const Text('Aggiunge un file; non sostituisce quelli già presenti'),
              onTap: uploading ? null : onUpload,
            ),
          if (files.isEmpty)
            const ListTile(
              dense: true,
              title: Text('Nessun documento.'),
            )
          else
            for (final f in files)
              ListTile(
                dense: true,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(f.fileName),
                subtitle: Text(
                  [
                    formatDateTimeIt(f.uploadedAt),
                    if ((f.customDescrizione ?? '').isNotEmpty)
                      f.customDescrizione!,
                    if ((f.note ?? '').isNotEmpty) f.note!,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scarica',
                      onPressed: () => unawaited(onDownload(f)),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      tooltip: 'Apri',
                      onPressed: () => unawaited(onOpen(f)),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    if (canWrite)
                      IconButton(
                        tooltip: 'Elimina',
                        onPressed: () => unawaited(onDelete(f)),
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.present});

  final bool present;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    final grey = Theme.of(context).colorScheme.outline;
    return Tooltip(
      message: present ? 'Documento presente' : 'Documento mancante',
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: present ? green : Colors.transparent,
          border: Border.all(
            color: present ? green : grey,
            width: 2,
          ),
          boxShadow: present
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.45),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
