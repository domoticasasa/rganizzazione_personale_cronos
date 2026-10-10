import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_assegnazione_mezzi_documenti_service.dart';
import '../services/logistica_asset_storico_service.dart';
import '../services/mezzi_km_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/logistica_assignee_giustificativi_confirm_dialog.dart';
import 'employee_assegnazione_mezzi_page.dart';

enum _AssegnazioneFilter { tutti, assegnati, nonAssegnati, conPdf }

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

class AdminLogisticaAssegnazioneMezziStradaliPage extends StatelessWidget {
  final bool forceMobileLayout;
  final bool dipendenteMode;

  const AdminLogisticaAssegnazioneMezziStradaliPage({
    super.key,
    this.forceMobileLayout = false,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (dipendenteMode) {
      return EmployeeAssegnazioneMezziPage(
        forceMobileLayout: forceMobileLayout,
      );
    }
    return _AdminLogisticaAssegnazioneMezziStradaliPage(
      forceMobileLayout: forceMobileLayout,
    );
  }
}

class _AdminLogisticaAssegnazioneMezziStradaliPage extends StatefulWidget {
  final bool forceMobileLayout;

  const _AdminLogisticaAssegnazioneMezziStradaliPage({
    this.forceMobileLayout = false,
  });

  @override
  State<_AdminLogisticaAssegnazioneMezziStradaliPage> createState() =>
      _AdminLogisticaAssegnazioneMezziStradaliPageState();
}

class _AdminLogisticaAssegnazioneMezziStradaliPageState
    extends State<_AdminLogisticaAssegnazioneMezziStradaliPage> {
  final _supa = Supabase.instance.client;
  final ScrollController _desktopHorizontalCtrl = ScrollController();
  final ScrollController _desktopVerticalCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _uploading = false;
  String _search = '';
  _AssegnazioneFilter _filter = _AssegnazioneFilter.tutti;
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  Map<String, int> _pdfCounts = <String, int>{};

  bool get _canWrite {
    final role = ClassicNavSessionCache.current?.role ?? '';
    return canEditAssegnazioneMezziStradali(role);
  }

  bool _guardWrite() {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
      return false;
    }
    if (!_canWrite) {
      ModifyFeedback.hint(
        context,
        'Solo admin possono modificare o caricare PDF.',
      );
      return false;
    }
    return true;
  }

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
    _desktopHorizontalCtrl.dispose();
    _desktopVerticalCtrl.dispose();
    super.dispose();
  }

  bool _narrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  bool _hasAssignee(Map<String, dynamic> row) {
    final name = (row['assegnatario_attuale'] ?? '').toString().trim();
    final uuid = (row['assegnatario_user_uuid'] ?? '').toString().trim();
    return name.isNotEmpty || uuid.isNotEmpty;
  }

  String _mezzoLabel(Map<String, dynamic> row) => mezzoLabelFromParts(
        targa: (row['targa'] ?? '').toString(),
        marca: (row['marca'] ?? '').toString(),
        modello: (row['modello'] ?? '').toString(),
      );

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _search = _searchCtrl.text);
    });
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final res = await _supa
          .from('logistica_mezzi_stradali')
          .select(
            'id_uuid,numerazione,targa,marca,modello,tipologia_mezzo,'
            'assegnatario_attuale,assegnatario_user_uuid,'
            'periodo_assegnatario_attuale,data_fine_assegnatario_attuale,'
            'multicard,telepass,note',
          )
          .order('numerazione', ascending: true);
      Map<String, int> counts = const {};
      try {
        counts =
            await LogisticaAssegnazioneMezziDocumentiService.countByMezzo();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _pdfCounts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento: $e');
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final k = _search.trim().toLowerCase();
    return _rows.where((r) {
      final id = (r['id_uuid'] ?? '').toString();
      if (_filter == _AssegnazioneFilter.assegnati && !_hasAssignee(r)) {
        return false;
      }
      if (_filter == _AssegnazioneFilter.nonAssegnati && _hasAssignee(r)) {
        return false;
      }
      if (_filter == _AssegnazioneFilter.conPdf &&
          (_pdfCounts[id] ?? 0) <= 0) {
        return false;
      }
      if (k.isEmpty) return true;
      final fields = [
        r['numerazione'],
        r['targa'],
        r['marca'],
        r['modello'],
        r['tipologia_mezzo'],
        r['assegnatario_attuale'],
        r['multicard'],
        r['telepass'],
        r['note'],
      ].map((v) => (v ?? '').toString().toLowerCase());
      return fields.any((f) => f.contains(k));
    }).toList(growable: false);
  }

  Future<void> _exportExcel() async {
    final rows = _visibleRows;
    if (rows.isEmpty) {
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Assegnazioni_mezzi'];
      sheet.appendRow([
        'Numerazione',
        'Targa',
        'Marca',
        'Modello',
        'Tipologia',
        'Assegnatario',
        'Data inizio',
        'Data fine',
        'Multicard',
        'Telepass',
        'Note',
      ]);
      for (final r in rows) {
        sheet.appendRow([
          (r['numerazione'] ?? '').toString(),
          (r['targa'] ?? '').toString(),
          (r['marca'] ?? '').toString(),
          (r['modello'] ?? '').toString(),
          (r['tipologia_mezzo'] ?? '').toString(),
          (r['assegnatario_attuale'] ?? '').toString(),
          _fmtDate(r['periodo_assegnatario_attuale']),
          _fmtDate(r['data_fine_assegnatario_attuale']),
          (r['multicard'] ?? '').toString(),
          (r['telepass'] ?? '').toString(),
          (r['note'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: 'Assegnazione_mezzi_stradali',
        bytes: bytes,
        extension: 'xlsx',
        openFile: true,
      );
      if (!mounted) return;
      ModifyFeedback.hint(
        context,
        ok ? 'Esportazione completata.' : 'Esportazione annullata.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore export: $e');
    }
  }

  Future<void> _openAssigneeDialog(Map<String, dynamic> row) async {
    if (!_guardWrite()) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AssigneeEditDialog(row: row),
    );
    if (saved == true) await _loadRows(showLoader: false);
  }

  Future<void> _openPdfDialog(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AssegnazionePdfDialog(
        row: row,
        canWrite: _canWrite,
        onChanged: () => _loadRows(showLoader: false),
      ),
    );
  }

  Future<void> _uploadPdfWithMezzoPicker() async {
    if (!_guardWrite()) return;

    List<MezzoStradaleRef> mezzi;
    try {
      mezzi = await LogisticaAssegnazioneMezziDocumentiService.listMezzi();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore elenco mezzi: $e');
      }
      return;
    }
    if (!mounted) return;
    if (mezzi.isEmpty) {
      ModifyFeedback.hint(
        context,
        'Nessun mezzo stradale in anagrafica.',
      );
      return;
    }

    final meta = await showDialog<_MezzoUploadMeta>(
      context: context,
      builder: (ctx) => _UploadMezzoPdfDialog(mezzi: mezzi),
    );
    if (meta == null || !mounted) return;

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;
    if (!LogisticaAssegnazioneMezziDocumentiService.isAllowedFileName(
      file.name,
    )) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Carica un file PDF.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaAssegnazioneMezziDocumentiService.upload(
        mezzoId: meta.mezzo.id,
        originalFileName: file.name,
        bytes: bytes,
        note: meta.note,
      );
      await _loadRows(showLoader: false);
      if (mounted) ModifyFeedback.hint(context, 'PDF caricato.');
      if (!mounted) return;
      Map<String, dynamic>? row;
      for (final r in _rows) {
        if ((r['id_uuid'] ?? '').toString() == meta.mezzo.id) {
          row = r;
          break;
        }
      }
      if (row != null) {
        await _openPdfDialog(row);
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Upload fallito: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _rowActions(Map<String, dynamic> row) {
    final id = (row['id_uuid'] ?? '').toString();
    final pdfCount = _pdfCounts[id] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: pdfCount > 0
              ? 'PDF assegnazione ($pdfCount)'
              : 'PDF assegnazione',
          icon: Badge(
            isLabelVisible: pdfCount > 0,
            label: Text('$pdfCount'),
            child: Icon(
              pdfCount > 0
                  ? Icons.picture_as_pdf
                  : Icons.picture_as_pdf_outlined,
            ),
          ),
          onPressed: () => _openPdfDialog(row),
        ),
        if (_canWrite)
          IconButton(
            tooltip: 'Modifica assegnazione',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openAssigneeDialog(row),
          ),
      ],
    );
  }

  Widget _assigneeCell(Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final name = (row['assegnatario_attuale'] ?? '').toString().trim();
    final inizio = _fmtDate(row['periodo_assegnatario_attuale']);
    final fine = _fmtDate(row['data_fine_assegnatario_attuale']);
    if (name.isEmpty && inizio.isEmpty && fine.isEmpty) {
      return Text(
        'Non assegnato',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty)
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        if (inizio.isNotEmpty)
          Text('Inizio: $inizio', style: theme.textTheme.bodySmall),
        if (fine.isNotEmpty)
          Text('Fine: $fine', style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tutti'),
          selected: _filter == _AssegnazioneFilter.tutti,
          onSelected: (_) =>
              setState(() => _filter = _AssegnazioneFilter.tutti),
        ),
        ChoiceChip(
          label: const Text('Assegnati'),
          selected: _filter == _AssegnazioneFilter.assegnati,
          onSelected: (_) =>
              setState(() => _filter = _AssegnazioneFilter.assegnati),
        ),
        ChoiceChip(
          label: const Text('Non assegnati'),
          selected: _filter == _AssegnazioneFilter.nonAssegnati,
          onSelected: (_) =>
              setState(() => _filter = _AssegnazioneFilter.nonAssegnati),
        ),
        ChoiceChip(
          label: Text(
            'Con PDF${_pdfCounts.isEmpty ? '' : ' (${_pdfCounts.values.fold<int>(0, (a, b) => a + (b > 0 ? 1 : 0))})'}',
          ),
          selected: _filter == _AssegnazioneFilter.conPdf,
          onSelected: (_) =>
              setState(() => _filter = _AssegnazioneFilter.conPdf),
        ),
      ],
    );
  }

  Widget _desktopTable(List<Map<String, dynamic>> rows) {
    return DataTable2(
      headingRowHeight: 44,
      dataRowHeight: 72,
      columnSpacing: 16,
      horizontalMargin: 12,
      minWidth: 1100,
      scrollController: _desktopVerticalCtrl,
      isVerticalScrollBarVisible: true,
      isHorizontalScrollBarVisible: true,
      columns: const [
        DataColumn2(label: Text('N°'), size: ColumnSize.S),
        DataColumn2(label: Text('Mezzo'), size: ColumnSize.M),
        DataColumn2(label: Text('Tipologia'), size: ColumnSize.S),
        DataColumn2(label: Text('Assegnatario attuale'), size: ColumnSize.L),
        DataColumn2(label: Text('Multicard'), size: ColumnSize.S),
        DataColumn2(label: Text('Telepass'), size: ColumnSize.S),
        DataColumn2(label: Text('PDF'), size: ColumnSize.S),
        DataColumn2(label: Text('Azioni'), size: ColumnSize.M),
      ],
      rows: rows.map((r) {
        final id = (r['id_uuid'] ?? '').toString();
        final pdfCount = _pdfCounts[id] ?? 0;
        return DataRow2(
          cells: [
            DataCell(Text((r['numerazione'] ?? '—').toString())),
            DataCell(Text(_mezzoLabel(r))),
            DataCell(Text((r['tipologia_mezzo'] ?? '—').toString())),
            DataCell(_assigneeCell(r)),
            DataCell(Text((r['multicard'] ?? '—').toString())),
            DataCell(Text((r['telepass'] ?? '—').toString())),
            DataCell(
              pdfCount > 0
                  ? TextButton.icon(
                      onPressed: () => _openPdfDialog(r),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: Text('$pdfCount'),
                    )
                  : TextButton(
                      onPressed: () => _openPdfDialog(r),
                      child: const Text('—'),
                    ),
            ),
            DataCell(_rowActions(r)),
          ],
        );
      }).toList(growable: false),
    );
  }

  Widget _mobileList(List<Map<String, dynamic>> rows) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 0, 12, _canWrite ? 88 : 16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = rows[index];
        return Card(
          child: ListTile(
            isThreeLine: true,
            title: Text(_mezzoLabel(r)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((r['tipologia_mezzo'] ?? '').toString().trim().isNotEmpty)
                  Text((r['tipologia_mezzo'] ?? '').toString()),
                const SizedBox(height: 4),
                _assigneeCell(r),
              ],
            ),
            trailing: _rowActions(r),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final assignedCount = _rows.where(_hasAssignee).length;
    final unassignedCount = _rows.length - assignedCount;

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(
            title: 'Assegnazione mezzi stradali',
          ),
          actions: [
            if (_canWrite)
              IconButton(
                tooltip: 'Carica PDF',
                onPressed: _uploading ? null : _uploadPdfWithMezzoPicker,
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
              onPressed: _uploading ? null : _uploadPdfWithMezzoPicker,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_uploading ? 'Caricamento…' : 'Carica PDF'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: logisticaFilterBar(
              context: context,
              children: [
                SizedBox(
                  width: logisticaFieldWidth(context),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Cerca targa, mezzo, assegnatario…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Aggiorna',
                  onPressed: _loading ? null : () => _loadRows(),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Esporta Excel',
                  onPressed: _loading || rows.isEmpty ? null : _exportExcel,
                  icon: const Icon(Icons.download_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _filterChips(),
                const SizedBox(height: 8),
                Text(
                  '${rows.length} mezzi · $assignedCount assegnati · '
                  '$unassignedCount non assegnati'
                  '${_canWrite ? '' : ' · sola lettura'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(
                        child: Text(
                          _rows.isEmpty
                              ? 'Nessun mezzo stradale in anagrafica.'
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

class _AssigneeEditDialog extends StatefulWidget {
  final Map<String, dynamic> row;

  const _AssigneeEditDialog({required this.row});

  @override
  State<_AssigneeEditDialog> createState() => _AssigneeEditDialogState();
}

class _AssigneeEditDialogState extends State<_AssigneeEditDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController _assegnatarioCtrl;
  late final TextEditingController _inizioCtrl;
  late final TextEditingController _fineCtrl;
  final List<_AssegnatarioOption> _options = <_AssegnatarioOption>[];
  String? _assegnatarioUserUuid;
  bool _loadingOptions = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _assegnatarioUserUuid =
        (r['assegnatario_user_uuid'] ?? '').toString().trim().isEmpty
            ? null
            : (r['assegnatario_user_uuid'] ?? '').toString().trim();
    _assegnatarioCtrl = TextEditingController(
      text: (r['assegnatario_attuale'] ?? '').toString(),
    );
    _inizioCtrl = TextEditingController(
      text: formatDateDdMmYyyy(r['periodo_assegnatario_attuale']),
    );
    _fineCtrl = TextEditingController(
      text: formatDateDdMmYyyy(r['data_fine_assegnatario_attuale']),
    );
    unawaited(_loadOptions());
  }

  @override
  void dispose() {
    _assegnatarioCtrl.dispose();
    _inizioCtrl.dispose();
    _fineCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final personaleRows = await _supa
          .from('personale')
          .select('id_uuid,full_name,matricola,user_id,active')
          .order('full_name', ascending: true);
      final personaleList = List<Map<String, dynamic>>.from(
        (personaleRows as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
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
        final users = await _supa
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
        final uid = p['user_id'];
        int? userId;
        if (uid is int) userId = uid;
        userId ??= int.tryParse((uid ?? '').toString().trim());
        options.add(
          _AssegnatarioOption(
            label: labelParts.join(' - '),
            assignedName: fullName,
            userUuid: userId != null ? userById[userId] : null,
          ),
        );
      }
      options.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _options
          ..clear()
          ..addAll(options);
        _loadingOptions = false;
        if ((_assegnatarioUserUuid ?? '').isNotEmpty) {
          final matched =
              _options.where((o) => o.userUuid == _assegnatarioUserUuid);
          if (matched.isNotEmpty) {
            _assegnatarioCtrl.text = matched.first.assignedName;
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    setState(() => _saving = true);
    try {
      String? toIso(String value) => parseFlexibleDateToIsoDate(value.trim());

      final assigneeName = _assegnatarioCtrl.text.trim();
      if (assigneeName.isNotEmpty && (_assegnatarioUserUuid ?? '').isEmpty) {
        final map = await MezziKmService.loadAssigneeNameToUserUuidMap();
        final resolved = MezziKmService.resolveAssigneeUserUuid(
          <String, dynamic>{'assegnatario_attuale': assigneeName},
          assigneeNameToUserUuid: map,
        );
        if (resolved != null && resolved.isNotEmpty) {
          _assegnatarioUserUuid = resolved;
        }
      }

      final prevSnap = LogisticaAssigneeSnapshot.fromMezzoRow(widget.row);
      final nextName = _assegnatarioCtrl.text.trim();
      final nextSnap = LogisticaAssigneeSnapshot(
        name: nextName.isEmpty ? null : nextName,
        userUuid: _assegnatarioUserUuid,
      );
      final assigneeChanged =
          LogisticaAssetStoricoService.assigneeChanged(prevSnap, nextSnap);

      if (assigneeChanged && prevSnap.hasAssignee) {
        if (!mounted) return;
        final targa = (widget.row['targa'] ?? '').toString().trim();
        final ok = await confirmPreviousAssigneeGiustificativi(
          context: context,
          previousAssigneeName: prevSnap.name ?? '',
          assetLabel: targa.isNotEmpty ? 'mezzo $targa' : 'questo mezzo',
        );
        if (!ok || !mounted) return;
      }

      if (assigneeChanged && nextSnap.hasAssignee) {
        _inizioCtrl.text = LogisticaAssetStoricoService.todayDisplayDate();
      }

      final inizioIso = LogisticaAssetStoricoService.resolveDataInizioOnSave(
        previous: prevSnap,
        next: nextSnap,
        manualInizioIso: toIso(_inizioCtrl.text),
      );

      final id = (widget.row['id_uuid'] ?? '').toString().trim();
      final targa = (widget.row['targa'] ?? '').toString().trim();
      final telepass = (widget.row['telepass'] ?? '').toString().trim();
      final note = (widget.row['note'] ?? '').toString().trim();

      await LogisticaAssetStoricoService.handleMezzoAssigneeOnSave(
        supa: _supa,
        previousRow: widget.row,
        targa: targa,
        mezzoIdUuid: id.isEmpty ? null : id,
        next: nextSnap,
        telepass: telepass,
        note: note.isEmpty ? null : note,
      );

      final payload = <String, dynamic>{
        'assegnatario_user_uuid': _assegnatarioUserUuid,
        'assegnatario_attuale': nextName.isEmpty ? null : nextName,
        'periodo_assegnatario_attuale': inizioIso,
        'data_fine_assegnatario_attuale': toIso(_fineCtrl.text),
      };

      await _supa.from('logistica_mezzi_stradali').update(payload).eq(
            'id_uuid',
            id,
          );

      await LogisticaAssetStoricoService.ensureForMezzo(
        supa: _supa,
        targa: targa,
        mezzoIdUuid: id,
        telepass: telepass,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mezzoLabel = mezzoLabelFromParts(
      targa: (widget.row['targa'] ?? '').toString(),
      marca: (widget.row['marca'] ?? '').toString(),
      modello: (widget.row['modello'] ?? '').toString(),
    );

    return AlertDialog(
      title: const Text('Modifica assegnazione'),
      content: SizedBox(
        width: logisticaDialogWidth(context),
        child: _loadingOptions
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      mezzoLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Autocomplete<_AssegnatarioOption>(
                      initialValue:
                          TextEditingValue(text: _assegnatarioCtrl.text),
                      optionsBuilder: (textEditingValue) {
                        final q = textEditingValue.text.trim().toLowerCase();
                        if (q.isEmpty) return _options;
                        return _options.where(
                          (e) =>
                              e.label.toLowerCase().contains(q) ||
                              e.assignedName.toLowerCase().contains(q),
                        );
                      },
                      displayStringForOption: (opt) => opt.label,
                      onSelected: (opt) {
                        setState(() {
                          _assegnatarioUserUuid = opt.userUuid;
                          _assegnatarioCtrl.text = opt.assignedName;
                          _inizioCtrl.text =
                              LogisticaAssetStoricoService.todayDisplayDate();
                          _fineCtrl.clear();
                        });
                      },
                      fieldViewBuilder:
                          (context, textCtrl, focusNode, onFieldSubmitted) {
                        if (textCtrl.text != _assegnatarioCtrl.text) {
                          textCtrl.text = _assegnatarioCtrl.text;
                        }
                        return TextField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Assegnatario (dipendente)',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: 'Azzera assegnatario',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _assegnatarioUserUuid = null;
                                  _assegnatarioCtrl.clear();
                                  textCtrl.clear();
                                });
                              },
                            ),
                          ),
                          onChanged: (v) {
                            _assegnatarioCtrl.text = v;
                            final exact = _options
                                .where(
                                  (e) =>
                                      e.label.toLowerCase() ==
                                          v.trim().toLowerCase() ||
                                      e.assignedName.toLowerCase() ==
                                          v.trim().toLowerCase(),
                                )
                                .toList(growable: false);
                            setState(() {
                              _assegnatarioUserUuid = exact.isNotEmpty
                                  ? exact.first.userUuid
                                  : null;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inizioCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data inizio (GG/MM/AAAA)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fineCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data fine (GG/MM/AAAA)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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
              : const Text('Salva'),
        ),
      ],
    );
  }
}

class _AssegnazionePdfDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool canWrite;
  final VoidCallback onChanged;

  const _AssegnazionePdfDialog({
    required this.row,
    required this.canWrite,
    required this.onChanged,
  });

  @override
  State<_AssegnazionePdfDialog> createState() => _AssegnazionePdfDialogState();
}

class _AssegnazionePdfDialogState extends State<_AssegnazionePdfDialog> {
  bool _loading = true;
  bool _uploading = false;
  List<AssegnazioneMezzoDocumento> _docs = const [];

  String get _mezzoId => (widget.row['id_uuid'] ?? '').toString().trim();

  String get _mezzoLabel => mezzoLabelFromParts(
        targa: (widget.row['targa'] ?? '').toString(),
        marca: (widget.row['marca'] ?? '').toString(),
        modello: (widget.row['modello'] ?? '').toString(),
      );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs =
          await LogisticaAssegnazioneMezziDocumentiService.listForMezzo(
        _mezzoId,
      );
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
    if (!LogisticaAssegnazioneMezziDocumentiService.isAllowedFileName(
      file.name,
    )) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Carica un file PDF.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await LogisticaAssegnazioneMezziDocumentiService.upload(
        mezzoId: _mezzoId,
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

  Future<void> _open(AssegnazioneMezzoDocumento doc) async {
    try {
      final url =
          await LogisticaAssegnazioneMezziDocumentiService.signedUrl(doc);
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
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

  Future<void> _download(AssegnazioneMezzoDocumento doc) async {
    try {
      final bytes =
          await LogisticaAssegnazioneMezziDocumentiService.downloadBytes(doc);
      var base = doc.fileName.trim();
      if (base.toLowerCase().endsWith('.pdf')) {
        base = base.substring(0, base.length - 4);
      }
      if (base.isEmpty) base = 'assegnazione';
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
      // Fallback web: apri URL firmata se FileSaver annulla/fallisce.
      final url =
          await LogisticaAssegnazioneMezziDocumentiService.signedUrl(doc);
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

  Future<void> _delete(AssegnazioneMezzoDocumento doc) async {
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
      await LogisticaAssegnazioneMezziDocumentiService.delete(doc);
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
              _mezzoLabel,
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

class _MezzoUploadMeta {
  const _MezzoUploadMeta({required this.mezzo, required this.note});
  final MezzoStradaleRef mezzo;
  final String note;
}

class _UploadMezzoPdfDialog extends StatefulWidget {
  const _UploadMezzoPdfDialog({required this.mezzi});

  final List<MezzoStradaleRef> mezzi;

  @override
  State<_UploadMezzoPdfDialog> createState() => _UploadMezzoPdfDialogState();
}

class _UploadMezzoPdfDialogState extends State<_UploadMezzoPdfDialog> {
  final _noteCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  MezzoStradaleRef? _selected;
  String _filter = '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  List<MezzoStradaleRef> get _filtered {
    final k = _filter.trim().toLowerCase();
    if (k.isEmpty) return widget.mezzi;
    return widget.mezzi.where((m) {
      final blob = [
        m.targa,
        m.marca,
        m.modello,
        m.tipologia,
        m.assegnatario,
        m.label,
        if (m.numerazione != null) '${m.numerazione}',
      ].map((s) => s.toLowerCase());
      return blob.any((s) => s.contains(k));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
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
                labelText: 'Cerca mezzo stradale',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 10),
            Text(
              _selected == null
                  ? 'Seleziona un mezzo dalla lista'
                  : 'Selezionato: ${_selected!.label}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight:
                        _selected == null ? FontWeight.w500 : FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nessun mezzo trovato.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final m = items[index];
                        final selected = _selected?.id == m.id;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.local_shipping_outlined,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            m.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(m.subtitle),
                          onTap: () => setState(() => _selected = m),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (opzionale)',
                border: OutlineInputBorder(),
              ),
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
                    _MezzoUploadMeta(
                      mezzo: _selected!,
                      note: _noteCtrl.text,
                    ),
                  ),
          child: const Text('Scegli PDF'),
        ),
      ],
    );
  }
}
