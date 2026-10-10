import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bacheca_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminBachecaPage extends StatefulWidget {
  const AdminBachecaPage({
    super.key,
    this.forceMobileLayout = false,
    this.readOnly = false,
  });

  final bool forceMobileLayout;
  final bool readOnly;

  @override
  State<AdminBachecaPage> createState() => _AdminBachecaPageState();
}

class _AdminBachecaPageState extends State<AdminBachecaPage> {
  bool _loading = true;
  String? _error;
  List<BachecaPost> _posts = const [];

  bool get _canWrite {
    if (widget.readOnly) return false;
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) return false;
    // Catalogo hub già filtrato; RLS enforce can_write_bacheca().
    return true;
  }

  bool get _compact {
    if (widget.forceMobileLayout) return true;
    return MediaQuery.sizeOf(context).width < 720;
  }

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
      final rows = await BachecaService.list(onlyActive: !_canWrite);
      await BachecaService.markSeen();
      if (!mounted) return;
      setState(() {
        _posts = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _guardWrite() {
    if (_canWrite) return true;
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
    } else {
      ModifyFeedback.hint(context, 'Solo consultazione');
    }
    return false;
  }

  Future<void> _openEditor({BachecaPost? existing}) async {
    if (!_guardWrite()) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BachecaEditorDialog(existing: existing),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(BachecaPost post) async {
    if (!_guardWrite()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina comunicazione'),
        content: Text('Eliminare «${post.titolo}»?'),
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
      await BachecaService.delete(post);
      if (!mounted) return;
      ModifyFeedback.success(context, 'Comunicazione eliminata');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore eliminazione: $e')),
      );
    }
  }

  Future<void> _openAttachment(BachecaPost post) async {
    try {
      final url = await BachecaService.signedUrl(post.filePath);
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allegato non disponibile')),
        );
        return;
      }
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile aprire allegato: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Bacheca'),
          actions: [
            IconButton(
              tooltip: 'Ricarica',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
            if (_canWrite)
              IconButton(
                tooltip: 'Nuova comunicazione',
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
              ),
          ],
        ),
      ),
      floatingActionButton: _canWrite && _compact
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: kClassicAppBarColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuova'),
            )
          : null,
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _posts.isEmpty
                    ? const Center(
                        child: Text('Nessuna comunicazione in bacheca'),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          _canWrite && _compact ? 88 : 24,
                        ),
                        itemCount: _posts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final p = _posts[i];
                          return Card(
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: kClassicAppBarColor
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.campaign_outlined,
                                          color: kClassicAppBarColor,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.titolo,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (p.publishedAt != null)
                                              Text(
                                                df.format(p.publishedAt!),
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (_canWrite)
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              _openEditor(existing: p);
                                            }
                                            if (v == 'delete') _delete(p);
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Modifica'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Elimina'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (p.corpo.trim().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      p.corpo,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  if (p.hasAttachment) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => _openAttachment(p),
                                      icon: Icon(
                                        p.isPdf
                                            ? Icons.picture_as_pdf_outlined
                                            : Icons.image_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        p.fileName.isEmpty
                                            ? 'Apri allegato'
                                            : p.fileName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _BachecaEditorDialog extends StatefulWidget {
  const _BachecaEditorDialog({this.existing});

  final BachecaPost? existing;

  @override
  State<_BachecaEditorDialog> createState() => _BachecaEditorDialogState();
}

class _BachecaEditorDialogState extends State<_BachecaEditorDialog> {
  late final TextEditingController _titolo;
  late final TextEditingController _corpo;
  bool _saving = false;
  bool _removeAttachment = false;
  String? _pickedName;
  String? _pickedMime;
  Uint8List? _pickedBytes;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titolo = TextEditingController(text: e?.titolo ?? '');
    _corpo = TextEditingController(text: e?.corpo ?? '');
  }

  @override
  void dispose() {
    _titolo.dispose();
    _corpo.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Allegati',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    if (!BachecaService.isAllowedFileName(file.name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato non supportato. Usa PDF, JPG, PNG o WEBP.'),
        ),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > BachecaService.maxFileBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il file supera i 200 MB')),
      );
      return;
    }
    setState(() {
      _pickedName = file.name;
      _pickedMime = file.mimeType;
      _pickedBytes = bytes;
      _removeAttachment = false;
    });
  }

  Future<void> _save() async {
    final titolo = _titolo.text.trim();
    if (titolo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un titolo')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await BachecaService.create(
          titolo: titolo,
          corpo: _corpo.text,
          originalFileName: _pickedName,
          mimeType: _pickedMime,
          bytes: _pickedBytes,
          notify: true,
        );
      } else {
        await BachecaService.update(
          existing: existing,
          titolo: titolo,
          corpo: _corpo.text,
          removeAttachment: _removeAttachment,
          originalFileName: _pickedName,
          mimeType: _pickedMime,
          bytes: _pickedBytes,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final hasExistingFile =
        existing != null && existing.hasAttachment && !_removeAttachment;
    final attachmentLabel = _pickedName ??
        (hasExistingFile ? existing.fileName : null);

    return AlertDialog(
      title: Text(existing == null ? 'Nuova comunicazione' : 'Modifica comunicazione'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titolo,
                decoration: const InputDecoration(
                  labelText: 'Titolo *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _corpo,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Messaggio',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        attachmentLabel == null
                            ? 'Allega foto o PDF'
                            : 'Cambia allegato',
                      ),
                    ),
                    if (attachmentLabel != null)
                      Chip(
                        label: Text(attachmentLabel),
                        onDeleted: _saving
                            ? null
                            : () => setState(() {
                                  _pickedName = null;
                                  _pickedMime = null;
                                  _pickedBytes = null;
                                  if (hasExistingFile ||
                                      (existing?.hasAttachment ?? false)) {
                                    _removeAttachment = true;
                                  }
                                }),
                      ),
                  ],
                ),
              ),
              if (existing == null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Alla pubblicazione verrà inviata una notifica a tutti.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pubblica'),
        ),
      ],
    );
  }
}
