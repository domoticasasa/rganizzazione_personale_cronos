import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_asset_storico_service.dart';
import '../services/logistica_multicard_mdo_assegnazioni_service.dart';
import '../services/mezzi_km_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/logistica_layout.dart';
import '../utils/logistica_multicard_mezzo_sync.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/logistica_assignee_giustificativi_confirm_dialog.dart';

class _AssegnatarioOption {
  final String label;
  final String assignedName;
  final String? userUuid;
  const _AssegnatarioOption({
    required this.label,
    required this.assignedName,
    this.userUuid,
  });
}

class AdminLogisticaMulticardPage extends StatefulWidget {
  final bool forceMobileLayout;
  final bool dipendenteMode;

  const AdminLogisticaMulticardPage({
    super.key,
    this.forceMobileLayout = false,
    this.dipendenteMode = false,
  });

  @override
  State<AdminLogisticaMulticardPage> createState() =>
      _AdminLogisticaMulticardPageState();
}

class _AdminLogisticaMulticardPageState extends State<AdminLogisticaMulticardPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _mezzi = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _mezzoByTargaLower =
      <String, Map<String, dynamic>>{};
  final Map<String, String> _utentiByUuid = <String, String>{};
  String _myUserUuid = '';
  String _myNameNorm = '';
  /// Conteggio PDF assegnazione MDO per multicard_id (vista dipendente).
  Map<String, int> _mdoPdfCounts = const {};

  bool get _isDipendenteView => widget.dipendenteMode;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isDipendenteView) await _loadMyIdentity();
    await _loadRows();
  }

  Future<void> _loadMyIdentity() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return;
    try {
      final me = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .eq('auth_id', authId!)
          .maybeSingle();
      _myUserUuid = _nonEmpty(me?['id_uuid']);
      final full = _nonEmpty(me?['full_name']);
      final user = _nonEmpty(me?['username']);
      final source = full.isNotEmpty ? full : user;
      _myNameNorm = MezziKmService.normalizePersonName(source);
    } catch (_) {
      _myUserUuid = '';
      _myNameNorm = '';
    }
  }

  bool _isAssignedToMe(Map<String, dynamic> r) {
    return MezziKmService.isRowAssignedToCurrentUser(
      <String, dynamic>{
        'assegnatario_user_uuid': _effAssegnatarioUuid(r),
        'assegnatario_attuale': _effAssegnatario(r),
      },
      _myUserUuid,
      _myNameNorm,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  bool _useNarrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  String _nonEmpty(dynamic v) => (v ?? '').toString().trim();

  String _effAssegnatario(Map<String, dynamic> r) {
    final local = _nonEmpty(r['assegnatario_attuale']);
    if (local.isNotEmpty) return local;
    final targa = _nonEmpty(r['mezzo_targa']).toLowerCase();
    final m = _mezzoByTargaLower[targa];
    return _nonEmpty(m?['assegnatario_attuale']);
  }

  String? _effAssegnatarioUuid(Map<String, dynamic> r) {
    final local = _nonEmpty(r['assegnatario_user_uuid']);
    if (local.isNotEmpty) return local;
    final targa = _nonEmpty(r['mezzo_targa']).toLowerCase();
    final m = _mezzoByTargaLower[targa];
    final fromMezzo = _nonEmpty(m?['assegnatario_user_uuid']);
    return fromMezzo.isEmpty ? null : fromMezzo;
  }

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final resRows = await _supa
          .from('logistica_multicard')
          .select()
          .order('mezzo_targa', ascending: true);
      final resMezzi = await _supa.from('logistica_mezzi_stradali').select(
          'id_uuid,targa,assegnatario_attuale,assegnatario_user_uuid,multicard,periodo_assegnatario_attuale,data_fine_assegnatario_attuale');

      var list = List<Map<String, dynamic>>.from(
        (resRows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      _mezzi = List<Map<String, dynamic>>.from(
        (resMezzi as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      _mezzoByTargaLower
        ..clear()
        ..addEntries(_mezzi.map((m) => MapEntry(
              _nonEmpty(m['targa']).toLowerCase(),
              m,
            )));

      if (_isDipendenteView) {
        list = list.where(_isAssignedToMe).toList(growable: false);
      }

      if (_search.trim().isNotEmpty) {
        final k = _search.toLowerCase().trim();
        list = list.where((r) {
          final fields = [
            r['multicard'],
            r['mezzo_targa'],
            labelMulticardAssegnazione(r['mezzo_targa']?.toString()),
            r['limite_spesa_giornaliero'],
            r['scadenza_carta'],
            _effAssegnatario(r),
          ].map((v) => (v ?? '').toString().toLowerCase());
          return fields.any((f) => f.contains(k));
        }).toList(growable: false);
      }

      final ids = <String>{};
      for (final r in list) {
        final c = _nonEmpty(r['created_by_user_uuid']);
        final u = _nonEmpty(r['updated_by_user_uuid']);
        if (c.isNotEmpty) ids.add(c);
        if (u.isNotEmpty) ids.add(u);
        final ass = _effAssegnatarioUuid(r);
        if ((ass ?? '').isNotEmpty) ids.add(ass!);
        mergeFieldTimestampActorUuids(r, ids);
      }
      final userMap = <String, String>{};
      if (ids.isNotEmpty) {
        final users = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', ids.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = _nonEmpty(m['id_uuid']);
          final full = _nonEmpty(m['full_name']);
          final user = _nonEmpty(m['username']);
          if (id.isNotEmpty) userMap[id] = full.isNotEmpty ? full : user;
        }
      }

      Map<String, int> pdfCounts = const {};
      if (_isDipendenteView) {
        try {
          final allCounts =
              await LogisticaMulticardMdoAssegnazioniService.countByMulticard();
          final mine = <String, int>{};
          for (final r in list) {
            if (!isMulticardMdoAssignment(r['mezzo_targa']?.toString())) {
              continue;
            }
            final id = _nonEmpty(r['id_uuid']);
            if (id.isEmpty) continue;
            final n = allCounts[id] ?? 0;
            if (n > 0) mine[id] = n;
          }
          pdfCounts = mine;
        } catch (_) {
          pdfCounts = const {};
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = list;
        _mdoPdfCounts = pdfCounts;
        _utentiByUuid
          ..clear()
          ..addAll(userMap);
        if (showLoader) _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _rows = <Map<String, dynamic>>[];
          _mdoPdfCounts = const {};
          if (showLoader) _loading = false;
        });
        ModifyFeedback.error(context, 'Errore caricamento: $e');
      }
    }
  }

  int _mdoPdfCount(Map<String, dynamic> r) {
    final id = _nonEmpty(r['id_uuid']);
    if (id.isEmpty) return 0;
    return _mdoPdfCounts[id] ?? 0;
  }

  Future<void> _downloadMdoAssegnazionePdf(
    MulticardMdoAssegnazioneFile file,
  ) async {
    try {
      final bytes =
          await LogisticaMulticardMdoAssegnazioniService.downloadBytes(file);
      final original = file.fileName.trim();
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
      if (saved) {
        ModifyFeedback.success(context, 'PDF assegnazione scaricato.');
      } else {
        ModifyFeedback.hint(context, 'Download annullato.');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Download PDF: $e');
    }
  }

  Future<void> _openMdoAssegnazionePdfs(Map<String, dynamic> r) async {
    final id = _nonEmpty(r['id_uuid']);
    if (id.isEmpty) return;
    try {
      final files =
          await LogisticaMulticardMdoAssegnazioniService.listForMulticard(id);
      if (!mounted) return;
      if (files.isEmpty) {
        ModifyFeedback.hint(
          context,
          'Nessun PDF di assegnazione caricato per questa Multicard MDO.',
        );
        return;
      }
      if (files.length == 1) {
        await _downloadMdoAssegnazionePdf(files.first);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('PDF assegnazione MDO'),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = files[i];
                return ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf,
                    color: Color(0xFFC62828),
                  ),
                  title: Text(f.fileName),
                  subtitle: Text(formatDateDdMmYyyyFromDate(f.uploadedAt)),
                  trailing: IconButton(
                    tooltip: 'Scarica',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadMdoAssegnazionePdf(f);
                    },
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _downloadMdoAssegnazionePdf(f);
                  },
                );
              },
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
      if (!mounted) return;
      ModifyFeedback.error(context, 'PDF assegnazione: $e');
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadRows(showLoader: false);
    });
  }


  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MulticardDialog(
        supa: _supa,
        row: row,
        mezziRows: _mezzi,
      ),
    );
    if (ok == true) await _loadRows();
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    if (!await ensureCanPersist(context)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Multicard'),
        content: const Text('Confermi eliminazione?'),
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
    if (go != true) return;
    try {
      final targa = _nonEmpty(row['mezzo_targa']);
      await _supa.from('logistica_multicard').delete().eq('id_uuid', row['id_uuid']);
      if (isMulticardVehicleAssignment(targa)) {
        await refreshMezzoMulticardField(supa: _supa, targa: targa);
      }
      await _loadRows();
      if (mounted) ModifyFeedback.success(context, 'Riga eliminata.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  Future<void> _exportExcel() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ModifyFeedback.hint(context, 'Nessun dato da esportare');
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Multicard'];
      sheet.appendRow([
        'Multicard',
        'Scadenza della Carta',
        'Limite spesa carta giornaliero',
        'Assegnazione',
        'ASSEGNATARIO',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          _nonEmpty(r['multicard']),
          _fmtDate(r['scadenza_carta']),
          _nonEmpty(r['limite_spesa_giornaliero']),
          labelMulticardAssegnazione(r['mezzo_targa']?.toString()),
          _effAssegnatario(r),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Gestione_Multicard',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ModifyFeedback.success(
        context,
        p.isEmpty ? 'Export Excel completato.' : 'Export Excel completato.\n$p',
      );
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    }
  }

  DataCell _hoverCell(Widget child, Map<String, dynamic> r, String fieldKey) {
    return decorateDataCellWithAuditHover(
      DataCell(child),
      row: r,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  Future<void> _showReadOnlyDetail(Map<String, dynamic> r) async {
    final isMdo = isMulticardMdoAssignment(r['mezzo_targa']?.toString());
    final pdfCount = _mdoPdfCount(r);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_nonEmpty(r['multicard']).isEmpty ? 'Multicard' : _nonEmpty(r['multicard'])),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailLine(
                'Assegnazione',
                labelMulticardAssegnazione(r['mezzo_targa']?.toString()),
              ),
              _detailLine('Scadenza carta', _fmtDate(r['scadenza_carta'])),
              _detailLine('Limite giornaliero', _nonEmpty(r['limite_spesa_giornaliero'])),
              if (isMdo) ...[
                const SizedBox(height: 8),
                _detailLine(
                  'PDF assegnazione',
                  pdfCount > 0
                      ? (pdfCount == 1
                          ? '1 file disponibile'
                          : '$pdfCount file disponibili')
                      : 'Non ancora caricato',
                ),
                if (pdfCount > 0) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_openMdoAssegnazionePdfs(r));
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Scarica assegnazione MDO'),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600),
          children: [TextSpan(text: value.isEmpty ? '—' : value)],
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _isDipendenteView ? 'Nessuna multicard assegnata a te.' : 'Nessuna riga',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final isMdo =
            isMulticardMdoAssignment(r['mezzo_targa']?.toString());
        final pdfCount = _mdoPdfCount(r);
        return Card(
          child: ListTile(
            title: Text(
              '${i + 1}. ${_nonEmpty(r['multicard']).isEmpty ? 'Multicard' : _nonEmpty(r['multicard'])}',
            ),
            subtitle: Text(
              [
                'Assegnazione: ${labelMulticardAssegnazione(r['mezzo_targa']?.toString())}',
                'Scadenza: ${_fmtDate(r['scadenza_carta'])}',
                if (!_isDipendenteView)
                  'Assegnatario: ${_effAssegnatario(r).isEmpty ? '—' : _effAssegnatario(r)}',
                if (_isDipendenteView && isMdo && pdfCount > 0)
                  'PDF assegnazione: $pdfCount',
              ].join('\n'),
            ),
            isThreeLine: !_isDipendenteView || (isMdo && pdfCount > 0),
            trailing: _isDipendenteView
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMdo && pdfCount > 0)
                        IconButton(
                          tooltip: 'Scarica assegnazione MDO',
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            color: Color(0xFFC62828),
                          ),
                          onPressed: () => unawaited(_openMdoAssegnazionePdfs(r)),
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  )
                : PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _openForm(row: r);
                      if (v == 'del') await _deleteRow(r);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifica')),
                      PopupMenuItem(value: 'del', child: Text('Elimina')),
                    ],
                  ),
            onTap: _isDipendenteView ? () => _showReadOnlyDetail(r) : () => _openForm(row: r),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _isDipendenteView ? 'Nessuna multicard assegnata a te.' : 'Nessuna riga',
        ),
      );
    }
    if (_isDipendenteView) {
      return DataTable2(
        minWidth: 980,
        columnSpacing: 12,
        horizontalMargin: 10,
        columns: [
          DataColumn2(
            label: Text('N° (${_rows.length})'),
            size: ColumnSize.S,
            fixedWidth: 56,
          ),
          const DataColumn2(label: Text('Multicard'), size: ColumnSize.L),
          DataColumn2(label: Text('Scadenza carta'), size: ColumnSize.S),
          DataColumn2(label: Text('Limite giornaliero'), size: ColumnSize.S),
          DataColumn2(label: Text('Assegnazione'), size: ColumnSize.S),
          DataColumn2(label: Text('PDF assegnazione'), size: ColumnSize.S),
        ],
        rows: _rows.asMap().entries.map((entry) {
          final r = entry.value;
          final isMdo =
              isMulticardMdoAssignment(r['mezzo_targa']?.toString());
          final pdfCount = _mdoPdfCount(r);
          return DataRow(
            onSelectChanged: (_) => _showReadOnlyDetail(r),
            cells: [
              DataCell(Text('${entry.key + 1}')),
              DataCell(Text(_nonEmpty(r['multicard']))),
              DataCell(Text(_fmtDate(r['scadenza_carta']))),
              DataCell(Text(_nonEmpty(r['limite_spesa_giornaliero']))),
              DataCell(Text(labelMulticardAssegnazione(r['mezzo_targa']?.toString()))),
              DataCell(
                isMdo && pdfCount > 0
                    ? TextButton.icon(
                        onPressed: () =>
                            unawaited(_openMdoAssegnazionePdfs(r)),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(pdfCount == 1 ? 'Scarica' : 'Scarica ($pdfCount)'),
                      )
                    : Text(isMdo ? '—' : ''),
              ),
            ],
          );
        }).toList(),
      );
    }
    return DataTable2(
      minWidth: 1100,
      columnSpacing: 12,
      horizontalMargin: 10,
      columns: [
        DataColumn2(
          label: Text('N° (${_rows.length})'),
          size: ColumnSize.S,
          fixedWidth: 56,
        ),
        const DataColumn2(label: Text('Multicard'), size: ColumnSize.L),
        const DataColumn2(label: Text('Scadenza carta'), size: ColumnSize.S),
        const DataColumn2(label: Text('Limite giornaliero'), size: ColumnSize.S),
        const DataColumn2(label: Text('Assegnazione'), size: ColumnSize.S),
        const DataColumn2(label: Text('Assegnatario'), size: ColumnSize.L),
        const DataColumn2(label: Text('Azioni'), size: ColumnSize.S),
      ],
      rows: _rows.asMap().entries.map((entry) {
        final r = entry.value;
        return DataRow(cells: [
          DataCell(
            Text(
              '${entry.key + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          _hoverCell(Text(_nonEmpty(r['multicard'])), r, 'multicard'),
          _hoverCell(Text(_fmtDate(r['scadenza_carta'])), r, 'scadenza_carta'),
          _hoverCell(
              Text(_nonEmpty(r['limite_spesa_giornaliero'])), r, 'limite_spesa_giornaliero'),
          _hoverCell(
            Text(labelMulticardAssegnazione(r['mezzo_targa']?.toString())),
            r,
            'mezzo_targa',
          ),
          _hoverCell(
            Text(_effAssegnatario(r).isEmpty ? '—' : _effAssegnatario(r)),
            r,
            'assegnatario_attuale',
          ),
          DataCell(
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Modifica',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openForm(row: r),
                ),
                IconButton(
                  tooltip: 'Elimina',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteRow(r),
                ),
              ],
            ),
          ),
        ]);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(
          title: _isDipendenteView ? 'La mia Multicard' : 'Gestione Multicard',
        ),
        actions: [
          if (!_isDipendenteView)
            IconButton(
              tooltip: 'Export Excel',
              onPressed: _loading ? null : _exportExcel,
              icon: const Icon(Icons.table_chart_outlined),
            ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading ? null : () => _loadRows(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      floatingActionButton: _isDipendenteView
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nuova riga'),
            ),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _isDipendenteView
                            ? 'Cerca multicard, targa, MDO...'
                            : 'Cerca multicard, targa, MDO, assegnatario...',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (!_loading)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Totale: ${_rows.length} '
                          '${_rows.length == 1 ? 'riga' : 'righe'}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _useNarrowLayout(context)
                        ? _buildMobileList()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: _buildDesktopTable(),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MulticardDialog extends StatefulWidget {
  final SupabaseClient supa;
  final Map<String, dynamic>? row;
  final List<Map<String, dynamic>> mezziRows;
  const _MulticardDialog({
    required this.supa,
    this.row,
    required this.mezziRows,
  });

  @override
  State<_MulticardDialog> createState() => _MulticardDialogState();
}

class _MulticardDialogState extends State<_MulticardDialog> {
  late final TextEditingController multicardCtrl;
  late final TextEditingController scadenzaCtrl;
  late final TextEditingController limiteCtrl;
  late final TextEditingController assegnatarioSearchCtrl;
  late final TextEditingController dataInizioAssegnatarioCtrl;
  late final TextEditingController dataFineAssegnatarioCtrl;
  final List<_AssegnatarioOption> _assegnatariOptions = <_AssegnatarioOption>[];
  String? assegnatarioUserUuid;
  String _assegnazioneKey = kMulticardAssegnazioneNessuna;
  bool _saving = false;

  String _nonEmpty(dynamic v) => (v ?? '').toString().trim();

  String? _mezzoIdUuidForTarga(String targa) {
    final key = targa.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final m in widget.mezziRows) {
      if (_nonEmpty(m['targa']).toLowerCase() == key) {
        final id = _nonEmpty(m['id_uuid']);
        return id.isEmpty ? null : id;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row ?? const <String, dynamic>{};
    multicardCtrl = TextEditingController(text: _nonEmpty(r['multicard']));
    scadenzaCtrl = TextEditingController(text: formatDateDdMmYyyy(r['scadenza_carta']));
    limiteCtrl = TextEditingController(text: _nonEmpty(r['limite_spesa_giornaliero']));
    _assegnazioneKey = multicardAssegnazioneKeyFromTarga(r['mezzo_targa']?.toString());
    assegnatarioSearchCtrl =
        TextEditingController(text: _nonEmpty(r['assegnatario_attuale']));
    dataInizioAssegnatarioCtrl = TextEditingController(
      text: formatDateDdMmYyyy(r['periodo_assegnatario_attuale']),
    );
    dataFineAssegnatarioCtrl = TextEditingController(
      text: formatDateDdMmYyyy(r['data_fine_assegnatario_attuale']),
    );
    assegnatarioUserUuid = _nonEmpty(r['assegnatario_user_uuid']).isEmpty
        ? null
        : _nonEmpty(r['assegnatario_user_uuid']);
    _loadDipendentiOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAssegnatarioFromMezzo();
    });
  }

  Future<void> _loadDipendentiOptions() async {
    try {
      final personaleRows = await widget.supa
          .from('personale')
          .select('id_uuid,full_name,matricola,user_id,active')
          .order('full_name', ascending: true);
      final personaleList = List<Map<String, dynamic>>.from(
        (personaleRows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final userIds = <int>{};
      for (final p in personaleList) {
        final uid = p['user_id'];
        if (uid is int) userIds.add(uid);
        final uidParsed = int.tryParse((uid ?? '').toString().trim());
        if (uidParsed != null) userIds.add(uidParsed);
      }

      final userById = <int, String>{};
      if (userIds.isNotEmpty) {
        final users = await widget.supa
            .from('users')
            .select('id,id_uuid')
            .inFilter('id', userIds.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = m['id'] is int
              ? m['id'] as int
              : int.tryParse((m['id'] ?? '').toString());
          final uuid = (m['id_uuid'] ?? '').toString().trim();
          if (id != null && uuid.isNotEmpty) userById[id] = uuid;
        }
      }

      final options = <_AssegnatarioOption>[];
      for (final p in personaleList) {
        final fullName = (p['full_name'] ?? '').toString().trim();
        if (fullName.isEmpty) continue;
        final matricola = (p['matricola'] ?? '').toString().trim();
        final active = p['active'] == true;
        final labelParts = <String>[fullName];
        if (matricola.isNotEmpty) labelParts.add('Matr. $matricola');
        if (!active) labelParts.add('Inattivo');
        final label = labelParts.join(' - ');
        final uid = p['user_id'];
        int? userId;
        if (uid is int) userId = uid;
        userId ??= int.tryParse((uid ?? '').toString().trim());
        options.add(_AssegnatarioOption(
          label: label,
          assignedName: fullName,
          userUuid: userId != null ? userById[userId] : null,
        ));
      }
      options.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _assegnatariOptions
          ..clear()
          ..addAll(options);
        if ((assegnatarioUserUuid ?? '').isNotEmpty) {
          final matched = _assegnatariOptions
              .where((o) => o.userUuid == assegnatarioUserUuid);
          if (matched.isNotEmpty) {
            assegnatarioSearchCtrl.text = matched.first.assignedName;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    multicardCtrl.dispose();
    scadenzaCtrl.dispose();
    limiteCtrl.dispose();
    assegnatarioSearchCtrl.dispose();
    dataInizioAssegnatarioCtrl.dispose();
    dataFineAssegnatarioCtrl.dispose();
    super.dispose();
  }

  void _syncAssegnatarioFromMezzo() {
    if (!isMulticardVehicleAssignment(
      mezzoTargaFromAssegnazioneKey(_assegnazioneKey),
    )) {
      return;
    }
    final t = mezzoTargaFromAssegnazioneKey(_assegnazioneKey)
        .trim()
        .toLowerCase();
    final mezzo = widget.mezziRows.firstWhere(
      (m) => _nonEmpty(m['targa']).toLowerCase() == t,
      orElse: () => const <String, dynamic>{},
    );
    if (mezzo.isEmpty) return;
    final ass = _nonEmpty(mezzo['assegnatario_attuale']);
    final assUuid = _nonEmpty(mezzo['assegnatario_user_uuid']);
    if (assegnatarioSearchCtrl.text.trim().isEmpty && ass.isNotEmpty) {
      assegnatarioSearchCtrl.text = ass;
    }
    if ((assegnatarioUserUuid ?? '').trim().isEmpty && assUuid.isNotEmpty) {
      assegnatarioUserUuid = assUuid;
    }
    final inizioMezzo = formatDateDdMmYyyy(mezzo['periodo_assegnatario_attuale']);
    final fineMezzo = formatDateDdMmYyyy(mezzo['data_fine_assegnatario_attuale']);
    if (dataInizioAssegnatarioCtrl.text.trim().isEmpty) {
      dataInizioAssegnatarioCtrl.text = inizioMezzo.isNotEmpty
          ? inizioMezzo
          : LogisticaAssetStoricoService.todayDisplayDate();
    }
    if (dataFineAssegnatarioCtrl.text.trim().isEmpty && fineMezzo.isNotEmpty) {
      dataFineAssegnatarioCtrl.text = fineMezzo;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!await ensureCanPersist(context)) return;
    final mc = multicardCtrl.text.trim();
    if (mc.isEmpty) {
      ModifyFeedback.error(context, 'Il numero Multicard è obbligatorio.');
      return;
    }
    final targaDb = mezzoTargaFromAssegnazioneKey(_assegnazioneKey);
    final targaVehicle =
        isMulticardVehicleAssignment(targaDb) ? targaDb.trim() : '';
    final prevTarga = _nonEmpty(widget.row?['mezzo_targa']);
    if (targaVehicle.isNotEmpty) {
      _syncAssegnatarioFromMezzo();
    }
    final limiteNum = num.tryParse(limiteCtrl.text.trim().replaceAll(',', '.'));
    final assigneeName = assegnatarioSearchCtrl.text.trim();
    if (assigneeName.isNotEmpty && (assegnatarioUserUuid ?? '').isEmpty) {
      final map = await MezziKmService.loadAssigneeNameToUserUuidMap();
      final resolved = MezziKmService.resolveAssigneeUserUuid(
        <String, dynamic>{'assegnatario_attuale': assigneeName},
        assigneeNameToUserUuid: map,
      );
      if (resolved != null && resolved.isNotEmpty) {
        assegnatarioUserUuid = resolved;
      }
    }
    final prevSnap =
        LogisticaAssigneeSnapshot.fromMulticardRow(widget.row);
    final nextName = assigneeName;
    final nextSnap = LogisticaAssigneeSnapshot(
      name: nextName.isEmpty ? null : nextName,
      userUuid: assegnatarioUserUuid,
    );
    final assigneeChanged =
        LogisticaAssetStoricoService.assigneeChanged(prevSnap, nextSnap);
    if (assigneeChanged && prevSnap.hasAssignee) {
      if (!mounted) return;
      final mcLabel = mc.isNotEmpty ? 'multicard $mc' : 'questa multicard';
      final ok = await confirmPreviousAssigneeGiustificativi(
        context: context,
        previousAssigneeName: prevSnap.name ?? '',
        assetLabel: mcLabel,
      );
      if (!ok || !mounted) return;
    }
    if (assigneeChanged &&
        nextSnap.hasAssignee) {
      dataInizioAssegnatarioCtrl.text =
          LogisticaAssetStoricoService.todayDisplayDate();
    }
    final inizioIso = LogisticaAssetStoricoService.resolveDataInizioOnSave(
      previous: prevSnap,
      next: nextSnap,
      manualInizioIso:
          parseFlexibleDateToIsoDate(dataInizioAssegnatarioCtrl.text),
    );

    final payload = <String, dynamic>{
      'multicard': mc,
      'scadenza_carta': parseFlexibleDateToIsoDate(scadenzaCtrl.text),
      'limite_spesa_giornaliero': limiteNum,
      'mezzo_targa': targaDb,
      'assegnatario_attuale': nextName.isEmpty ? null : nextName,
      'assegnatario_user_uuid':
          (assegnatarioUserUuid ?? '').trim().isEmpty ? null : assegnatarioUserUuid,
      'periodo_assegnatario_attuale': inizioIso,
      'data_fine_assegnatario_attuale':
          parseFlexibleDateToIsoDate(dataFineAssegnatarioCtrl.text),
    };

    setState(() => _saving = true);
    try {
      final mezzoId = targaVehicle.isEmpty ? null : _mezzoIdUuidForTarga(targaVehicle);
      await LogisticaAssetStoricoService.handleMulticardAssigneeOnSave(
        supa: widget.supa,
        previousRow: widget.row,
        multicard: mc,
        mezzoTarga: targaVehicle,
        mezzoIdUuid: mezzoId,
        multicardIdUuid: widget.row == null
            ? null
            : _nonEmpty(widget.row!['id_uuid']),
        next: nextSnap,
      );

      String? multicardId;
      if (widget.row == null) {
        final inserted = await widget.supa
            .from('logistica_multicard')
            .insert(payload)
            .select('id_uuid')
            .single();
        multicardId = _nonEmpty(inserted['id_uuid']);
      } else {
        multicardId = _nonEmpty(widget.row!['id_uuid']);
        await widget.supa
            .from('logistica_multicard')
            .update(payload)
            .eq('id_uuid', multicardId);
      }
      await LogisticaAssetStoricoService.ensureForMulticard(
        supa: widget.supa,
        multicard: mc,
        mezzoTarga: targaVehicle,
        mezzoIdUuid: mezzoId,
        multicardIdUuid: multicardId,
      );
      if (isMulticardVehicleAssignment(prevTarga) &&
          prevTarga.toLowerCase() != targaVehicle.toLowerCase()) {
        await refreshMezzoMulticardField(supa: widget.supa, targa: prevTarga);
      }
      if (targaVehicle.isNotEmpty) {
        await refreshMezzoMulticardField(supa: widget.supa, targa: targaVehicle);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targaItems = widget.mezziRows
        .map((m) => _nonEmpty(m['targa']))
        .where((t) => t.isNotEmpty && !isMulticardMdoAssignment(t))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    if (isMulticardVehicleAssignment(mezzoTargaFromAssegnazioneKey(_assegnazioneKey))) {
      final cur = mezzoTargaFromAssegnazioneKey(_assegnazioneKey);
      if (!targaItems.contains(cur)) targaItems.insert(0, cur);
    }
    final assegnazioneItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: kMulticardAssegnazioneNessuna,
        child: Text('Nessuna assegnazione'),
      ),
      const DropdownMenuItem(
        value: kMulticardAssegnazioneMdo,
        child: Text('MDO'),
      ),
      ...targaItems.map(
        (t) => DropdownMenuItem(value: t, child: Text(t)),
      ),
    ];
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuova Multicard' : 'Modifica Multicard'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: multicardCtrl,
                decoration: const InputDecoration(
                  labelText: 'Multicard',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: scadenzaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza carta (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: limiteCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Limite spesa giornaliero',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(_assegnazioneKey),
                initialValue: assegnazioneItems.any((e) => e.value == _assegnazioneKey)
                    ? _assegnazioneKey
                    : kMulticardAssegnazioneNessuna,
                items: assegnazioneItems,
                decoration: const InputDecoration(
                  labelText: 'Assegnazione',
                  helperText: 'Targa mezzo stradale, MDO oppure nessuna',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  setState(() {
                    _assegnazioneKey = (v ?? kMulticardAssegnazioneNessuna).trim();
                    if (_assegnazioneKey.isEmpty) {
                      _assegnazioneKey = kMulticardAssegnazioneNessuna;
                    }
                  });
                  _syncAssegnatarioFromMezzo();
                },
              ),
              const SizedBox(height: 10),
              Autocomplete<_AssegnatarioOption>(
                initialValue:
                    TextEditingValue(text: assegnatarioSearchCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return _assegnatariOptions;
                  return _assegnatariOptions.where(
                    (e) =>
                        e.label.toLowerCase().contains(q) ||
                        e.assignedName.toLowerCase().contains(q),
                  );
                },
                displayStringForOption: (opt) => opt.label,
                onSelected: (opt) {
                  setState(() {
                    assegnatarioUserUuid = opt.userUuid;
                    assegnatarioSearchCtrl.text = opt.assignedName;
                    dataInizioAssegnatarioCtrl.text =
                        LogisticaAssetStoricoService.todayDisplayDate();
                    dataFineAssegnatarioCtrl.clear();
                  });
                },
                fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != assegnatarioSearchCtrl.text) {
                    textCtrl.text = assegnatarioSearchCtrl.text;
                  }
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Assegnatario (scrivi o seleziona)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: 'Azzera assegnatario',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            assegnatarioUserUuid = null;
                            assegnatarioSearchCtrl.clear();
                            textCtrl.clear();
                          });
                        },
                      ),
                    ),
                    onChanged: (v) {
                      assegnatarioSearchCtrl.text = v;
                      final exact = _assegnatariOptions
                          .where(
                            (e) =>
                                e.label.toLowerCase() ==
                                    v.trim().toLowerCase() ||
                                e.assignedName.toLowerCase() ==
                                    v.trim().toLowerCase(),
                          )
                          .toList(growable: false);
                      setState(() {
                        assegnatarioUserUuid =
                            exact.isNotEmpty ? exact.first.userUuid : null;
                        if (dataInizioAssegnatarioCtrl.text.trim().isEmpty &&
                            v.trim().isNotEmpty) {
                          dataInizioAssegnatarioCtrl.text =
                              LogisticaAssetStoricoService.todayDisplayDate();
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: dataInizioAssegnatarioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data inizio assegnatario (GG/MM/AAAA)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: dataFineAssegnatarioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data fine assegnatario attuale (GG/MM/AAAA)',
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
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvataggio...' : 'Salva'),
        ),
      ],
    );
  }
}