import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/confirm_sound_service.dart';
import '../services/pos_commessa_mdo_service.dart';
import '../services/pos_mdo_ferroviari_import_parser.dart';
import '../services/supabase_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/responsive.dart';
import '../utils/roles.dart';
import '../utils/gestopro_page_chrome.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminPosMdoFerroviariPage extends StatefulWidget {
  const AdminPosMdoFerroviariPage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  State<AdminPosMdoFerroviariPage> createState() => _AdminPosMdoFerroviariPageState();
}

class _AdminPosMdoFerroviariPageState extends State<AdminPosMdoFerroviariPage> {
  bool _loading = true;
  String? _commessaId;
  Map<String, String> _commesse = {};
  List<PosCommessaMdoRiepilogo> _riepilogoCommesse = [];
  Map<String, Map<String, dynamic>> _mdoById = {};
  List<PosCommessaMdoRow> _righe = [];
  DateTime? _ultimoAggiornamentoApp;
  String? _userUuid;
  final TextEditingController _searchCtrl = TextEditingController();
  String _commessaListaFiltro = 'ALL';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _effectiveReadOnly =>
      widget.readOnly ||
      (widget.role != null &&
          widget.role!.trim().isNotEmpty &&
          !canManagePosMdoFerroviariLista(widget.role!));

  List<PosCommessaMdoRow> get _righeFiltrate {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _righe;
    return _righe.where((r) {
      return r.displayLabel.toLowerCase().contains(q) ||
          r.matricolaInterna.toLowerCase().contains(q) ||
          r.targaRfi.toLowerCase().contains(q) ||
          (r.proprietaImport ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _resolveUserUuid();
      _commesse = await PosCommessaMdoService.loadCommesseAttive();
      _mdoById = await PosCommessaMdoService.loadMdoAttivi();
      _riepilogoCommesse =
          await PosCommessaMdoService.loadCommesseRiepilogo(_commesse);
      if (_commessaId != null && _commesse.containsKey(_commessaId)) {
        await _reloadLista();
      }
    } catch (e) {
      _snack('Errore caricamento: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveUserUuid() async {
    final auth = SupabaseService.client.auth.currentUser;
    if (auth != null) {
      final row = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('auth_id', auth.id)
          .maybeSingle();
      final u = (row?['id_uuid'] ?? '').toString().trim();
      if (u.isNotEmpty) {
        _userUuid = u;
        return;
      }
    }
    final uid = widget.userId;
    if (uid != null) {
      final row = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('id', uid)
          .maybeSingle();
      _userUuid = (row?['id_uuid'] ?? '').toString().trim();
    }
  }

  Future<void> _reloadLista() async {
    final cid = _commessaId;
    if (cid == null || cid.isEmpty) return;
    _ultimoAggiornamentoApp =
        await PosCommessaMdoService.loadUltimoAggiornamentoApp(cid);
    _righe = await PosCommessaMdoService.loadMezziPos(cid);
    _riepilogoCommesse =
        await PosCommessaMdoService.loadCommesseRiepilogo(_commesse);
    if (mounted) setState(() {});
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _onCommessaChanged(String? id) async {
    setState(() {
      _commessaId = id;
      _righe = [];
      _ultimoAggiornamentoApp = null;
      _searchCtrl.clear();
    });
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _reloadLista();
    } catch (e) {
      _snack('Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final bytes = PosMdoFerroviariImportParser.buildTemplateExcelBytes();
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Modello_Elenco_MdO_Ferroviari_POS',
        bytes: bytes,
      );
      if (!mounted || !saved) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      _snack(
        path.isEmpty
            ? 'Modello Excel scaricato.'
            : 'Modello Excel scaricato:\n$path',
      );
    } catch (e) {
      _snack('Errore download modello: $e', error: true);
    }
  }

  Future<void> _importFile() async {
    final cid = _commessaId;
    if (cid == null || cid.isEmpty) {
      _snack('Seleziona prima la commessa', error: true);
      return;
    }
    const types = <XTypeGroup>[
      XTypeGroup(label: 'Excel', extensions: <String>['xlsx', 'xls']),
    ];
    final file = await openFile(acceptedTypeGroups: types);
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final parsed = await PosMdoFerroviariImportParser.parseFile(
        fileName: file.name,
        bytes: bytes,
      );
      if (parsed.righe.isEmpty) {
        _snack(parsed.avviso ?? 'File senza righe utili', error: true);
        return;
      }
      final previews = PosCommessaMdoService.previewImportMatches(
        righe: parsed.righe,
        mdoById: _mdoById,
      );
      if (!mounted) return;
      final confirmed = await showDialog<List<PosMdoImportMatchPreview>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ImportPreviewDialog(
          fileName: file.name,
          dataLista: parsed.dataUltimoAggiornamento,
          previews: previews,
          mdoById: _mdoById,
        ),
      );
      if (confirmed == null) return;

      final result = await PosCommessaMdoService.applyImport(
        commessaId: cid,
        previews: confirmed,
        dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
        userUuid: _userUuid,
      );
      await _reloadLista();
      final parts = <String>[
        if (result.added > 0) '${result.added} nuovi',
        if (result.updated > 0) '${result.updated} aggiornati',
        if (result.importOnly > 0) '${result.importOnly} solo dati file',
        if (result.skipped > 0) '${result.skipped} saltati',
      ];
      _snack(
        parts.isEmpty
            ? 'Import completato (nessuna modifica)'
            : 'Import completato: ${parts.join(', ')}',
      );
    } catch (e) {
      _snack('Import non riuscito: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMezzoManuale() async {
    final cid = _commessaId;
    if (cid == null) return;
    final existing = _righe.map((r) => r.mdoId).toSet();
    final available = _mdoById.entries
        .where((e) => !existing.contains(e.key))
        .map((e) => MapEntry(e.key, PosCommessaMdoService.mdoLabel(e.value)))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (available.isEmpty) {
      _snack('Tutti i mezzi attivi sono già in lista', error: true);
      return;
    }

    String? selected = available.first.key;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi mezzo al POS'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(
            labelText: 'MdO ferroviario',
            border: OutlineInputBorder(),
          ),
          items: available
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => selected = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aggiungi')),
        ],
      ),
    );
    if (ok != true || selected == null) return;

    try {
      final m = _mdoById[selected!]!;
      await PosCommessaMdoService.addMezzo(
        commessaId: cid,
        mdoId: selected!,
        codificaImport: (m['matricola_interna'] ?? '').toString(),
        targaImport: (m['codice_identificativo_targa_rfi'] ?? '').toString(),
        descrizioneImport: (m['descrizione_mezzo'] ?? '').toString(),
        createdByUserUuid: _userUuid,
      );
      await _reloadLista();
      _snack('Mezzo aggiunto');
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  Future<void> _removeRow(PosCommessaMdoRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi dal POS'),
        content: Text('Rimuovere ${row.displayLabel} da questa commessa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PosCommessaMdoService.removeMezzo(row.id);
      await _reloadLista();
      _snack('Rimosso');
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  static const List<String> _commessaFiltri = <String>['ALL', 'TE', 'TLC', 'IS', 'LFM'];

  String _commessaCategoria(String nome) {
    final up = nome.trim().toUpperCase();
    for (final code in _commessaFiltri.where((c) => c != 'ALL')) {
      if (up.startsWith('$code-') || up.startsWith('$code ')) return code;
    }
    return 'ALTRE';
  }

  @override
  Widget build(BuildContext context) {
    final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
    final canEdit = !_effectiveReadOnly;
    final narrow = useMobileUi(context);
    final pad = narrow ? 12.0 : 16.0;
    final filtrate = _righeFiltrate;
    final searchActive = _searchCtrl.text.trim().isNotEmpty;

    final pageTitle = _effectiveReadOnly
        ? (narrow ? 'MdO POS (lettura)' : 'Elenco MdO Ferroviari POS (sola lettura)')
        : (narrow ? 'MdO POS' : 'Elenco MdO Ferroviari POS');
    final refreshAction = IconButton(
      tooltip: 'Ricarica',
      onPressed: _loading ? null : _bootstrap,
      icon: const Icon(Icons.refresh),
    );

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: [refreshAction],
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text(pageTitle),
        actions: [refreshAction],
      )),
      body: _loading && _commesse.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 16),
                    children: [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(narrow ? 12 : 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                narrow ? '1. Seleziona commessa' : '1. Seleziona commessa (cantiere)',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              CommessaUuidAutocompleteField(
                                commesseByUuid: _commesse,
                                selectedUuid: _commessaId,
                                labelText: narrow ? 'Commessa' : 'Commessa (scrivi e seleziona)',
                                onSelected: _onCommessaChanged,
                              ),
                              if (_commessaId != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _ultimoAggiornamentoApp != null
                                      ? 'Ultimo aggiornamento in app: ${dateTimeFmt.format(_ultimoAggiornamentoApp!)}'
                                      : 'Ultimo aggiornamento in app: da inserire',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  searchActive
                                      ? '${filtrate.length} di ${_righe.length} mezzi'
                                      : '${_righe.length} mezzi nel POS di questa commessa',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_commessaId == null) ...[
                        const SizedBox(height: 12),
                        _buildTemplateHelpCard(narrow),
                        const SizedBox(height: 12),
                        _buildCommesseLista(narrow, dateTimeFmt),
                      ],
                      if (_commessaId != null) ...[
                        if (canEdit) _buildActionButtons(narrow),
                        if (!canEdit) ...[
                          const SizedBox(height: 12),
                          _buildTemplateHelpCard(narrow, compact: true),
                        ],
                        if (_righe.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              labelText: 'Cerca mezzo',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: searchActive
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: _searchCtrl.clear,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_loading)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ))
                        else if (_righe.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Nessun mezzo in POS per questa commessa. Usa Import o Aggiungi mezzo.',
                              ),
                            ),
                          )
                        else if (filtrate.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text('Nessun risultato per «${_searchCtrl.text.trim()}».'),
                            ),
                          )
                        else
                          ...filtrate.map((r) => _buildMezzoCard(r, canEdit, narrow)),
                      ],
                    ],
                  ),
    );
  }

  Widget _buildTemplateHelpCard(bool narrow, {bool compact = false}) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              compact ? 'Modello import Excel' : 'Import elenco MdO da Excel',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!compact) ...[
              const SizedBox(height: 6),
              const Text(
                'Scarica il modello (allegato 02.3) con codifica, targa/matricola, '
                'descrizione e proprietà/noleggio.',
                style: TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text(narrow ? 'Modello Excel' : 'Scarica modello Excel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool narrow) {
    final importBtn = FilledButton.icon(
      onPressed: _importFile,
      icon: const Icon(Icons.upload_file),
      label: Text(narrow ? 'Import Excel' : 'Import Excel'),
    );
    final templateBtn = OutlinedButton.icon(
      onPressed: _downloadTemplate,
      icon: const Icon(Icons.download_outlined),
      label: Text(narrow ? 'Modello' : 'Scarica modello Excel'),
    );
    final addBtn = OutlinedButton.icon(
      onPressed: _addMezzoManuale,
      icon: const Icon(Icons.train_outlined),
      label: Text(narrow ? 'Aggiungi' : 'Aggiungi mezzo'),
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          importBtn,
          const SizedBox(height: 8),
          templateBtn,
          const SizedBox(height: 8),
          addBtn,
        ],
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [importBtn, templateBtn, addBtn]);
  }

  Widget _buildCommesseLista(bool narrow, DateFormat dateTimeFmt) {
    final listaFiltrata = _commessaListaFiltro == 'ALL'
        ? _riepilogoCommesse
        : _riepilogoCommesse
            .where((r) => _commessaCategoria(r.nome) == _commessaListaFiltro)
            .toList();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Elenco commesse', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commessaFiltri
                  .map(
                    (f) => ChoiceChip(
                      label: Text(f == 'ALL' ? 'Tutte' : f),
                      selected: _commessaListaFiltro == f,
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _commessaListaFiltro = f);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            for (final r in listaFiltrata)
              ListTile(
                title: Text(r.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${r.mezziCount} mezzi'),
                trailing: Text(
                  r.ultimoAggiornamentoInApp != null
                      ? dateTimeFmt.format(r.ultimoAggiornamentoInApp!)
                      : 'da inserire',
                  style: TextStyle(
                    fontSize: 12,
                    color: r.ultimoAggiornamentoInApp != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () => _onCommessaChanged(r.commessaId),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMezzoCard(PosCommessaMdoRow r, bool canEdit, bool narrow) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(r.displayLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${r.matricolaInterna.isEmpty ? (r.codificaImport ?? '—') : r.matricolaInterna} · '
          '${r.targaRfi.isEmpty ? (r.targaImport ?? '—') : r.targaRfi}',
        ),
        trailing: canEdit
            ? IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                onPressed: () => _removeRow(r),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('Codifica', r.matricolaInterna.isEmpty ? r.codificaImport : r.matricolaInterna),
                _detailLine('Targa / matricola RFI', r.targaRfi.isEmpty ? r.targaImport : r.targaRfi),
                _detailLine('Descrizione', r.descrizioneMezzo.isEmpty ? r.descrizioneImport : r.descrizioneMezzo),
                _detailLine('Proprietà / noleggio', r.proprietaImport),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String? value) {
    final v = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
          children: [TextSpan(text: v.isEmpty ? '—' : v)],
        ),
      ),
    );
  }
}

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.fileName,
    required this.previews,
    required this.mdoById,
    this.dataLista,
  });

  final String fileName;
  final DateTime? dataLista;
  final List<PosMdoImportMatchPreview> previews;
  final Map<String, Map<String, dynamic>> mdoById;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late List<PosMdoImportMatchPreview> _items;

  @override
  void initState() {
    super.initState();
    _items = List<PosMdoImportMatchPreview>.from(widget.previews);
  }

  Set<String> get _usedMdoIds =>
      _items.where((p) => p.matched).map((p) => p.mdoId!).toSet();

  int get _importCount => _items.length;

  List<MapEntry<String, String>> get _mdoOptions {
    return widget.mdoById.entries
        .map((e) => MapEntry(e.key, PosCommessaMdoService.mdoLabel(e.value)))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return AlertDialog(
      title: const Text('Anteprima import MdO'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${widget.fileName}'),
            if (widget.dataLista != null)
              Text('Data lista: ${dateFmt.format(widget.dataLista!)}'),
            Text('Righe: ${_items.length} · Da importare: $_importCount'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final p = _items[i];
                  final imp = p.importRow;
                  final label =
                      '${imp.codifica} · ${imp.targaMatricola} · ${imp.descrizione}';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (p.matched)
                            Text('→ ${p.mdoLabel}', style: const TextStyle(fontSize: 13))
                          else ...[
                            const Text(
                              'Nessun abbinamento automatico — verrà importato con i dati del file',
                              style: TextStyle(fontSize: 13, color: Colors.orange),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Opzionale: collega a un MdO in anagrafica',
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                            ),
                          ],
                          if (!p.matched) ...[
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Seleziona mezzo in anagrafica',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: _mdoOptions
                                  .where((e) =>
                                      !_usedMdoIds.contains(e.key) ||
                                      e.key == p.mdoId)
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id == null) return;
                                setState(() {
                                  _items[i] = p.copyWith(
                                    mdoId: id,
                                    mdoLabel: PosCommessaMdoService.mdoLabel(
                                      widget.mdoById[id]!,
                                    ),
                                  );
                                });
                              },
                            ),
                          ],
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(
          onPressed: _importCount > 0 ? () => Navigator.pop(context, _items) : null,
          child: Text('Importa $_importCount'),
        ),
      ],
    );
  }
}
