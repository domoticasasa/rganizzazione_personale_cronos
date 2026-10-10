import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/commesse_cig_cup_pdf_export.dart';
import '../services/supabase_service.dart';
import '../utils/modify_feedback.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/roles.dart';
import '../widgets/classic_app_bar_chrome.dart';

String _s(dynamic v) => (v ?? '').toString().trim();

class AdminCommesseCigCupPage extends StatefulWidget {
  const AdminCommesseCigCupPage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  State<AdminCommesseCigCupPage> createState() => _AdminCommesseCigCupPageState();
}

class _AdminCommesseCigCupPageState extends State<AdminCommesseCigCupPage> {
  bool _loading = true;
  String _search = '';
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Map<String, String> _commesseIdByCode = <String, String>{};

  bool get _effectiveReadOnly =>
      widget.readOnly || !isAnyAdminRole(widget.role ?? '');

  List<Map<String, dynamic>> get _filteredRows {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final tokens = <String>[
        _s(r['commessa_code']),
        _s(r['cig']),
        _s(r['cig_derivato']),
        _s(r['cup']),
        _s(r['cliente']),
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _loadCommesseMap() async {
    _commesseIdByCode.clear();
    final rows = await SupabaseService.client
        .from('commesse')
        .select('id_uuid,nome')
        .order('nome');
    for (final e in (rows as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = _s(m['id_uuid']);
      final code = _s(m['nome']).toUpperCase();
      if (id.isNotEmpty && code.isNotEmpty) {
        _commesseIdByCode[code] = id;
      }
    }
  }

  Future<void> _loadRows() async {
    final rows = await SupabaseService.client
        .from('commesse_cig_cup')
        .select()
        .eq('active', true)
        .order('commessa_code');
    _rows
      ..clear()
      ..addAll((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadCommesseMap();
      await _loadRows();
    } catch (e) {
      _snack('Errore caricamento: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _ensureCommessaExists(String code) async {
    final key = code.trim().toUpperCase();
    if (key.isEmpty) return null;
    final knownId = _commesseIdByCode[key];
    if (knownId != null && knownId.isNotEmpty) {
      return knownId;
    }
    final inserted = await SupabaseService.client
        .from('commesse')
        .insert(<String, dynamic>{
          'nome': key,
          'active': true,
        })
        .select('id_uuid')
        .single();
    final id = _s(inserted['id_uuid']);
    if (id.isNotEmpty) {
      _commesseIdByCode[key] = id;
      return id;
    }
    return null;
  }

  Future<void> _openEditDialog({Map<String, dynamic>? existing}) async {
    if (_effectiveReadOnly) return;
    final codeCtrl = TextEditingController(text: _s(existing?['commessa_code']));
    final codeFocus = FocusNode();
    final cigCtrl = TextEditingController(text: _s(existing?['cig']));
    final cigDerCtrl = TextEditingController(text: _s(existing?['cig_derivato']));
    final cupCtrl = TextEditingController(text: _s(existing?['cup']));
    final clienteCtrl = TextEditingController(text: _s(existing?['cliente']));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nuova commessa CIG/CUP' : 'Modifica commessa CIG/CUP'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                RawAutocomplete<String>(
                  textEditingController: codeCtrl,
                  focusNode: codeFocus,
                  optionsBuilder: (textEditingValue) {
                    final q = textEditingValue.text.trim().toUpperCase();
                    final allCodes = _commesseIdByCode.keys.toList(growable: false)
                      ..sort();
                    if (q.isEmpty) {
                      return allCodes.take(12);
                    }
                    return allCodes
                        .where((c) => c.contains(q))
                        .take(12);
                  },
                  onSelected: (value) => codeCtrl.text = value,
                  fieldViewBuilder: (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Commessa (libera o da elenco)',
                        hintText: 'Scrivi o seleziona (es. TE-03-24)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onFieldSubmitted(),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 560,
                            maxHeight: 260,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(option),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cigCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CIG',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cigDerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CIG derivato',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cupCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CUP',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: clienteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (ok != true) {
      codeCtrl.dispose();
      codeFocus.dispose();
      cigCtrl.dispose();
      cigDerCtrl.dispose();
      cupCtrl.dispose();
      clienteCtrl.dispose();
      return;
    }

    final code = codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _snack('Commessa obbligatoria.', error: true);
      return;
    }

    final commessaId = await _ensureCommessaExists(code);
    final payload = <String, dynamic>{
      'commessa_code': code,
      'commessa_id_uuid': commessaId,
      'cig': cigCtrl.text.trim(),
      'cig_derivato': cigDerCtrl.text.trim(),
      'cup': cupCtrl.text.trim(),
      'cliente': clienteCtrl.text.trim(),
      'active': true,
    };

    try {
      if (existing == null) {
        await SupabaseService.client.from('commesse_cig_cup').insert(payload);
        _snack('Riga inserita.');
      } else {
        await SupabaseService.client
            .from('commesse_cig_cup')
            .update(payload)
            .eq('id_uuid', existing['id_uuid']);
        _snack('Riga aggiornata.');
      }
      await _load();
    } catch (e) {
      _snack('Errore salvataggio: $e', error: true);
    } finally {
      codeCtrl.dispose();
      codeFocus.dispose();
      cigCtrl.dispose();
      cigDerCtrl.dispose();
      cupCtrl.dispose();
      clienteCtrl.dispose();
    }
  }

  String _exportFileStamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPdf() async {
    final items = _filteredRows;
    if (items.isEmpty) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final bytes = await buildCommesseCigCupPdfBytes(
        rows: items,
        searchFilter: _search.trim().isEmpty ? null : _search.trim(),
      );
      await FileSaver.instance.saveFile(
        name: 'Commesse_CIG_CUP_${_exportFileStamp()}',
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ModifyFeedback.success(
        context,
        kIsWeb
            ? 'Export PDF avviato (controlla i download del browser).'
            : 'Export PDF completato.',
      );
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export PDF: $e');
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> r) async {
    if (_effectiveReadOnly) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina riga'),
        content: Text('Eliminare la riga ${_s(r['commessa_code'])}?'),
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
      await SupabaseService.client
          .from('commesse_cig_cup')
          .delete()
          .eq('id_uuid', r['id_uuid']);
      _snack('Riga eliminata.');
      await _load();
    } catch (e) {
      _snack('Errore eliminazione: $e', error: true);
    }
  }

  String _cellText(dynamic v) {
    final t = _s(v);
    return t.isEmpty ? '—' : t;
  }

  Widget _commessaCell(Map<String, dynamic> r) {
    final inCommesse = _s(r['commessa_id_uuid']).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _s(r['commessa_code']),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (!inCommesse)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Non in anagrafica',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> items) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 24,
        ),
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 12,
          headingRowColor: WidgetStateProperty.all(
            theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          ),
          columns: [
            const DataColumn(label: Text('Commessa')),
            const DataColumn(label: Text('CIG')),
            const DataColumn(label: Text('CIG derivato')),
            const DataColumn(label: Text('CUP')),
            const DataColumn(label: Text('Cliente')),
            if (!_effectiveReadOnly) const DataColumn(label: Text('Azioni')),
          ],
          rows: items.map((r) {
            final cells = <DataCell>[
              DataCell(_commessaCell(r)),
              DataCell(Text(_cellText(r['cig']))),
              DataCell(Text(_cellText(r['cig_derivato']))),
              DataCell(Text(_cellText(r['cup']))),
              DataCell(Text(_cellText(r['cliente']))),
            ];
            if (!_effectiveReadOnly) {
              cells.add(
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Modifica',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEditDialog(existing: r),
                      ),
                      IconButton(
                        tooltip: 'Elimina',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteRow(r),
                      ),
                    ],
                  ),
                ),
              );
            }
            return DataRow(cells: cells);
          }).toList(growable: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Commesse CIG / CUP';
    final toolbarActions = <Widget>[
      IconButton(
        tooltip: 'Export PDF',
        onPressed: _loading ? null : _exportPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
      ),
      if (!_effectiveReadOnly)
        IconButton(
          tooltip: 'Nuova riga',
          onPressed: _loading ? null : () => _openEditDialog(),
          icon: const Icon(Icons.add),
        ),
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ];

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: toolbarActions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Text(pageTitle),
        actions: toolbarActions,
      )),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                labelText: 'Cerca commessa / CIG / CUP / cliente',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filteredRows.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nessun dato disponibile.'),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                  children: [_buildTable(_filteredRows)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
