import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_assegnazione_attrezzature_documenti_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum _AttFilter { tutte, conPdf, senzaPdf }

class AdminLogisticaAssegnazioneAttrezzaturePage extends StatefulWidget {
  final bool forceMobileLayout;

  const AdminLogisticaAssegnazioneAttrezzaturePage({
    super.key,
    this.forceMobileLayout = false,
  });

  @override
  State<AdminLogisticaAssegnazioneAttrezzaturePage> createState() =>
      _AdminLogisticaAssegnazioneAttrezzaturePageState();
}

class _AdminLogisticaAssegnazioneAttrezzaturePageState
    extends State<AdminLogisticaAssegnazioneAttrezzaturePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _desktopVerticalCtrl = ScrollController();

  bool _loading = true;
  bool _uploading = false;
  String _search = '';
  _AttFilter _filter = _AttFilter.tutte;
  Timer? _searchDebounce;
  List<AttrezzaturaRef> _rows = const <AttrezzaturaRef>[];
  Map<String, int> _pdfCounts = <String, int>{};

  bool get _canWrite {
    final role = ClassicNavSessionCache.current?.role ?? '';
    return canEditAssegnazioneAttrezzature(role);
  }

  bool _narrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_loadRows());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _desktopVerticalCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _search = _searchCtrl.text);
    });
  }

  bool _guardWrite() {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
      return false;
    }
    if (!_canWrite) {
      ModifyFeedback.hint(context, 'Solo admin possono caricare PDF.');
      return false;
    }
    return true;
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final rows =
          await LogisticaAssegnazioneAttrezzatureDocumentiService
              .listAttrezzature();
      Map<String, int> counts = const {};
      try {
        counts = await LogisticaAssegnazioneAttrezzatureDocumentiService
            .countByAttrezzatura();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _pdfCounts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento: $e');
    }
  }

  List<AttrezzaturaRef> get _visibleRows {
    final k = _search.trim().toLowerCase();
    return _rows.where((a) {
      final count = _pdfCounts[a.id] ?? 0;
      if (_filter == _AttFilter.conPdf && count <= 0) return false;
      if (_filter == _AttFilter.senzaPdf && count > 0) return false;
      if (k.isEmpty) return true;
      final blob = [
        a.codiceCronos,
        a.descrizione,
        a.assegnatario,
        a.marca,
        a.modello,
        a.label,
      ].map((s) => s.toLowerCase());
      return blob.any((s) => s.contains(k));
    }).toList(growable: false);
  }

  Future<void> _openPdfDialog(AttrezzaturaRef att) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AssegnazioneAttPdfDialog(
        attrezzatura: att,
        canWrite: _canWrite,
        onChanged: () => _loadRows(showLoader: false),
      ),
    );
  }

  Future<void> _uploadPdfWithPicker() async {
    if (!_guardWrite()) return;
    if (_rows.isEmpty) {
      ModifyFeedback.hint(
        context,
        'Nessuna attrezzatura in anagrafica. Creane una in Lista attrezzature.',
      );
      return;
    }

    final result = await showDialog<_UploadMeta>(
      context: context,
      builder: (ctx) => _UploadPdfDialog(attrezzature: _rows),
    );
    if (result == null || !mounted) return;

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;
    if (!LogisticaAssegnazioneAttrezzatureDocumentiService.isAllowedFileName(
      file.name,
    )) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Carica un file PDF.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaAssegnazioneAttrezzatureDocumentiService.upload(
        originalFileName: file.name,
        bytes: bytes,
        attrezzaturaId: result.attrezzatura.id,
        attrezzaturaLabel: result.attrezzatura.label,
        note: result.note,
      );
      await _loadRows(showLoader: false);
      if (mounted) ModifyFeedback.hint(context, 'PDF caricato.');
      if (!mounted) return;
      await _openPdfDialog(result.attrezzatura);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Upload fallito: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _filterChips() {
    final conPdf = _pdfCounts.values.where((c) => c > 0).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tutte'),
          selected: _filter == _AttFilter.tutte,
          onSelected: (_) => setState(() => _filter = _AttFilter.tutte),
        ),
        ChoiceChip(
          label: Text('Con PDF ($conPdf)'),
          selected: _filter == _AttFilter.conPdf,
          onSelected: (_) => setState(() => _filter = _AttFilter.conPdf),
        ),
        ChoiceChip(
          label: const Text('Senza PDF'),
          selected: _filter == _AttFilter.senzaPdf,
          onSelected: (_) => setState(() => _filter = _AttFilter.senzaPdf),
        ),
      ],
    );
  }

  Widget _rowActions(AttrezzaturaRef att) {
    final pdfCount = _pdfCounts[att.id] ?? 0;
    return IconButton(
      tooltip: pdfCount > 0
          ? 'PDF assegnazione ($pdfCount)'
          : 'PDF assegnazione',
      icon: Badge(
        isLabelVisible: pdfCount > 0,
        label: Text('$pdfCount'),
        child: Icon(
          pdfCount > 0 ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
        ),
      ),
      onPressed: () => _openPdfDialog(att),
    );
  }

  Widget _desktopTable(List<AttrezzaturaRef> rows) {
    return DataTable2(
      headingRowHeight: 44,
      dataRowHeight: 64,
      columnSpacing: 16,
      horizontalMargin: 12,
      minWidth: 1000,
      scrollController: _desktopVerticalCtrl,
      isVerticalScrollBarVisible: true,
      isHorizontalScrollBarVisible: true,
      columns: const [
        DataColumn2(label: Text('Codice'), size: ColumnSize.S),
        DataColumn2(label: Text('Descrizione'), size: ColumnSize.L),
        DataColumn2(label: Text('Assegnatario'), size: ColumnSize.M),
        DataColumn2(label: Text('PDF'), size: ColumnSize.S),
        DataColumn2(label: Text('Azioni'), size: ColumnSize.S),
      ],
      rows: rows.map((a) {
        final pdfCount = _pdfCounts[a.id] ?? 0;
        return DataRow2(
          cells: [
            DataCell(Text(a.codiceCronos.isEmpty ? '—' : a.codiceCronos)),
            DataCell(Text(a.descrizione.isEmpty ? a.label : a.descrizione)),
            DataCell(
              Text(a.assegnatario.isEmpty ? 'Non assegnata' : a.assegnatario),
            ),
            DataCell(
              pdfCount > 0
                  ? TextButton.icon(
                      onPressed: () => _openPdfDialog(a),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: Text('$pdfCount'),
                    )
                  : TextButton(
                      onPressed: () => _openPdfDialog(a),
                      child: const Text('—'),
                    ),
            ),
            DataCell(_rowActions(a)),
          ],
        );
      }).toList(growable: false),
    );
  }

  Widget _mobileList(List<AttrezzaturaRef> rows) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 0, 12, _canWrite ? 88 : 16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = rows[index];
        return Card(
          child: ListTile(
            isThreeLine: true,
            title: Text(a.label),
            subtitle: Text(a.subtitle),
            trailing: _rowActions(a),
            onTap: () => _openPdfDialog(a),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final withPdf = _pdfCounts.values.where((c) => c > 0).length;

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(
            title: 'Assegnazione Attrezzature',
          ),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : () => _loadRows(),
              icon: const Icon(Icons.refresh),
            ),
            if (_canWrite)
              IconButton(
                tooltip: 'Carica PDF',
                onPressed: _uploading ? null : _uploadPdfWithPicker,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
              ),
          ],
        ),
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _uploadPdfWithPicker,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_uploading ? 'Caricamento…' : 'Carica PDF'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: logisticaFieldWidth(context),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Cerca codice, descrizione, assegnatario…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _filterChips(),
                const SizedBox(height: 8),
                Text(
                  '${rows.length} attrezzature · $withPdf con PDF'
                  '${_canWrite ? '' : ' · sola lettura (apri/scarica)'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(
                        child: Text(
                          _rows.isEmpty
                              ? 'Nessuna attrezzatura in anagrafica.'
                              : 'Nessun risultato con i filtri attuali.',
                        ),
                      )
                    : _narrowLayout(context)
                        ? _mobileList(rows)
                        : Padding(
                            padding: EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: _canWrite ? 88 : 16,
                            ),
                            child: _desktopTable(rows),
                          ),
          ),
        ],
      ),
    );
  }
}

class _UploadMeta {
  const _UploadMeta({required this.attrezzatura, required this.note});
  final AttrezzaturaRef attrezzatura;
  final String note;
}

class _UploadPdfDialog extends StatefulWidget {
  const _UploadPdfDialog({required this.attrezzature});

  final List<AttrezzaturaRef> attrezzature;

  @override
  State<_UploadPdfDialog> createState() => _UploadPdfDialogState();
}

class _UploadPdfDialogState extends State<_UploadPdfDialog> {
  final _noteCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  AttrezzaturaRef? _selected;
  String _filter = '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  List<AttrezzaturaRef> get _filtered {
    final k = _filter.trim().toLowerCase();
    if (k.isEmpty) return widget.attrezzature;
    return widget.attrezzature.where((a) {
      final blob = [
        a.codiceCronos,
        a.descrizione,
        a.assegnatario,
        a.marca,
        a.modello,
        a.label,
      ].map((s) => s.toLowerCase());
      return blob.any((s) => s.contains(k));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return AlertDialog(
      title: const Text('Nuovo PDF assegnazione'),
      content: SizedBox(
        width: logisticaDialogWidth(context, desktop: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _filterCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Filtra attrezzatura',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: list.isEmpty
                  ? const Text('Nessuna attrezzatura trovata.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final selected = _selected?.id == a.id;
                        return ListTile(
                          selected: selected,
                          title: Text(a.label),
                          subtitle: Text(a.subtitle),
                          onTap: () => setState(() => _selected = a),
                          trailing: selected
                              ? const Icon(Icons.check_circle)
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (opzionale)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                    context,
                    _UploadMeta(
                      attrezzatura: _selected!,
                      note: _noteCtrl.text.trim(),
                    ),
                  ),
          child: const Text('Scegli PDF'),
        ),
      ],
    );
  }
}

class _AssegnazioneAttPdfDialog extends StatefulWidget {
  final AttrezzaturaRef attrezzatura;
  final bool canWrite;
  final VoidCallback onChanged;

  const _AssegnazioneAttPdfDialog({
    required this.attrezzatura,
    required this.canWrite,
    required this.onChanged,
  });

  @override
  State<_AssegnazioneAttPdfDialog> createState() =>
      _AssegnazioneAttPdfDialogState();
}

class _AssegnazioneAttPdfDialogState extends State<_AssegnazioneAttPdfDialog> {
  bool _loading = true;
  bool _uploading = false;
  List<AssegnazioneAttrezzaturaDocumento> _docs =
      const <AssegnazioneAttrezzaturaDocumento>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs =
          await LogisticaAssegnazioneAttrezzatureDocumentiService
              .listForAttrezzatura(widget.attrezzatura.id);
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore documenti: $e');
    }
  }

  bool _guardWrite() {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
      return false;
    }
    if (!widget.canWrite) {
      ModifyFeedback.hint(context, 'Solo admin possono caricare PDF.');
      return false;
    }
    return true;
  }

  Future<void> _upload() async {
    if (!_guardWrite()) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;
    if (!LogisticaAssegnazioneAttrezzatureDocumentiService.isAllowedFileName(
      file.name,
    )) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Carica un file PDF.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaAssegnazioneAttrezzatureDocumentiService.upload(
        originalFileName: file.name,
        bytes: bytes,
        attrezzaturaId: widget.attrezzatura.id,
        attrezzaturaLabel: widget.attrezzatura.label,
      );
      widget.onChanged();
      await _load();
      if (mounted) ModifyFeedback.hint(context, 'PDF caricato.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Upload fallito: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(AssegnazioneAttrezzaturaDocumento doc) async {
    try {
      final url =
          await LogisticaAssegnazioneAttrezzatureDocumentiService.signedUrl(
        doc,
      );
      final launched = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!launched && mounted) {
        ModifyFeedback.error(context, 'Impossibile aprire il PDF.');
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Apertura fallita: $e');
    }
  }

  Future<void> _download(AssegnazioneAttrezzaturaDocumento doc) async {
    try {
      final bytes =
          await LogisticaAssegnazioneAttrezzatureDocumentiService.downloadBytes(
        doc,
      );
      var base = doc.fileName.trim();
      if (base.toLowerCase().endsWith('.pdf')) {
        base = base.substring(0, base.length - 4);
      }
      if (base.isEmpty) base = 'assegnazione_attrezzature';
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: base,
        bytes: bytes,
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ModifyFeedback.hint(context, 'Download completato.');
        return;
      }
      final url =
          await LogisticaAssegnazioneAttrezzatureDocumentiService.signedUrl(
        doc,
      );
      final launched = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!mounted) return;
      ModifyFeedback.hint(
        context,
        launched ? 'PDF aperto in una nuova scheda.' : 'Download annullato.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Download fallito: $e');
    }
  }

  Future<void> _delete(AssegnazioneAttrezzaturaDocumento doc) async {
    if (!_guardWrite()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina PDF'),
        content: Text('Eliminare «${doc.fileName}»?'),
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
      await LogisticaAssegnazioneAttrezzatureDocumentiService.delete(doc);
      widget.onChanged();
      await _load();
      if (mounted) ModifyFeedback.hint(context, 'PDF eliminato.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Eliminazione fallita: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF assegnazione'),
      content: SizedBox(
        width: logisticaDialogWidth(context, desktop: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.attrezzatura.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.attrezzatura.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!widget.canWrite) ...[
              const SizedBox(height: 8),
              Text(
                'Sola lettura: puoi aprire o scaricare i PDF.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (widget.canWrite)
              FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_uploading ? 'Caricamento…' : 'Carica PDF'),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_docs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nessun PDF caricato.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = _docs[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(doc.fileName),
                      subtitle: Text(formatDateTimeIt(doc.uploadedAt)),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'Apri',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _open(doc),
                          ),
                          IconButton(
                            tooltip: 'Scarica',
                            icon: const Icon(Icons.download_outlined),
                            onPressed: () => _download(doc),
                          ),
                          if (widget.canWrite)
                            IconButton(
                              tooltip: 'Elimina',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(doc),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}
