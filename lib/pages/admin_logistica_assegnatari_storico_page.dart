import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_asset_storico_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_web_safe.dart';
import '../utils/modify_feedback.dart';
import '../utils/logistica_layout.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Tipi asset gestiti nello storico assegnatari.
enum LogisticaAssetTipo {
  mezzoStradale('mezzo_stradale', 'Mezzi stradali'),
  multicard('multicard', 'Multicard'),
  telepass('telepass', 'Telepass');

  const LogisticaAssetTipo(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

class _AssetListItem {
  final LogisticaAssetTipo tipo;
  final String identificativo;
  final String? mezzoTarga;
  final String? mezzoIdUuid;
  final String? multicardIdUuid;
  final String? assegnatarioAttuale;
  final String? dataInizioAttuale;
  final String? dataFineAttuale;
  final Map<int, Map<String, dynamic>> passaggi;

  const _AssetListItem({
    required this.tipo,
    required this.identificativo,
    this.mezzoTarga,
    this.mezzoIdUuid,
    this.multicardIdUuid,
    this.assegnatarioAttuale,
    this.dataInizioAttuale,
    this.dataFineAttuale,
    required this.passaggi,
  });

  bool get _showTargaMezzo =>
      (mezzoTarga ?? '').trim().isNotEmpty &&
      (mezzoTarga ?? '').trim().toLowerCase() !=
          identificativo.trim().toLowerCase();

  String get subtitle {
    final parts = <String>[];
    if (_showTargaMezzo) {
      parts.add('Targa mezzo: $mezzoTarga');
    }
    return parts.join(' · ');
  }

  String get attualeDisplay =>
      _formatAssegnatarioConDate(assegnatarioAttuale, dataInizioAttuale, dataFineAttuale);

  int get filledPassaggiCount =>
      passaggi.values.where((p) => _passaggioHasData(p)).length;
}

String _formatAssegnatarioConDate(
  String? assegnatario,
  String? inizio,
  String? fine,
) {
  final ass = (assegnatario ?? '').trim();
  final dal = (inizio ?? '').trim();
  final al = (fine ?? '').trim();
  if (ass.isEmpty && dal.isEmpty && al.isEmpty) return '—';
  final lines = <String>[];
  if (ass.isNotEmpty) lines.add(ass);
  lines.add('Inizio: ${dal.isEmpty ? "—" : dal}');
  lines.add('Fine: ${al.isEmpty ? "—" : al}');
  return lines.join('\n');
}

bool _passaggioHasData(Map<String, dynamic> p) {
  final ass = (p['assegnatario'] ?? '').toString().trim();
  final dal = (p['periodo_dal'] ?? '').toString().trim();
  final al = (p['periodo_al'] ?? '').toString().trim();
  final note = (p['note'] ?? '').toString().trim();
  return ass.isNotEmpty || dal.isNotEmpty || al.isNotEmpty || note.isNotEmpty;
}

/// Cella tabella: nome + date Inizio/Fine leggibili (contrasto e dimensione).
class _AssegnatarioConDateView extends StatelessWidget {
  final String? assegnatario;
  final String? inizio;
  final String? fine;

  const _AssegnatarioConDateView({
    this.assegnatario,
    this.inizio,
    this.fine,
  });

  factory _AssegnatarioConDateView.fromPassaggio(Map<String, dynamic>? p) {
    if (p == null || !_passaggioHasData(p)) {
      return const _AssegnatarioConDateView();
    }
    return _AssegnatarioConDateView(
      assegnatario: (p['assegnatario'] ?? '').toString(),
      inizio: formatDateDdMmYyyy(p['periodo_dal']),
      fine: formatDateDdMmYyyy(p['periodo_al']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ass = (assegnatario ?? '').trim();
    final dal = (inizio ?? '').trim();
    final al = (fine ?? '').trim();
    if (ass.isEmpty && dal.isEmpty && al.isEmpty) {
      return Text(
        '—',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ass.isNotEmpty)
          Text(
            ass,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              height: 1.25,
            ),
          ),
        _dateLine(context, 'Inizio', dal),
        _dateLine(context, 'Fine', al),
      ],
    );
  }

  Widget _dateLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final display = value.isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            height: 1.3,
            color: theme.colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            TextSpan(
              text: display,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLogisticaAssegnatariStoricoPage extends StatefulWidget {
  final bool forceMobileLayout;

  const AdminLogisticaAssegnatariStoricoPage({
    super.key,
    this.forceMobileLayout = false,
  });

  @override
  State<AdminLogisticaAssegnatariStoricoPage> createState() =>
      _AdminLogisticaAssegnatariStoricoPageState();
}

class _AdminLogisticaAssegnatariStoricoPageState
    extends State<AdminLogisticaAssegnatariStoricoPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  LogisticaAssetTipo _tipo = LogisticaAssetTipo.mezzoStradale;
  String _search = '';
  Timer? _searchDebounce;
  List<_AssetListItem> _items = [];
  List<Map<String, dynamic>> _storicoRaw = [];
  String _myRole = '';

  bool get _canEdit => canEditLogisticaStoricoAssegnatari(_myRole);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadIdentity();
    await _load();
  }

  Future<void> _loadIdentity() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return;
    try {
      final me = await _supa
          .from('users')
          .select('role')
          .eq('auth_id', authId!)
          .maybeSingle();
      if (mounted) {
        setState(() => _myRole = (me?['role'] ?? '').toString().trim());
      }
    } catch (_) {
      if (mounted) setState(() => _myRole = '');
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  bool _narrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final storicoRes = await _supa
          .from('logistica_asset_assegnatari_storico')
          .select()
          .eq('tipo_asset', _tipo.dbValue);
      _storicoRaw = List<Map<String, dynamic>>.from(
        (storicoRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final items = await _buildItemsForTipo(_tipo, _storicoRaw);
      if (!mounted) return;
      setState(() {
        _items = _filterItems(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento: $e');
    }
  }

  List<_AssetListItem> _filterItems(List<_AssetListItem> items) {
    final k = _search.trim().toLowerCase();
    if (k.isEmpty) return items;
    return items.where((it) {
      final blob = [
        it.identificativo,
        it.mezzoTarga,
        it.assegnatarioAttuale,
        ...it.passaggi.values.expand((p) => [
              p['assegnatario'],
              p['periodo_dal'],
              p['periodo_al'],
              p['note'],
            ]),
      ].map((v) => (v ?? '').toString().toLowerCase());
      return blob.any((s) => s.contains(k));
    }).toList(growable: false);
  }

  Map<int, Map<String, dynamic>> _passaggiFromStorico(
    LogisticaAssetTipo tipo,
    String identificativo,
    List<Map<String, dynamic>> storico,
  ) {
    final map = <int, Map<String, dynamic>>{};
    for (final row in storico) {
      if ((row['tipo_asset'] ?? '').toString() != tipo.dbValue) continue;
      if ((row['identificativo'] ?? '').toString().trim().toLowerCase() !=
          identificativo.trim().toLowerCase()) {
        continue;
      }
      final p = int.tryParse((row['passaggio'] ?? '').toString()) ?? 0;
      if (p >= 1 && p <= 4) map[p] = row;
    }
    return map;
  }

  Future<List<_AssetListItem>> _buildItemsForTipo(
    LogisticaAssetTipo tipo,
    List<Map<String, dynamic>> storico,
  ) async {
    switch (tipo) {
      case LogisticaAssetTipo.mezzoStradale:
        final res = await _supa
            .from('logistica_mezzi_stradali')
            .select(
                'id_uuid,targa,assegnatario_attuale,periodo_assegnatario_attuale,data_fine_assegnatario_attuale')
            .order('targa', ascending: true);
        final mezzi = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        return mezzi
            .map((m) {
              final targa = (m['targa'] ?? '').toString().trim();
              if (targa.isEmpty) return null;
              return _AssetListItem(
                tipo: tipo,
                identificativo: targa,
                mezzoTarga: targa,
                mezzoIdUuid: (m['id_uuid'] ?? '').toString(),
                assegnatarioAttuale: (m['assegnatario_attuale'] ?? '').toString(),
                dataInizioAttuale:
                    _fmtDate(m['periodo_assegnatario_attuale']),
                dataFineAttuale:
                    _fmtDate(m['data_fine_assegnatario_attuale']),
                passaggi: _passaggiFromStorico(tipo, targa, storico),
              );
            })
            .whereType<_AssetListItem>()
            .toList(growable: false);

      case LogisticaAssetTipo.multicard:
        final resMezzi = await _supa
            .from('logistica_mezzi_stradali')
            .select(
                'targa,periodo_assegnatario_attuale,data_fine_assegnatario_attuale,assegnatario_attuale');
        final mezziByTarga = <String, Map<String, dynamic>>{};
        for (final m in (resMezzi as List)) {
          final map = Map<String, dynamic>.from(m as Map);
          final t = (map['targa'] ?? '').toString().trim().toLowerCase();
          if (t.isNotEmpty) mezziByTarga[t] = map;
        }
        final res = await _supa
            .from('logistica_multicard')
            .select(
                'id_uuid,multicard,mezzo_targa,assegnatario_attuale,periodo_assegnatario_attuale,data_fine_assegnatario_attuale')
            .order('multicard', ascending: true);
        final cards = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        return cards
            .map((c) {
              final mc = (c['multicard'] ?? '').toString().trim();
              if (mc.isEmpty) return null;
              final targaKey =
                  (c['mezzo_targa'] ?? '').toString().trim().toLowerCase();
              final mezzo = mezziByTarga[targaKey];
              final inizio = _fmtDate(c['periodo_assegnatario_attuale']);
              final fine = _fmtDate(c['data_fine_assegnatario_attuale']);
              final assCard = (c['assegnatario_attuale'] ?? '').toString().trim();
              final assMezzo =
                  (mezzo?['assegnatario_attuale'] ?? '').toString().trim();
              return _AssetListItem(
                tipo: tipo,
                identificativo: mc,
                mezzoTarga: (c['mezzo_targa'] ?? '').toString().trim(),
                multicardIdUuid: (c['id_uuid'] ?? '').toString(),
                assegnatarioAttuale:
                    assCard.isNotEmpty ? assCard : assMezzo,
                dataInizioAttuale: inizio.isNotEmpty
                    ? inizio
                    : _fmtDate(mezzo?['periodo_assegnatario_attuale']),
                dataFineAttuale: fine.isNotEmpty
                    ? fine
                    : _fmtDate(mezzo?['data_fine_assegnatario_attuale']),
                passaggi: _passaggiFromStorico(tipo, mc, storico),
              );
            })
            .whereType<_AssetListItem>()
            .toList(growable: false);

      case LogisticaAssetTipo.telepass:
        final res = await _supa
            .from('logistica_mezzi_stradali')
            .select(
                'id_uuid,targa,telepass,assegnatario_attuale,periodo_assegnatario_attuale,data_fine_assegnatario_attuale')
            .order('telepass', ascending: true);
        final mezzi = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final seen = <String>{};
        final out = <_AssetListItem>[];
        for (final m in mezzi) {
          final tp = (m['telepass'] ?? '').toString().trim();
          if (LogisticaAssetStoricoService.isTelepassVuoto(tp)) continue;
          final key = tp.toLowerCase();
          if (seen.contains(key)) continue;
          seen.add(key);
          out.add(
            _AssetListItem(
              tipo: tipo,
              identificativo: tp,
              mezzoTarga: (m['targa'] ?? '').toString().trim(),
              mezzoIdUuid: (m['id_uuid'] ?? '').toString(),
              assegnatarioAttuale: (m['assegnatario_attuale'] ?? '').toString(),
              dataInizioAttuale:
                  _fmtDate(m['periodo_assegnatario_attuale']),
              dataFineAttuale:
                  _fmtDate(m['data_fine_assegnatario_attuale']),
              passaggi: _passaggiFromStorico(tipo, tp, storico),
            ),
          );
        }
        out.sort(
          (a, b) => a.identificativo.toLowerCase().compareTo(
                b.identificativo.toLowerCase(),
              ),
        );
        return out;
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final items = await _buildItemsForTipo(_tipo, _storicoRaw);
      if (!mounted) return;
      setState(() => _items = _filterItems(items));
    });
  }

  Future<void> _exportExcel() async {
    try {
      final excel = Excel.createExcel();
      final defaultName = excel.sheets.keys.first;
      var first = true;

      for (final tipo in LogisticaAssetTipo.values) {
        final storicoRes = await _supa
            .from('logistica_asset_assegnatari_storico')
            .select()
            .eq('tipo_asset', tipo.dbValue);
        final storico = List<Map<String, dynamic>>.from(
          (storicoRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final items = await _buildItemsForTipo(tipo, storico);

        final sheetName = tipo.label.replaceAll(' ', '_');
        final Sheet sheet;
        if (first) {
          excelRenameIfPossible(excel, defaultName, sheetName);
          sheet = excelUseDefaultSheet(excel);
          first = false;
        } else {
          sheet = excel[sheetName];
        }

        sheet.appendRow([
          'Identificativo',
          'Targa collegata',
          'Assegnatario attuale',
          'Inizio attuale',
          'Fine attuale',
          'Passaggio',
          'Assegnatario precedente',
          'Data inizio',
          'Data fine',
          'Note',
        ]);

        for (final it in items) {
          for (var p = 1; p <= 4; p++) {
            final row = it.passaggi[p];
            sheet.appendRow([
              it.identificativo,
              it.mezzoTarga ?? '',
              it.assegnatarioAttuale ?? '',
              it.dataInizioAttuale ?? '',
              it.dataFineAttuale ?? '',
              p.toString(),
              (row?['assegnatario'] ?? '').toString(),
              _fmtDate(row?['periodo_dal']),
              _fmtDate(row?['periodo_al']),
              (row?['note'] ?? '').toString(),
            ]);
          }
        }
      }

      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Storico_assegnatari',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ModifyFeedback.success(
        context,
        p.isEmpty ? 'Export Excel completato.' : 'Export Excel: $p',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore export: $e');
    }
  }

  Future<void> _openEditor(_AssetListItem item) async {
    if (!_canEdit) {
      ModifyFeedback.error(
        context,
        'La modifica dello storico è riservata agli amministratori.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _StoricoPassaggiDialog(
        supa: _supa,
        item: item,
      ),
    );
    if (ok == true) await _load(showLoader: false);
  }

  String get _identificativoHeader {
    switch (_tipo) {
      case LogisticaAssetTipo.mezzoStradale:
        return 'Targa';
      case LogisticaAssetTipo.multicard:
        return 'Multicard';
      case LogisticaAssetTipo.telepass:
        return 'Telepass';
    }
  }

  bool get _showTargaMezzoColumn => _tipo != LogisticaAssetTipo.mezzoStradale;

  List<DataColumn> _buildTableColumns() {
    return [
      DataColumn(label: Text(_identificativoHeader)),
      if (_showTargaMezzoColumn) const DataColumn(label: Text('Targa mezzo')),
      const DataColumn(label: Text('Assegnatario attuale')),
      for (var p = 1; p <= 4; p++)
        DataColumn(
          label: Text('Passaggio $p\nInizio / Fine', textAlign: TextAlign.center),
        ),
      if (_canEdit) const DataColumn(label: Text('Azioni')),
    ];
  }

  List<DataCell> _buildTableCells(_AssetListItem it) {
    return [
      DataCell(Text(it.identificativo)),
      if (_showTargaMezzoColumn) DataCell(Text(it.mezzoTarga ?? '—')),
      DataCell(
        _AssegnatarioConDateView(
          assegnatario: it.assegnatarioAttuale,
          inizio: it.dataInizioAttuale,
          fine: it.dataFineAttuale,
        ),
      ),
      for (var p = 1; p <= 4; p++)
        DataCell(_AssegnatarioConDateView.fromPassaggio(it.passaggi[p])),
      if (_canEdit)
        DataCell(
          IconButton(
            tooltip: 'Modifica storico',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openEditor(it),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Logistica - Storico assegnatari',
        ),
        actions: [
          IconButton(
            tooltip: 'Export Excel (tutte le sezioni)',
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<LogisticaAssetTipo>(
                    segments: LogisticaAssetTipo.values
                        .map(
                          (t) => ButtonSegment(
                            value: t,
                            label: Text(t.label),
                            icon: Icon(
                              t == LogisticaAssetTipo.mezzoStradale
                                  ? Icons.local_shipping_outlined
                                  : t == LogisticaAssetTipo.multicard
                                      ? Icons.credit_card_outlined
                                      : Icons.toll_outlined,
                              size: 18,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    selected: {_tipo},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) {
                      if (sel.isEmpty) return;
                      setState(() => _tipo = sel.first);
                      _load();
                    },
                  ),
                  SizedBox(
                    width: logisticaFieldWidth(context, desktop: 360),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Cerca identificativo, targa, assegnatario…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            'Nessun ${_tipo.label.toLowerCase()} trovato.',
                          ),
                        )
                      : _narrowLayout(context)
                          ? ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final it = _items[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(it.identificativo),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (it.subtitle.isNotEmpty)
                                          Text(it.subtitle),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Attuale',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        _AssegnatarioConDateView(
                                          assegnatario: it.assegnatarioAttuale,
                                          inizio: it.dataInizioAttuale,
                                          fine: it.dataFineAttuale,
                                        ),
                                        const SizedBox(height: 8),
                                        for (var p = 1; p <= 4; p++) ...[
                                          Text(
                                            'Passaggio $p',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          _AssegnatarioConDateView.fromPassaggio(
                                            it.passaggi[p],
                                          ),
                                          const SizedBox(height: 4),
                                        ],
                                      ],
                                    ),
                                    trailing: _canEdit
                                        ? IconButton(
                                            tooltip: 'Modifica 4 passaggi',
                                            icon: const Icon(Icons.edit_outlined),
                                            onPressed: () => _openEditor(it),
                                          )
                                        : null,
                                    onTap: _canEdit ? () => _openEditor(it) : null,
                                  ),
                                );
                              },
                            )
                          : DataTable2(
                              minWidth: _showTargaMezzoColumn ? 1280 : 1080,
                              columnSpacing: 12,
                              horizontalMargin: 12,
                              dataRowHeight: 78,
                              headingRowHeight: 52,
                              columns: _buildTableColumns(),
                              rows: _items
                                  .map(
                                    (it) => DataRow(cells: _buildTableCells(it)),
                                  )
                                  .toList(growable: false),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassaggioFields {
  final TextEditingController assegnatario;
  final TextEditingController periodoDal;
  final TextEditingController periodoAl;
  final TextEditingController note;
  String? existingId;

  _PassaggioFields()
      : assegnatario = TextEditingController(),
        periodoDal = TextEditingController(),
        periodoAl = TextEditingController(),
        note = TextEditingController();

  void load(Map<String, dynamic>? row) {
    existingId = row == null ? null : (row['id_uuid'] ?? '').toString();
    assegnatario.text = (row?['assegnatario'] ?? '').toString();
    periodoDal.text = formatDateDdMmYyyy(row?['periodo_dal']);
    periodoAl.text = formatDateDdMmYyyy(row?['periodo_al']);
    note.text = (row?['note'] ?? '').toString();
  }

  bool get isEmpty =>
      assegnatario.text.trim().isEmpty &&
      periodoDal.text.trim().isEmpty &&
      periodoAl.text.trim().isEmpty &&
      note.text.trim().isEmpty;

  void dispose() {
    assegnatario.dispose();
    periodoDal.dispose();
    periodoAl.dispose();
    note.dispose();
  }
}

class _StoricoPassaggiDialog extends StatefulWidget {
  final SupabaseClient supa;
  final _AssetListItem item;

  const _StoricoPassaggiDialog({
    required this.supa,
    required this.item,
  });

  @override
  State<_StoricoPassaggiDialog> createState() => _StoricoPassaggiDialogState();
}

class _StoricoPassaggiDialogState extends State<_StoricoPassaggiDialog> {
  final _fields = List.generate(4, (_) => _PassaggioFields());
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 4; i++) {
      _fields[i].load(widget.item.passaggi[i + 1]);
    }
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!await ensureCanPersist(context)) return;
    setState(() => _saving = true);
    try {
      for (var i = 0; i < 4; i++) {
        final passaggio = i + 1;
        final f = _fields[i];
        final id = (f.existingId ?? '').trim();

        if (f.isEmpty) {
          if (id.isNotEmpty) {
            await widget.supa
                .from('logistica_asset_assegnatari_storico')
                .delete()
                .eq('id_uuid', id);
          }
          continue;
        }

        final payload = <String, dynamic>{
          'tipo_asset': widget.item.tipo.dbValue,
          'identificativo': widget.item.identificativo,
          'passaggio': passaggio,
          'assegnatario':
              f.assegnatario.text.trim().isEmpty ? null : f.assegnatario.text.trim(),
          'periodo_dal': parseFlexibleDateToIsoDate(f.periodoDal.text),
          'periodo_al': parseFlexibleDateToIsoDate(f.periodoAl.text),
          'note': f.note.text.trim().isEmpty ? null : f.note.text.trim(),
          'mezzo_targa': widget.item.mezzoTarga,
          'mezzo_id_uuid': (widget.item.mezzoIdUuid ?? '').trim().isEmpty
              ? null
              : widget.item.mezzoIdUuid,
          'multicard_id_uuid':
              (widget.item.multicardIdUuid ?? '').trim().isEmpty
                  ? null
                  : widget.item.multicardIdUuid,
        };

        if (id.isEmpty) {
          await widget.supa
              .from('logistica_asset_assegnatari_storico')
              .insert(payload);
        } else {
          await widget.supa
              .from('logistica_asset_assegnatari_storico')
              .update(payload)
              .eq('id_uuid', id);
        }
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
    final it = widget.item;
    return AlertDialog(
      title: Text('Storico — ${it.identificativo}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                it.tipo.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (it._showTargaMezzo) Text('Targa mezzo: ${it.mezzoTarga}'),
              const SizedBox(height: 8),
              const Text(
                'Assegnatario attuale (sola lettura)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              _AssegnatarioConDateView(
                assegnatario: it.assegnatarioAttuale,
                inizio: it.dataInizioAttuale,
                fine: it.dataFineAttuale,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < 4; i++) ...[
                Text(
                  'Passaggio ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _fields[i].assegnatario,
                  decoration: const InputDecoration(
                    labelText: 'Assegnatario precedente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fields[i].periodoDal,
                        decoration: const InputDecoration(
                          labelText: 'Data inizio (gg/mm/aaaa)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _fields[i].periodoAl,
                        decoration: const InputDecoration(
                          labelText: 'Data fine (gg/mm/aaaa)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fields[i].note,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
              ],
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
