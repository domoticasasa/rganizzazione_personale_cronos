import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/logistica_sim_documenti_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../utils/simple_excel_table_io.dart';
import '../widgets/app_logo.dart';

/// Gestione SIM / linee telefoniche (Logistica).
class AdminLogisticaSimPage extends StatefulWidget {
  final bool forceMobileLayout;

  const AdminLogisticaSimPage({super.key, this.forceMobileLayout = false});

  @override
  State<AdminLogisticaSimPage> createState() => _AdminLogisticaSimPageState();
}

class _AdminLogisticaSimPageState extends State<AdminLogisticaSimPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  Map<String, int> _pdfCounts = <String, int>{};

  bool get _canEdit =>
      canEditLogisticaSim(currentSessionRole() ?? '');

  bool get _useMobile =>
      widget.forceMobileLayout ||
      MediaQuery.sizeOf(context).shortestSide < 700;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRows());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('logistica_sim')
          .select(
            'id_uuid,numero_linea,assegnatario,assegnatario_user_uuid,'
            'data_assegnazione,note,active,updated_at',
          )
          .eq('active', true)
          .order('assegnatario', ascending: true)
          .order('numero_linea', ascending: true);
      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var counts = <String, int>{};
      try {
        counts = await LogisticaSimDocumentiService.countBySim();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = list;
        _pdfCounts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento SIM: $e');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final blob =
          '${_s(r['numero_linea'])} ${_s(r['assegnatario'])} ${_s(r['note'])}'
              .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  bool _isDisponibile(Map<String, dynamic> r) {
    final a = _s(r['assegnatario']).toUpperCase();
    return a.contains('DISPONIBILE') || a.isEmpty;
  }

  Future<void> _openPdfDialog(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SimPdfDialog(
        row: row,
        canWrite: _canEdit,
        onChanged: () => unawaited(_loadRows()),
      ),
    );
  }

  String _normalizeNumero(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    // Excel a volte lascia float "3397998105.0"
    if (digits.endsWith('0') && raw.contains('.')) {
      final asDouble = double.tryParse(raw.replaceAll(',', '.'));
      if (asDouble != null && asDouble == asDouble.roundToDouble()) {
        return asDouble.round().toString();
      }
    }
    return digits;
  }

  String? _pickKey(Map<String, String> row, List<String> candidates) {
    for (final e in row.entries) {
      final k = e.key.toLowerCase().trim();
      for (final c in candidates) {
        if (k == c || k.contains(c)) return e.value;
      }
    }
    return null;
  }

  Future<void> _importAssegnazioniExcel() async {
    if (!_canEdit) {
      await showAdminVistaReadOnlyDialog(context);
      return;
    }
    if (!await ensureCanPersist(context)) return;

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Excel',
          extensions: ['xlsx', 'xls'],
        ),
      ],
    );
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final parsed = SimpleExcelTableIo.parseTable(Uint8List.fromList(bytes));
      if (parsed.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        ModifyFeedback.hint(
          context,
          'File vuoto o senza intestazioni. '
          'Serve una colonna numero (es. «N. linee») e una «Assegnatario».',
        );
        return;
      }

      final byNumero = <String, Map<String, dynamic>>{};
      for (final r in _rows) {
        final n = _normalizeNumero(_s(r['numero_linea']));
        if (n.isNotEmpty) byNumero[n] = r;
      }

      var updated = 0;
      var inserted = 0;
      var skipped = 0;
      final today = DateTime.now();
      final todayIso =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      for (final row in parsed) {
        final numRaw = _pickKey(row, const [
              'n. linee',
              'n linee',
              'numero',
              'linea',
              'telefono',
              'sim',
              'msisdn',
            ]) ??
            '';
        final assRaw = _pickKey(row, const [
              'assegnatario',
              'assegnatari',
              'dipendente',
              'nominativo',
              'nome',
            ]) ??
            '';
        final numero = _normalizeNumero(numRaw);
        final assegnatario = assRaw.trim();
        if (numero.isEmpty) {
          skipped++;
          continue;
        }

        final existing = byNumero[numero];
        if (existing != null) {
          await _supa.from('logistica_sim').update({
            'assegnatario': assegnatario.isEmpty ? null : assegnatario,
            'data_assegnazione': assegnatario.isEmpty ? null : todayIso,
          }).eq('id_uuid', _s(existing['id_uuid']));
          updated++;
        } else {
          await _supa.from('logistica_sim').insert({
            'numero_linea': numero,
            'assegnatario': assegnatario.isEmpty ? null : assegnatario,
            'data_assegnazione': assegnatario.isEmpty ? null : todayIso,
            'active': true,
          });
          inserted++;
        }
      }

      await _loadRows();
      if (!mounted) return;
      ModifyFeedback.success(
        context,
        'Import Excel: $updated aggiornate, $inserted nuove'
        '${skipped > 0 ? ', $skipped ignorate' : ''}.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Import Excel fallito: $e');
    }
  }

  Future<void> _clearAllAssegnazioni() async {
    if (!_canEdit) {
      await showAdminVistaReadOnlyDialog(context);
      return;
    }
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Svuota assegnazioni'),
        content: const Text(
          'Rimuovere tutti gli assegnatari dalle SIM attive?\n'
          'I numeri restano; potrai ricaricarli da Excel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa
          .from('logistica_sim')
          .update({
            'assegnatario': null,
            'data_assegnazione': null,
          })
          .eq('active', true);
      await _loadRows();
      if (!mounted) return;
      ModifyFeedback.success(context, 'Assegnazioni svuotate.');
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    if (!_canEdit) {
      await showAdminVistaReadOnlyDialog(context);
      return;
    }
    if (!await ensureCanPersist(context)) return;

    final isNew = existing == null;
    final numeroCtrl =
        TextEditingController(text: _s(existing?['numero_linea']));
    final assegnatarioCtrl =
        TextEditingController(text: _s(existing?['assegnatario']));
    final noteCtrl = TextEditingController(text: _s(existing?['note']));
    DateTime? dataAss = DateTime.tryParse(
          _s(existing?['data_assegnazione']),
        ) ??
        (isNew ? DateTime.now() : null);

    final saved = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(isNew ? 'Nuova SIM' : 'Modifica SIM / assegnazione'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: numeroCtrl,
                        decoration: const InputDecoration(
                          labelText: 'N. linea *',
                          hintText: 'es. 3331234567',
                        ),
                        keyboardType: TextInputType.phone,
                        enabled: isNew || _canEdit,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assegnatarioCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Assegnatario',
                          hintText: 'Nome cognome o DISPONIBILE IN SEDE',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data assegnazione'),
                        subtitle: Text(
                          dataAss == null
                              ? 'Non impostata'
                              : formatDateDdMmYyyyFromDate(dataAss!),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_month_outlined),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: dataAss ?? DateTime.now(),
                              firstDate: DateTime(2015),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setLocal(() => dataAss = picked);
                            }
                          },
                        ),
                      ),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Note'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, 'import'),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Carica assegnazione'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Oppure carica un Excel con «N. linee» e «Assegnatario» '
                        'per aggiornare tutte le SIM in blocco.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
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
                  child: Text(isNew ? 'Crea' : 'Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    final numero = numeroCtrl.text.trim();
    final assegnatario = assegnatarioCtrl.text.trim();
    final note = noteCtrl.text.trim();
    numeroCtrl.dispose();
    assegnatarioCtrl.dispose();
    noteCtrl.dispose();

    if (saved == 'import') {
      await _importAssegnazioniExcel();
      return;
    }
    if (saved != true) return;
    if (numero.isEmpty) {
      ModifyFeedback.hint(context, 'Inserisci il numero di linea');
      return;
    }

    final payload = <String, dynamic>{
      'numero_linea': numero,
      'assegnatario': assegnatario.isEmpty ? null : assegnatario,
      'data_assegnazione': dataAss == null
          ? null
          : '${dataAss!.year.toString().padLeft(4, '0')}-'
              '${dataAss!.month.toString().padLeft(2, '0')}-'
              '${dataAss!.day.toString().padLeft(2, '0')}',
      'note': note.isEmpty ? null : note,
      'active': true,
    };

    try {
      if (isNew) {
        await _supa.from('logistica_sim').insert(payload);
      } else {
        final id = _s(existing['id_uuid']);
        final prevAss = _s(existing['assegnatario']);
        if (assegnatario != prevAss && dataAss == null) {
          final today = DateTime.now();
          payload['data_assegnazione'] =
              '${today.year.toString().padLeft(4, '0')}-'
              '${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}';
        }
        await _supa.from('logistica_sim').update(payload).eq('id_uuid', id);
      }
      if (!mounted) return;
      ModifyFeedback.success(
        context,
        isNew ? 'SIM creata.' : 'Assegnazione aggiornata.',
      );
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Salvataggio fallito: $e');
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    if (!_canEdit) {
      await showAdminVistaReadOnlyDialog(context);
      return;
    }
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disattiva SIM'),
        content: Text(
          'Disattivare la linea ${_s(row['numero_linea'])}?\n'
          'Resta in archivio (non viene cancellata definitivamente).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disattiva'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa
          .from('logistica_sim')
          .update({'active': false})
          .eq('id_uuid', _s(row['id_uuid']));
      if (!mounted) return;
      ModifyFeedback.success(context, 'SIM disattivata.');
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topBar = Theme.of(context).colorScheme.primary;
    final items = _filtered;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: topBar,
        foregroundColor: Colors.white,
        title: const ResponsiveAppBarTitle(
          title: 'SIM telefoniche',
          desktopLogoSize: 44,
          mobileLogoSize: 28,
          lightOnDark: true,
          showBrandAndClock: false,
        ),
        actions: [
          if (_canEdit)
            IconButton(
              tooltip: 'Carica assegnazioni (Excel)',
              onPressed:
                  _loading ? null : () => unawaited(_importAssegnazioniExcel()),
              icon: const Icon(Icons.upload_file_outlined),
            ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _loading ? null : _loadRows,
            icon: const Icon(Icons.refresh),
          ),
          if (_canEdit)
            PopupMenuButton<String>(
              tooltip: 'Altro',
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    unawaited(_openEditor());
                    break;
                  case 'import':
                    unawaited(_importAssegnazioniExcel());
                    break;
                  case 'clear':
                    unawaited(_clearAllAssegnazioni());
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'import',
                  child: Text('Carica assegnazioni Excel…'),
                ),
                PopupMenuItem(
                  value: 'new',
                  child: Text('Nuova SIM'),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text('Svuota tutte le assegnazioni'),
                ),
              ],
            ),
        ],
      ),
      body: PageWithTopLogo(
        logoSize: 96,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_canEdit) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => unawaited(_importAssegnazioniExcel()),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Carica assegnazioni'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Carica un Excel con colonne «N. linee» e «Assegnatario» '
                  '(come il file abbinamenti). I numeri già presenti vengono aggiornati.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Cerca numero o assegnatario…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 250),
                        () {
                          if (!mounted) return;
                          setState(() => _search = v);
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _canEdit
                    ? '${items.length} linee · modifica manuale o carica Excel'
                    : '${items.length} linee · sola lettura',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const Center(child: Text('Nessuna SIM trovata'))
                        : _useMobile
                            ? _buildMobileList(items)
                            : _buildDesktopTable(items),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList(List<Map<String, dynamic>> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = items[i];
        final disp = _isDisponibile(r);
        final id = _s(r['id_uuid']);
        final pdfCount = _pdfCounts[id] ?? 0;
        return Card(
          child: ListTile(
            title: Text(
              _s(r['numero_linea']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${_s(r['assegnatario']).isEmpty ? '—' : _s(r['assegnatario'])}'
              '${_s(r['data_assegnazione']).isEmpty ? '' : ' · ${formatDateDdMmYyyy(r['data_assegnazione'])}'}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    unawaited(_openEditor(existing: r));
                    break;
                  case 'pdf':
                    unawaited(_openPdfDialog(r));
                    break;
                  case 'del':
                    unawaited(_deleteRow(r));
                    break;
                }
              },
              itemBuilder: (_) => [
                if (_canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Modifica / assegna'),
                  ),
                PopupMenuItem(
                  value: 'pdf',
                  child: Text(
                    pdfCount > 0
                        ? 'PDF assegnazione ($pdfCount)'
                        : 'PDF assegnazione',
                  ),
                ),
                if (_canEdit)
                  const PopupMenuItem(
                    value: 'del',
                    child: Text('Disattiva'),
                  ),
              ],
            ),
            leading: Icon(
              Icons.sim_card_outlined,
              color: disp ? Colors.green.shade700 : Colors.blueGrey,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> items) {
    return DataTable2(
      columnSpacing: 12,
      horizontalMargin: 12,
      minWidth: 880,
      columns: const [
        DataColumn2(label: Text('N. linea'), size: ColumnSize.M),
        DataColumn2(label: Text('Assegnatario'), size: ColumnSize.L),
        DataColumn2(label: Text('Data assegnazione'), size: ColumnSize.S),
        DataColumn2(label: Text('Note'), size: ColumnSize.L),
        DataColumn2(label: Text('Azioni'), size: ColumnSize.S),
      ],
      rows: [
        for (final r in items)
          DataRow(
            cells: [
              DataCell(Text(
                _s(r['numero_linea']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )),
              DataCell(
                Row(
                  children: [
                    if (_isDisponibile(r))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.green.shade700,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _s(r['assegnatario']).isEmpty
                            ? '—'
                            : _s(r['assegnatario']),
                      ),
                    ),
                  ],
                ),
              ),
              DataCell(Text(
                formatDateDdMmYyyy(r['data_assegnazione']).isEmpty
                    ? '—'
                    : formatDateDdMmYyyy(r['data_assegnazione']),
              )),
              DataCell(Text(
                _s(r['note']).isEmpty ? '—' : _s(r['note']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final id = _s(r['id_uuid']);
                        final pdfCount = _pdfCounts[id] ?? 0;
                        return IconButton(
                          tooltip: pdfCount > 0
                              ? 'PDF assegnazione ($pdfCount)'
                              : 'Carica / apri PDF assegnazione',
                          icon: Badge(
                            isLabelVisible: pdfCount > 0,
                            label: Text('$pdfCount'),
                            child: Icon(
                              pdfCount > 0
                                  ? Icons.picture_as_pdf
                                  : Icons.picture_as_pdf_outlined,
                              size: 20,
                            ),
                          ),
                          onPressed: () => unawaited(_openPdfDialog(r)),
                        );
                      },
                    ),
                    if (_canEdit) ...[
                      IconButton(
                        tooltip: 'Modifica',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () =>
                            unawaited(_openEditor(existing: r)),
                      ),
                      IconButton(
                        tooltip: 'Disattiva',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => unawaited(_deleteRow(r)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _SimPdfDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool canWrite;
  final VoidCallback onChanged;

  const _SimPdfDialog({
    required this.row,
    required this.canWrite,
    required this.onChanged,
  });

  @override
  State<_SimPdfDialog> createState() => _SimPdfDialogState();
}

class _SimPdfDialogState extends State<_SimPdfDialog> {
  bool _loading = true;
  bool _uploading = false;
  List<SimAssegnazioneDocumento> _docs = const [];

  String get _simId => (widget.row['id_uuid'] ?? '').toString().trim();

  String get _label {
    final num = (widget.row['numero_linea'] ?? '').toString().trim();
    final ass = (widget.row['assegnatario'] ?? '').toString().trim();
    if (num.isEmpty) return ass.isEmpty ? 'SIM' : ass;
    if (ass.isEmpty) return num;
    return '$num · $ass';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await LogisticaSimDocumentiService.listForSim(_simId);
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
    if (!_canEditGuard()) return false;
    if (!widget.canWrite) {
      ModifyFeedback.hint(context, 'Non hai permesso di caricare PDF.');
      return false;
    }
    return true;
  }

  bool _canEditGuard() {
    final role = currentSessionRole() ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
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
    if (!LogisticaSimDocumentiService.isAllowedFileName(file.name)) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Carica un file PDF.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaSimDocumentiService.upload(
        simId: _simId,
        originalFileName: file.name,
        bytes: bytes,
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

  Future<void> _open(SimAssegnazioneDocumento doc) async {
    try {
      final url = await LogisticaSimDocumentiService.signedUrl(doc);
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

  Future<void> _download(SimAssegnazioneDocumento doc) async {
    try {
      final bytes = await LogisticaSimDocumentiService.downloadBytes(doc);
      var base = doc.fileName.trim();
      if (base.toLowerCase().endsWith('.pdf')) {
        base = base.substring(0, base.length - 4);
      }
      if (base.isEmpty) base = 'assegnazione_sim';
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
      final url = await LogisticaSimDocumentiService.signedUrl(doc);
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

  Future<void> _delete(SimAssegnazioneDocumento doc) async {
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
      await LogisticaSimDocumentiService.delete(doc);
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
              _label,
              style: Theme.of(context).textTheme.titleMedium,
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
