import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mezzi_km_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../services/logistica_asset_storico_service.dart';
import '../utils/logistica_telepass_mezzo_sync.dart';
import '../utils/logistica_layout.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

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

class AdminLogisticaTelepassPage extends StatefulWidget {
  final bool forceMobileLayout;
  final bool dipendenteMode;

  const AdminLogisticaTelepassPage({
    super.key,
    this.forceMobileLayout = false,
    this.dipendenteMode = false,
  });

  @override
  State<AdminLogisticaTelepassPage> createState() =>
      _AdminLogisticaTelepassPageState();
}

class _AdminLogisticaTelepassPageState extends State<AdminLogisticaTelepassPage> {
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
          .from('logistica_telepass')
          .select()
          .order('mezzo_targa', ascending: true);
      final resMezzi = await _supa.from('logistica_mezzi_stradali').select(
          'id_uuid,targa,assegnatario_attuale,assegnatario_user_uuid,telepass,periodo_assegnatario_attuale,data_fine_assegnatario_attuale');

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
            r['telepass'],
            r['mezzo_targa'],
            labelTelepassAssegnazione(r['mezzo_targa']?.toString()),
            r['note'],
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

      if (!mounted) return;
      setState(() {
        _rows = list;
        _utentiByUuid
          ..clear()
          ..addAll(userMap);
        if (showLoader) _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _rows = <Map<String, dynamic>>[];
          if (showLoader) _loading = false;
        });
        ModifyFeedback.error(context, 'Errore caricamento: $e');
      }
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
      builder: (ctx) => _TelepassDialog(
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
        title: const Text('Elimina Telepass'),
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
      await _supa.from('logistica_telepass').delete().eq('id_uuid', row['id_uuid']);
      if (isTelepassVehicleAssignment(targa)) {
        await refreshMezzoTelepassField(supa: _supa, targa: targa);
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
      final sheet = excel['Telepass'];
      sheet.appendRow([
        'Telepass',
        'Assegnazione',
        'ASSEGNATARIO',
        'Data inizio',
        'Data fine',
        'Note',
      ]);
      for (final r in _rows) {
        sheet.appendRow([
          _nonEmpty(r['telepass']),
          labelTelepassAssegnazione(r['mezzo_targa']?.toString()),
          _effAssegnatario(r),
          _fmtDate(r['periodo_assegnatario_attuale']),
          _fmtDate(r['data_fine_assegnatario_attuale']),
          _nonEmpty(r['note']),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Gestione_Telepass',
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _nonEmpty(r['telepass']).isEmpty ? 'Telepass' : _nonEmpty(r['telepass']),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailLine(
                'Assegnazione',
                labelTelepassAssegnazione(r['mezzo_targa']?.toString()),
              ),
              _detailLine(
                'Data inizio assegnatario',
                _fmtDate(r['periodo_assegnatario_attuale']),
              ),
              _detailLine(
                'Data fine assegnatario',
                _fmtDate(r['data_fine_assegnatario_attuale']),
              ),
              _detailLine('Note', _nonEmpty(r['note'])),
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

  static const int _notePreviewChars = 42;

  bool _noteIsLong(String note) {
    final t = note.trim();
    if (t.isEmpty) return false;
    return t.length > _notePreviewChars || t.contains('\n');
  }

  Future<void> _showFullNote(String note) async {
    final t = note.trim();
    if (t.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: SelectableText(t)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Widget _noteCell(Map<String, dynamic> r) {
    final t = _nonEmpty(r['note']);
    if (t.isEmpty) {
      return Text('—', style: TextStyle(color: Theme.of(context).hintColor));
    }
    final long = _noteIsLong(t);
    return Row(
      children: [
        Expanded(
          child: Text(
            t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (long)
          IconButton(
            tooltip: 'Apri nota completa',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: const Icon(Icons.expand_more),
            onPressed: () => _showFullNote(t),
          ),
      ],
    );
  }

  Widget _buildMobileList() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _isDipendenteView ? 'Nessun telepass assegnato a te.' : 'Nessuna riga',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _rows[i];
        return Card(
          child: ListTile(
            title: Text(
              '${i + 1}. ${_nonEmpty(r['telepass']).isEmpty ? 'Telepass' : _nonEmpty(r['telepass'])}',
            ),
            subtitle: Text(
              [
                'Assegnazione: ${labelTelepassAssegnazione(r['mezzo_targa']?.toString())}',
                if (!_isDipendenteView)
                  'Assegnatario: ${_effAssegnatario(r).isEmpty ? '—' : _effAssegnatario(r)}',
                if (_nonEmpty(r['note']).isNotEmpty)
                  'Note: ${_noteIsLong(_nonEmpty(r['note'])) ? '${_nonEmpty(r['note']).split(RegExp(r'\r?\n')).first}…' : _nonEmpty(r['note'])}',
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_noteIsLong(_nonEmpty(r['note'])))
                  IconButton(
                    tooltip: 'Apri nota completa',
                    icon: const Icon(Icons.expand_more),
                    onPressed: () => _showFullNote(_nonEmpty(r['note'])),
                  ),
                if (_isDipendenteView)
                  const Icon(Icons.chevron_right)
                else
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _openForm(row: r);
                      if (v == 'del') await _deleteRow(r);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifica')),
                      PopupMenuItem(value: 'del', child: Text('Elimina')),
                    ],
                  ),
              ],
            ),
            onTap: _isDipendenteView
                ? () => _showReadOnlyDetail(r)
                : () => _openForm(row: r),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _isDipendenteView ? 'Nessun telepass assegnato a te.' : 'Nessuna riga',
        ),
      );
    }
    if (_isDipendenteView) {
      return DataTable2(
        minWidth: 720,
        columnSpacing: 6,
        horizontalMargin: 8,
        headingRowHeight: 36,
        dataRowHeight: 40,
        columns: [
          DataColumn2(
            label: Text('N° (${_rows.length})'),
            size: ColumnSize.S,
            fixedWidth: 48,
          ),
          const DataColumn2(label: Text('Telepass'), size: ColumnSize.M),
          const DataColumn2(
            label: Text('Assegnazione'),
            size: ColumnSize.S,
            fixedWidth: 96,
          ),
          const DataColumn2(label: Text('Note'), size: ColumnSize.L),
        ],
        rows: _rows.asMap().entries.map((entry) {
          final r = entry.value;
          return DataRow(
            onSelectChanged: (_) => _showReadOnlyDetail(r),
            cells: [
              DataCell(Text('${entry.key + 1}')),
              DataCell(Text(_nonEmpty(r['telepass']))),
              DataCell(Text(labelTelepassAssegnazione(r['mezzo_targa']?.toString()))),
              DataCell(_noteCell(r)),
            ],
          );
        }).toList(),
      );
    }
    return DataTable2(
      minWidth: 920,
      columnSpacing: 6,
      horizontalMargin: 8,
      headingRowHeight: 36,
      dataRowHeight: 40,
      smRatio: 0.55,
      lmRatio: 1.05,
      columns: [
        DataColumn2(
          label: Text('N° (${_rows.length})'),
          size: ColumnSize.S,
          fixedWidth: 48,
        ),
        const DataColumn2(label: Text('Telepass'), size: ColumnSize.M),
        const DataColumn2(
          label: Text('Assegnazione'),
          size: ColumnSize.S,
          fixedWidth: 96,
        ),
        const DataColumn2(label: Text('Assegnatario'), size: ColumnSize.M),
        const DataColumn2(
          label: Text('Data inizio'),
          size: ColumnSize.S,
          fixedWidth: 92,
        ),
        const DataColumn2(
          label: Text('Data fine'),
          size: ColumnSize.S,
          fixedWidth: 92,
        ),
        const DataColumn2(label: Text('Note'), size: ColumnSize.L),
        const DataColumn2(
          label: Text('Azioni'),
          size: ColumnSize.S,
          fixedWidth: 84,
        ),
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
          _hoverCell(Text(_nonEmpty(r['telepass'])), r, 'telepass'),
          _hoverCell(
            Text(labelTelepassAssegnazione(r['mezzo_targa']?.toString())),
            r,
            'mezzo_targa',
          ),
          _hoverCell(
            Text(_effAssegnatario(r).isEmpty ? '—' : _effAssegnatario(r)),
            r,
            'assegnatario_attuale',
          ),
          _hoverCell(
            Text(_fmtDate(r['periodo_assegnatario_attuale'])),
            r,
            'periodo_assegnatario_attuale',
          ),
          _hoverCell(
            Text(_fmtDate(r['data_fine_assegnatario_attuale'])),
            r,
            'data_fine_assegnatario_attuale',
          ),
          _hoverCell(_noteCell(r), r, 'note'),
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Modifica',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openForm(row: r),
                ),
                IconButton(
                  tooltip: 'Elimina',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
          title: _isDipendenteView ? 'Il mio Telepass' : 'Gestione Telepass',
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
                            ? 'Cerca telepass o targa...'
                            : 'Cerca telepass, targa, assegnatario...',
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

class _TelepassDialog extends StatefulWidget {
  final SupabaseClient supa;
  final Map<String, dynamic>? row;
  final List<Map<String, dynamic>> mezziRows;
  const _TelepassDialog({
    required this.supa,
    this.row,
    required this.mezziRows,
  });

  @override
  State<_TelepassDialog> createState() => _TelepassDialogState();
}

class _TelepassDialogState extends State<_TelepassDialog> {
  late final TextEditingController telepassCtrl;
  late final TextEditingController noteCtrl;
  late final TextEditingController assegnatarioSearchCtrl;
  late final TextEditingController dataInizioAssegnatarioCtrl;
  late final TextEditingController dataFineAssegnatarioCtrl;
  final List<_AssegnatarioOption> _assegnatariOptions = <_AssegnatarioOption>[];
  String? assegnatarioUserUuid;
  String _assegnazioneKey = kTelepassAssegnazioneNessuna;
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
    telepassCtrl = TextEditingController(text: _nonEmpty(r['telepass']));
    _assegnazioneKey = telepassAssegnazioneKeyFromTarga(r['mezzo_targa']?.toString());
    noteCtrl = TextEditingController(text: _nonEmpty(r['note']));
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
    telepassCtrl.dispose();
    noteCtrl.dispose();
    assegnatarioSearchCtrl.dispose();
    dataInizioAssegnatarioCtrl.dispose();
    dataFineAssegnatarioCtrl.dispose();
    super.dispose();
  }

  void _syncAssegnatarioFromMezzo() {
    if (!isTelepassVehicleAssignment(
      mezzoTargaFromTelepassAssegnazioneKey(_assegnazioneKey),
    )) {
      return;
    }
    final t = mezzoTargaFromTelepassAssegnazioneKey(_assegnazioneKey)
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
    final tp = telepassCtrl.text.trim();
    if (tp.isEmpty || isTelepassValueEmpty(tp)) {
      ModifyFeedback.error(context, 'Il codice Telepass è obbligatorio.');
      return;
    }
    final targaDb = mezzoTargaFromTelepassAssegnazioneKey(_assegnazioneKey);
    final targaVehicle =
        isTelepassVehicleAssignment(targaDb) ? targaDb.trim() : '';
    final prevTarga = _nonEmpty(widget.row?['mezzo_targa']);
    if (targaVehicle.isNotEmpty) {
      _syncAssegnatarioFromMezzo();
    }
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
    final prevSnap = LogisticaAssigneeSnapshot.fromTelepassRow(widget.row);
    final nextName = assigneeName;
    final nextSnap = LogisticaAssigneeSnapshot(
      name: nextName.isEmpty ? null : nextName,
      userUuid: assegnatarioUserUuid,
    );
    if (LogisticaAssetStoricoService.assigneeChanged(prevSnap, nextSnap) &&
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
      'telepass': tp,
      'mezzo_targa': targaDb,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
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
      await LogisticaAssetStoricoService.handleTelepassAssigneeOnSave(
        supa: widget.supa,
        previousRow: widget.row,
        telepass: tp,
        mezzoTarga: targaVehicle,
        mezzoIdUuid: mezzoId,
        next: nextSnap,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );

      if (widget.row == null) {
        await widget.supa.from('logistica_telepass').insert(payload);
      } else {
        await widget.supa
            .from('logistica_telepass')
            .update(payload)
            .eq('id_uuid', widget.row!['id_uuid']);
      }
      await LogisticaAssetStoricoService.ensureForTelepass(
        supa: widget.supa,
        telepass: tp,
        mezzoTarga: targaVehicle,
        mezzoIdUuid: mezzoId,
      );
      if (isTelepassVehicleAssignment(prevTarga) &&
          prevTarga.toLowerCase() != targaVehicle.toLowerCase()) {
        await refreshMezzoTelepassField(supa: widget.supa, targa: prevTarga);
      }
      if (targaVehicle.isNotEmpty) {
        await refreshMezzoTelepassField(supa: widget.supa, targa: targaVehicle);
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
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    if (isTelepassVehicleAssignment(
      mezzoTargaFromTelepassAssegnazioneKey(_assegnazioneKey),
    )) {
      final cur = mezzoTargaFromTelepassAssegnazioneKey(_assegnazioneKey);
      if (!targaItems.contains(cur)) targaItems.insert(0, cur);
    }
    final assegnazioneItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: kTelepassAssegnazioneNessuna,
        child: Text('Nessuna assegnazione'),
      ),
      ...targaItems.map(
        (t) => DropdownMenuItem(value: t, child: Text(t)),
      ),
    ];
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo Telepass' : 'Modifica Telepass'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: telepassCtrl,
                decoration: const InputDecoration(
                  labelText: 'Telepass',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(_assegnazioneKey),
                initialValue: assegnazioneItems.any((e) => e.value == _assegnazioneKey)
                    ? _assegnazioneKey
                    : kTelepassAssegnazioneNessuna,
                items: assegnazioneItems,
                decoration: const InputDecoration(
                  labelText: 'Assegnazione',
                  helperText: 'Targa mezzo stradale oppure nessuna',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  setState(() {
                    _assegnazioneKey =
                        (v ?? kTelepassAssegnazioneNessuna).trim();
                    if (_assegnazioneKey.isEmpty) {
                      _assegnazioneKey = kTelepassAssegnazioneNessuna;
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
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
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
