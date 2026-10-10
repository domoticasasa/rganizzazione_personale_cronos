import 'dart:async';
import 'package:data_table_2/data_table_2.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mdo_rifornimento_service.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/mezzi_km_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../utils/rcc_mdo_destinations.dart';
import '../utils/mdo_giustificativo_excel.dart';
import '../services/qt_carburante_dipendente_mancanti_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/carburante_scontrini_mancanti_panel.dart';
import '../utils/logistica_layout.dart';
import '../widgets/data_cell_audit_hover.dart';
import 'logistica_rcc_mdo_form_dialog.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class _MdoExportCompiler {
  final String uuid;
  final String label;
  const _MdoExportCompiler({required this.uuid, required this.label});
}

const List<String> _kMesiNomiBreve = <String>[
  'Gen',
  'Feb',
  'Mar',
  'Apr',
  'Mag',
  'Giu',
  'Lug',
  'Ago',
  'Set',
  'Ott',
  'Nov',
  'Dic',
];

class LogisticaRccMdoCarburantePage extends StatefulWidget {
  final bool dipendenteMode;
  final bool forceMobileLayout;
  final int? initialFilterYear;
  final int? initialFilterMonth;
  const LogisticaRccMdoCarburantePage({
    super.key,
    this.dipendenteMode = false,
    this.forceMobileLayout = false,
    this.initialFilterYear,
    this.initialFilterMonth,
  });

  @override
  State<LogisticaRccMdoCarburantePage> createState() =>
      _LogisticaRccMdoCarburantePageState();
}

class _LogisticaRccMdoCarburantePageState
    extends State<LogisticaRccMdoCarburantePage> with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rowsRaw = <Map<String, dynamic>>[];
  final Map<String, String> _utentiByUuid = <String, String>{};
  List<MdoUserPick> _userPicks = <MdoUserPick>[];
  String _myUserUuid = '';
  String _myDisplayName = '';
  String _myNameNorm = '';
  String _myRole = '';
  int? _myUserId;
  final Set<String> _assistenteAllowedDtUuids = <String>{};
  final Map<String, String> _assistenteDtLabelsByUuid = <String, String>{};
  String? _selectedAssistenteDtUuid;
  String? _filterCommessaUuid;
  late int _filterMonth;
  late int _filterYear;
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();
  final Map<String, String> _commessaFilterByUuid = <String, String>{};
  Map<String, Map<String, dynamic>> _mdoById = <String, Map<String, dynamic>>{};
  bool _loadingMancanti = false;
  List<QtScontrinoMancanteGiorno> _giorniMancanti =
      const <QtScontrinoMancanteGiorno>[];

  bool get _isDtView => normalizeRole(_myRole) == 'dt';
  bool get _isAssistenteDtView => normalizeRole(_myRole) == 'assistente_dt';
  bool get _isAdminView => !widget.dipendenteMode;
  bool get _canInsert {
    if (_isAssistenteDtView) {
      return _assistenteAllowedDtUuids.isNotEmpty;
    }
    return canInsertLogisticaRifornimenti(
      dipendenteMode: widget.dipendenteMode,
      role: _myRole,
    );
  }
  bool get _canEdit => canEditLogisticaRifornimenti(
        dipendenteMode: widget.dipendenteMode,
        role: _myRole,
      );
  bool get _canDelete => canDeleteLogisticaRifornimenti(
        dipendenteMode: widget.dipendenteMode,
        role: _myRole,
      );
  bool get _showLogisticaFilters => _isAdminView;
  bool _useNarrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _filterMonth = widget.initialFilterMonth ?? now.month;
    _filterYear = widget.initialFilterYear ?? now.year;
    _bootstrap();
  }

  bool _deadlineUuidAnchorsMatch(String rowUuid) {
    final t = _deadlineScrollUuid?.trim().toLowerCase();
    final r = rowUuid.trim().toLowerCase();
    return t != null && t.isNotEmpty && r.isNotEmpty && t == r;
  }

  void _onDeadlineHighlightUuid(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    setState(() => _deadlineScrollUuid = trimmed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleDeadlineScrollToAnchor(_deadlineScrollAnchorKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deadlineScrollUuid = null);
      });
    });
  }

  @override
  void dispose() {
    disposeDeadlineFlash();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadIdentity();
    if (!widget.dipendenteMode) await _loadUserPicks();
    await _loadMdoIndex();
    await _loadRows();
  }

  Future<void> _loadMdoIndex() async {
    try {
      final res = await _supa
          .from('logistica_mdo_ferroviari')
          .select('id_uuid,codice_identificativo_targa_rfi,matricola_interna');
      final map = <String, Map<String, dynamic>>{};
      for (final e in (res as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isNotEmpty) map[id] = m;
      }
      _mdoById = map;
    } catch (_) {
      _mdoById = <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _loadIdentity() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return;
    try {
      final me = await _supa
          .from('users')
          .select('id,id_uuid,full_name,username,role')
          .eq('auth_id', authId!)
          .maybeSingle();
      final rawId = me?['id'];
      _myUserId = rawId is int ? rawId : int.tryParse('$rawId');
      _myUserUuid = (me?['id_uuid'] ?? '').toString().trim();
      final full = (me?['full_name'] ?? '').toString().trim();
      final user = (me?['username'] ?? '').toString().trim();
      _myDisplayName = full.isNotEmpty ? full : user;
      _myNameNorm = MezziKmService.normalizePersonName(_myDisplayName);
      _myRole = (me?['role'] ?? '').toString().trim();
      await _loadAssistenteDtPermissions();
    } catch (_) {
      _myUserId = null;
      _myUserUuid = '';
      _myDisplayName = '';
      _myNameNorm = '';
      _myRole = '';
      _assistenteAllowedDtUuids.clear();
      _assistenteDtLabelsByUuid.clear();
      _selectedAssistenteDtUuid = null;
    }
  }

  Future<void> _loadAssistenteDtPermissions() async {
    _assistenteAllowedDtUuids.clear();
    _assistenteDtLabelsByUuid.clear();
    _selectedAssistenteDtUuid = null;
    if (!_isAssistenteDtView || (_myUserId ?? -1) <= 0) return;
    try {
      final permsRes = await _supa
          .from('assistente_dt_permissions')
          .select('grantor_dt_user_uuid')
          .eq('assistant_user_id', _myUserId!);
      final allowed = <String>{};
      for (final e in (permsRes as List)) {
        final u = (e['grantor_dt_user_uuid'] ?? '').toString().trim();
        if (u.isNotEmpty) allowed.add(u);
      }
      if (allowed.isEmpty) return;
      _assistenteAllowedDtUuids.addAll(allowed);
      final users = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .inFilter('id_uuid', allowed.toList());
      for (final raw in (users as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final full = (m['full_name'] ?? '').toString().trim();
        final usr = (m['username'] ?? '').toString().trim();
        _assistenteDtLabelsByUuid[id] = full.isNotEmpty ? full : usr;
      }
      if (_assistenteAllowedDtUuids.isNotEmpty) {
        _selectedAssistenteDtUuid = _assistenteAllowedDtUuids.first;
      }
    } catch (_) {}
  }

  Future<void> _loadUserPicks() async {
    try {
      final res = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .order('full_name', ascending: true)
          .limit(2500);
      final list = <MdoUserPick>[];
      for (final e in (res as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final full = (m['full_name'] ?? '').toString().trim();
        final user = (m['username'] ?? '').toString().trim();
        list.add(MdoUserPick(uuid: id, label: full.isNotEmpty ? full : (user.isNotEmpty ? user : id)));
      }
      if (mounted) setState(() => _userPicks = list);
    } catch (_) {}
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final fromDate = DateTime(_filterYear, _filterMonth, 1);
      final toDate = DateTime(_filterYear, _filterMonth + 1, 1);
      final fromIso = fromDate.toIso8601String().substring(0, 10);
      final toIso = toDate.toIso8601String().substring(0, 10);

      dynamic q = _supa
          .from('logistica_rcc_mdo_carburante')
          .select(
            'id_uuid,user_uuid,dt_user_uuid,data_rifornimento,'
            'n_carta_carburante,litri,euro,tipo_carburante,cantiere,'
            'commessa_uuid,nome_cognome,automezzo_mdo,targa_matricola,'
            'mezzi_riforniti_json,rifornimento_completo,mezzo_stradale_id_uuid,'
            'firma_compilatore,created_at,updated_at,'
            'created_by_user_uuid,updated_by_user_uuid,field_timestamps',
          )
          .gte('data_rifornimento', fromIso)
          .lt('data_rifornimento', toIso);

      if (widget.dipendenteMode && _myUserUuid.isNotEmpty) {
        q = q.eq('user_uuid', _myUserUuid);
      } else if (_isDtView && _myUserUuid.isNotEmpty) {
        q = q.eq('dt_user_uuid', _myUserUuid);
      } else if (_isAssistenteDtView) {
        if (_assistenteAllowedDtUuids.isEmpty) {
          if (!mounted) return;
          setState(() {
            _rowsRaw = <Map<String, dynamic>>[];
            _rows = <Map<String, dynamic>>[];
            if (showLoader) _loading = false;
          });
          return;
        }
        final selected = (_selectedAssistenteDtUuid ?? '').trim();
        if (selected.isNotEmpty) {
          q = q.eq('dt_user_uuid', selected);
        } else {
          q = q.inFilter(
            'dt_user_uuid',
            _assistenteAllowedDtUuids.toList(growable: false),
          );
        }
      }

      final res = await q
          .order('data_rifornimento', ascending: false)
          .limit(2000);
      final list = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)));

      _commessaFilterByUuid.clear();
      for (final r in list) {
        final id = (r['commessa_uuid'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          final name = (r['cantiere'] ?? '').toString().trim();
          _commessaFilterByUuid[id] = name.isEmpty ? id : name;
        }
      }
      if ((_filterCommessaUuid ?? '').isNotEmpty &&
          !_commessaFilterByUuid.containsKey(_filterCommessaUuid)) {
        _filterCommessaUuid = null;
      }
      final ids = <String>{};
      for (final r in list) {
        final all = [
          r['created_by_user_uuid'],
          r['updated_by_user_uuid'],
          r['user_uuid'],
          r['dt_user_uuid']
        ].map((e) => (e ?? '').toString().trim());
        for (final id in all) {
          if (id.isNotEmpty) ids.add(id);
        }
        mergeFieldTimestampActorUuids(r, ids);
      }
      final userMap = <String, String>{};
      if (ids.isNotEmpty) {
        final users = await _supa.from('users').select('id_uuid,full_name,username').inFilter('id_uuid', ids.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          if (id.isNotEmpty) userMap[id] = full.isNotEmpty ? full : user;
        }
      }
      if (!mounted) return;
      setState(() {
        _rowsRaw = list;
        _utentiByUuid
          ..clear()
          ..addAll(userMap);
        if (showLoader) _loading = false;
      });
      _applyClientFilters();
      maybeConsumeDeadlineFlashUuid(onHighlight: _onDeadlineHighlightUuid);
      if (widget.dipendenteMode) {
        await _loadDateMancanti();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rowsRaw = [];
        _rows = [];
        if (showLoader) _loading = false;
      });
      ModifyFeedback.error(context, 'Errore caricamento: $e');
    }
  }

  Future<void> _loadDateMancanti() async {
    if (!widget.dipendenteMode || _myNameNorm.isEmpty) return;
    if (mounted) setState(() => _loadingMancanti = true);
    try {
      final giorni = await QtCarburanteDipendenteMancantiService.loadDateMancanti(
        supa: _supa,
        anno: _filterYear,
        mese: _filterMonth,
        dipendenteNomeNorm: _myNameNorm,
      );
      if (!mounted) return;
      setState(() {
        _giorniMancanti = giorni;
        _loadingMancanti = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _giorniMancanti = const <QtScontrinoMancanteGiorno>[];
        _loadingMancanti = false;
      });
    }
  }

  void _onFilterMonthYearChanged() {
    unawaited(_loadRows());
    if (widget.dipendenteMode) {
      unawaited(_loadDateMancanti());
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _applyClientFilters();
    });
  }

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  String _dataInserimentoLabel(Map<String, dynamic> r) {
    final s = formatDateTimeItFromSupabase(r['created_at']);
    return s.isEmpty ? '—' : s;
  }

  DateTime? _parseRifornimentoDate(dynamic v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    final iso = parseFlexibleDateToIsoDate(raw);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  Iterable<String> _rowSearchTokens(Map<String, dynamic> r) sync* {
    final uLab = _utentiByUuid[(r['user_uuid'] ?? '').toString().trim()] ?? '';
    final dtLab = _utentiByUuid[(r['dt_user_uuid'] ?? '').toString().trim()] ?? '';
    yield* [
      r['n_carta_carburante'],
      r['litri'],
      r['euro'],
      r['cantiere'],
      r['commessa_uuid'],
      r['tipo_carburante'],
      r['automezzo_mdo'],
      r['targa_matricola'],
      r['nome_cognome'],
      r['data_rifornimento'],
      formatDateDdMmYyyy(r['data_rifornimento']),
      mdoMezziNumeriSummary(r, _mdoById),
      uLab,
      dtLab,
    ].map((v) => (v ?? '').toString().toLowerCase());
  }

  bool _rowMatchesSearch(Map<String, dynamic> r, String k) {
    return _rowSearchTokens(r).any((f) => f.contains(k));
  }

  List<int> get _availableYears {
    final nowY = DateTime.now().year;
    final years = <int>{_filterYear, nowY};
    for (var y = nowY + 1; y >= nowY - 5; y--) {
      years.add(y);
    }
    for (final r in _rowsRaw) {
      final d = _parseRifornimentoDate(r['data_rifornimento']);
      if (d != null) years.add(d.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  void _applyClientFilters() {
    if (!mounted) return;
    var list = List<Map<String, dynamic>>.from(_rowsRaw);
    if ((_filterCommessaUuid ?? '').isNotEmpty) {
      list = list
          .where(
            (r) => (r['commessa_uuid'] ?? '').toString().trim() == _filterCommessaUuid,
          )
          .toList(growable: false);
    }
    final k = _search.toLowerCase().trim();
    if (k.isNotEmpty) {
      list = list.where((r) => _rowMatchesSearch(r, k)).toList(growable: false);
    }
    setState(() => _rows = list);
  }

  Widget _buildMonthYearFilters() {
    final scheme = Theme.of(context).colorScheme;
    final currentMonth = DateTime.now().month;
    final currentYear = DateTime.now().year;
    Widget monthChip(int m) {
      final selected = _filterMonth == m;
      final isCurrent = m == currentMonth && _filterYear == currentYear;
      return ChoiceChip(
        label: Text(_kMesiNomiBreve[m - 1]),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterMonth = m);
          _onFilterMonthYearChanged();
        },
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        selectedColor: scheme.primary,
        backgroundColor: isCurrent ? scheme.primary.withValues(alpha: 0.10) : null,
        side: isCurrent && !selected ? BorderSide(color: scheme.primary, width: 1.4) : null,
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimary : scheme.onSurface,
          fontWeight: selected || isCurrent ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
      );
    }

    final years = _availableYears;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<int>(
              initialValue: years.contains(_filterYear) ? _filterYear : years.first,
              items: years
                  .map((y) => DropdownMenuItem<int>(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (y) {
                if (y == null) return;
                setState(() => _filterYear = y);
                _onFilterMonthYearChanged();
              },
              decoration: const InputDecoration(
                labelText: 'Anno',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var m = 1; m <= 12; m++) ...[
                    monthChip(m),
                    if (m < 12) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommessaFilterField() {
    final commessaKeys = _commessaFilterByUuid.keys.toList()
      ..sort(
        (a, b) =>
            (_commessaFilterByUuid[a] ?? '').compareTo(_commessaFilterByUuid[b] ?? ''),
      );
    return DropdownSearch<String?>(
      selectedItem: _filterCommessaUuid,
      items: [null, ...commessaKeys],
      itemAsString: (id) {
        if ((id ?? '').trim().isEmpty) return 'Tutte le commesse';
        return _commessaFilterByUuid[id] ?? id!;
      },
      compareFn: (a, b) => (a ?? '') == (b ?? ''),
      dropdownDecoratorProps: const DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: 'Filtro Commessa',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      popupProps: const PopupProps.menu(showSearchBox: true, fit: FlexFit.loose),
      onChanged: (v) {
        setState(() => _filterCommessaUuid = v);
        _applyClientFilters();
      },
    );
  }

  String _userLabel(String? id) {
    final u = (id ?? '').trim();
    if (u.isEmpty) return '—';
    return _utentiByUuid[u] ?? u;
  }

  String _mezziLabel(Map<String, dynamic> r) =>
      mdoMezziNumeriSummary(r, _mdoById);

  bool _dipendenteLocked(Map<String, dynamic> r) =>
      isMdoRifornimentoLockedForDipendente(r, dipendenteMode: widget.dipendenteMode);

  DataCell _hoverCell(Widget child, Map<String, dynamic> r, String fieldKey) {
    return decorateDataCellWithAuditHover(
      DataCell(child),
      row: r,
      fieldKey: fieldKey,
      userNamesByUuid: _utentiByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final isNew = row == null;
    if (isNew) {
      if (!_canInsert) return;
    } else if (!_canEdit) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => MdoRccFormDialog(
          supa: _supa,
          dipendenteMode: widget.dipendenteMode,
          myUserUuid: _myUserUuid,
          myDisplayName: _myDisplayName,
          myNameNorm: _myNameNorm,
          userPicks: _userPicks,
          lockDtUuid: _isDtView ? _myUserUuid : null,
          // Assistente: in giustificazione può scegliere qualsiasi DT;
          // in elenco vede solo i DT che lo hanno autorizzato.
          allowedDtUuids: const <String>[],
          initialDtUuid:
              _isAssistenteDtView ? _selectedAssistenteDtUuid : null,
          viewOnly: true,
          existing: row,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => MdoRccFormDialog(
        supa: _supa,
        dipendenteMode: widget.dipendenteMode,
        myUserUuid: _myUserUuid,
        myDisplayName: _myDisplayName,
        myNameNorm: _myNameNorm,
        userPicks: _userPicks,
        lockDtUuid: _isDtView ? _myUserUuid : null,
        allowedDtUuids: const <String>[],
        initialDtUuid:
            _isAssistenteDtView ? _selectedAssistenteDtUuid : null,
        viewOnly: false,
        existing: row,
      ),
    );
    if (ok == true) {
      await _loadRows();
      if (mounted) ModifyFeedback.success(context, row == null ? 'Riga inserita.' : 'Riga aggiornata.');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (!_canDelete) return;
    if (!await ensureCanPersist(context)) return;
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina riga'),
        content: const Text('Eliminare questo rifornimento MDO?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('logistica_rcc_mdo_carburante').delete().eq('id_uuid', id);
      await _loadRows();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  (String, String) _isoRangeForMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final isoStart =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final isoEnd =
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    return (isoStart, isoEnd);
  }

  Future<List<Map<String, dynamic>>> _fetchRowsForExportMonth(int year, int month) async {
    final (isoStart, isoEnd) = _isoRangeForMonth(year, month);
    var q = _supa
        .from('logistica_rcc_mdo_carburante')
        .select()
        .gte('data_rifornimento', isoStart)
        .lte('data_rifornimento', isoEnd);
    if (_isDtView && _myUserUuid.isNotEmpty) {
      q = q.eq('dt_user_uuid', _myUserUuid);
    } else if (_isAssistenteDtView) {
      final selected = (_selectedAssistenteDtUuid ?? '').trim();
      if (selected.isNotEmpty) {
        q = q.eq('dt_user_uuid', selected);
      } else if (_assistenteAllowedDtUuids.isNotEmpty) {
        q = q.inFilter('dt_user_uuid', _assistenteAllowedDtUuids.toList());
      }
    }
    final res = await q.order('data_rifornimento', ascending: true);
    return List<Map<String, dynamic>>.from(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  String _compilatoreLabelFromRow(Map<String, dynamic> r) {
    final uid = (r['user_uuid'] ?? '').toString().trim();
    if (uid.isNotEmpty) {
      final n = _utentiByUuid[uid];
      if (n != null && n.isNotEmpty) return n;
    }
    return (r['nome_cognome'] ?? '').toString().trim();
  }

  Future<({List<_MdoExportCompiler> compilers, List<String> multicards})> _exportFilterOptions(
    int year,
    int month,
  ) async {
    final rows = await _fetchRowsForExportMonth(year, month);
    final byUuid = <String, String>{};
    final cards = <String>{};
    for (final r in rows) {
      final card = (r['n_carta_carburante'] ?? '').toString().trim();
      if (card.isNotEmpty) cards.add(card);
      final uid = (r['user_uuid'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      byUuid.putIfAbsent(uid, () => _compilatoreLabelFromRow(r));
    }
    final missing = byUuid.keys.where((id) => byUuid[id] == id).toList();
    if (missing.isNotEmpty) {
      try {
        final users = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', missing);
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          if (id.isNotEmpty) byUuid[id] = full.isNotEmpty ? full : user;
        }
      } catch (_) {}
    }
    final compilers = byUuid.entries
        .map((e) => _MdoExportCompiler(uuid: e.key, label: e.value.isEmpty ? e.key : e.value))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final multicards = cards.toList()..sort();
    return (compilers: compilers, multicards: multicards);
  }

  Future<(int year, int month, String? compilatoreUuid, String? multicard)?> _pickMdoExportFilters() async {
    final now = DateTime.now();
    var selYear = now.year;
    var selMonth = now.month;
    String? selCompilatoreUuid;
    String? selMulticard;
    var optionsLoading = true;
    List<_MdoExportCompiler> compilers = <_MdoExportCompiler>[];
    List<String> multicards = <String>[];
    List<Map<String, dynamic>> monthRows = <Map<String, dynamic>>[];

    List<String> multicardsFromRows(List<Map<String, dynamic>> rows) {
      final s = <String>{};
      for (final r in rows) {
        final card = (r['n_carta_carburante'] ?? '').toString().trim();
        if (card.isNotEmpty) s.add(card);
      }
      return s.toList()..sort();
    }

    void applyMulticardSelection(StateSetter setSt) {
      if (selMulticard != null && !multicards.contains(selMulticard)) selMulticard = null;
      if (multicards.length == 1) selMulticard = multicards.first;
    }

    Future<void> reload(StateSetter setSt) async {
      setSt(() => optionsLoading = true);
      monthRows = await _fetchRowsForExportMonth(selYear, selMonth);
      final opt = await _exportFilterOptions(selYear, selMonth);
      if (!mounted) return;
      setSt(() {
        optionsLoading = false;
        compilers = opt.compilers;
        multicards = multicardsFromRows(monthRows);
        if (selCompilatoreUuid != null &&
            !compilers.any((c) => c.uuid == selCompilatoreUuid)) {
          selCompilatoreUuid = null;
        }
        applyMulticardSelection(setSt);
      });
    }

    void onCompilatoreChanged(StateSetter setSt, String? v) {
      setSt(() {
        selCompilatoreUuid = v;
        var rows = monthRows;
        if ((v ?? '').trim().isNotEmpty) {
          rows = rows
              .where((r) => (r['user_uuid'] ?? '').toString().trim() == v!.trim())
              .toList(growable: false);
        }
        multicards = multicardsFromRows(rows);
        applyMulticardSelection(setSt);
      });
    }

    String monthLabel(int mm) {
      final raw = DateFormat.MMMM('it_IT').format(DateTime(2000, mm, 1));
      return raw.isEmpty ? '$mm' : '${raw[0].toUpperCase()}${raw.substring(1)}';
    }

    var initialOptionsLoad = true;
    final result = await showDialog<(int, int, String?, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          if (initialOptionsLoad) {
            initialOptionsLoad = false;
            unawaited(reload(setSt));
          }
          final showMulticardPicker = multicards.length > 1;
          return AlertDialog(
            title: const Text('Export Giustificativo Carburante MDO'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selMonth,
                    decoration: const InputDecoration(
                      labelText: 'Mese',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (var mm = 1; mm <= 12; mm++)
                        DropdownMenuItem(value: mm, child: Text(monthLabel(mm))),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setSt(() => selMonth = v);
                      await reload(setSt);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selYear,
                    decoration: const InputDecoration(
                      labelText: 'Anno',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (var yy = now.year - 8; yy <= now.year + 2; yy++)
                        DropdownMenuItem(value: yy, child: Text('$yy')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setSt(() => selYear = v);
                      await reload(setSt);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (optionsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    DropdownSearch<String?>(
                      selectedItem: selCompilatoreUuid,
                      items: [null, ...compilers.map((c) => c.uuid)],
                      itemAsString: (id) {
                        if ((id ?? '').trim().isEmpty) return 'Tutti i compilatori';
                        final m = compilers.where((c) => c.uuid == id);
                        return m.isEmpty ? (id ?? '') : m.first.label;
                      },
                      compareFn: (a, b) => (a ?? '') == (b ?? ''),
                      dropdownDecoratorProps: const DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: 'Compilatore',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      popupProps: const PopupProps.menu(showSearchBox: true, fit: FlexFit.loose),
                      onChanged: (v) => onCompilatoreChanged(setSt, v),
                    ),
                    if (showMulticardPicker) ...[
                      const SizedBox(height: 12),
                      DropdownSearch<String?>(
                        selectedItem: selMulticard,
                        items: [null, ...multicards],
                        itemAsString: (s) => (s ?? '').trim().isEmpty
                            ? 'Tutte le multicard'
                            : s!,
                        compareFn: (a, b) => (a ?? '') == (b ?? ''),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'N° multicard',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        popupProps: const PopupProps.menu(showSearchBox: true, fit: FlexFit.loose),
                        onChanged: (v) => setSt(() => selMulticard = v),
                      ),
                    ] else if (multicards.length == 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Multicard: ${multicards.first}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
              FilledButton(
                onPressed: optionsLoading
                    ? null
                    : () => Navigator.pop(
                          ctx,
                          (selYear, selMonth, selCompilatoreUuid, selMulticard),
                        ),
                child: const Text('Esporta'),
              ),
            ],
          );
        },
      ),
    );
    return result;
  }

  Future<void> _export() async {
    if (widget.dipendenteMode) return;
    final picked = await _pickMdoExportFilters();
    if (picked == null || !mounted) return;
    final (y, m, compilatoreUuid, multicard) = picked;
    try {
      var list = await _fetchRowsForExportMonth(y, m);
      if ((compilatoreUuid ?? '').trim().isNotEmpty) {
        list = list
            .where((r) => (r['user_uuid'] ?? '').toString().trim() == compilatoreUuid!.trim())
            .toList(growable: false);
      }
      if ((multicard ?? '').trim().isNotEmpty) {
        list = list
            .where((r) => (r['n_carta_carburante'] ?? '').toString().trim() == multicard!.trim())
            .toList(growable: false);
      }
      if (list.isEmpty) {
        if (mounted) {
          ModifyFeedback.hint(context, 'Nessun rifornimento per i filtri selezionati.');
        }
        return;
      }

      final userMap = <String, String>{};
      final ids = <String>{};
      for (final r in list) {
        for (final k in ['user_uuid', 'dt_user_uuid']) {
          final id = (r[k] ?? '').toString().trim();
          if (id.isNotEmpty) ids.add(id);
        }
      }
      if (ids.isNotEmpty) {
        final users = await _supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', ids.toList());
        for (final e in (users as List)) {
          final row = Map<String, dynamic>.from(e as Map);
          final id = (row['id_uuid'] ?? '').toString().trim();
          final full = (row['full_name'] ?? '').toString().trim();
          final user = (row['username'] ?? '').toString().trim();
          if (id.isNotEmpty) userMap[id] = full.isNotEmpty ? full : user;
        }
      }

      final bytes = await buildMdoGiustificativoExcelBytes(
        year: y,
        month: m,
        rows: list,
        userNamesByUuid: userMap,
        mdoById: _mdoById,
      );
      final diag = lastMdoGiustificativoExportInfo;
      final cardSuffix = (multicard ?? '').trim().isEmpty
          ? ''
          : '_${multicard!.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName:
            'Giustificativo_Carburante_MDO_${y}_${m.toString().padLeft(2, '0')}$cardSuffix',
        bytes: bytes,
        openFile: true,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      final mediaNote = diag != null
          ? '\nLogo/certificazioni: ${diag.embeddedMediaCount} immagini (Python: ${diag.pythonExecutable}).'
          : '\nFile scaricato dal browser (layout e immagini dal template originale).';
      ModifyFeedback.success(
        context,
        p.isEmpty
            ? 'Export giustificativo MDO completato.$mediaNote\nScorri in basso (riga 29+) per firma e certificazioni.'
            : 'Export giustificativo MDO completato.$mediaNote\n$p\nScorri in basso (riga 29+) per firma e logo.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore export: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.dipendenteMode
        ? 'Rifornimento MDO'
        : (_isDtView ? 'Rifornimento MDO' : 'Rifornimento MDO (Logistica)');
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(title: title),
        actions: [
          if (_canInsert && _useNarrowLayout(context))
            IconButton(
              tooltip: 'Nuovo rifornimento',
              icon: const Icon(Icons.add),
              onPressed: _loading ? null : () => _openForm(),
            ),
          if (!widget.dipendenteMode)
            IconButton(
              tooltip: 'Export Giustificativo MDO',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: _loading ? null : _export,
            ),
        ],
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _useNarrowLayout(context)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Cerca',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: _onSearchChanged,
                              ),
                              if (_isAssistenteDtView &&
                                  _assistenteAllowedDtUuids.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: (_selectedAssistenteDtUuid ?? '')
                                          .trim()
                                          .isEmpty
                                      ? null
                                      : _selectedAssistenteDtUuid,
                                  items: _assistenteAllowedDtUuids
                                      .map(
                                        (id) => DropdownMenuItem(
                                          value: id,
                                          child: Text(
                                            _assistenteDtLabelsByUuid[id] ??
                                                id,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) async {
                                    setState(
                                        () => _selectedAssistenteDtUuid = v);
                                    await _loadRows(showLoader: false);
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'DT autorizzato',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'Cerca',
                                    prefixIcon: Icon(Icons.search),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: _onSearchChanged,
                                ),
                              ),
                              if (_isAssistenteDtView &&
                                  _assistenteAllowedDtUuids.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 280,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: (_selectedAssistenteDtUuid ?? '')
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : _selectedAssistenteDtUuid,
                                    items: _assistenteAllowedDtUuids
                                        .map(
                                          (id) => DropdownMenuItem(
                                            value: id,
                                            child: Text(
                                              _assistenteDtLabelsByUuid[
                                                      id] ??
                                                  id,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) async {
                                      setState(
                                          () => _selectedAssistenteDtUuid = v);
                                      await _loadRows(showLoader: false);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'DT autorizzato',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _useNarrowLayout(context)
                        ? Column(
                            children: [
                              _buildMonthYearFilters(),
                              if (_showLogisticaFilters) ...[
                                const SizedBox(height: 8),
                                _buildCommessaFilterField(),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildMonthYearFilters()),
                              if (_showLogisticaFilters) ...[
                                const SizedBox(width: 12),
                                Expanded(child: _buildCommessaFilterField()),
                              ],
                            ],
                          ),
                  ),
                  if (widget.dipendenteMode)
                    CarburanteScontriniMancantiPanel(
                      loading: _loadingMancanti,
                      anno: _filterYear,
                      mese: _filterMonth,
                      giorni: _giorniMancanti,
                      monthLabel:
                          '${_kMesiNomiBreve[_filterMonth - 1]} $_filterYear',
                    ),
                  Expanded(
                    child: _useNarrowLayout(context)
                        ? _buildMobileList()
                        : _buildDesktopTable(),
                  ),
                ],
              ),
      ),
      floatingActionButton: _canInsert
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nuova riga'),
            )
          : null,
    );
  }

  Widget _buildMobileList() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _canInsert
              ? 'Nessun rifornimento. Usa «Nuova riga» per inserire.'
              : 'Nessun rifornimento.',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      itemCount: _rows.length,
      itemBuilder: (ctx, i) {
        final r = _rows[i];
        final id = (r['id_uuid'] ?? '').toString();
        final flash = id.isNotEmpty && deadlineFlashLit(id);
        return KeyedSubtree(
          key: _deadlineUuidAnchorsMatch(id)
              ? _deadlineScrollAnchorKey
              : ValueKey<String>('mdo_mobile_$id'),
          child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: flash ? Colors.amber : Colors.transparent,
              width: flash ? 3 : 0,
            ),
          ),
          child: ListTile(
            onTap: () => _openForm(row: r),
            title: Text(_fmtDate(r['data_rifornimento']), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${_dipendenteLocked(r) ? 'Completo · ' : ''}'
              'Carta: ${(r['n_carta_carburante'] ?? '').toString().trim().isEmpty ? '—' : r['n_carta_carburante']}\n'
              'Carburante: ${(r['tipo_carburante'] ?? '').toString().trim().isEmpty ? '—' : r['tipo_carburante']}\n'
              'Litri: ${r['litri'] ?? '—'} · Euro: ${r['euro'] ?? '—'}\n'
              'Inserito: ${_dataInserimentoLabel(r)}\n'
              'Mezzi: ${_mezziLabel(r)}\n'
              'DT: ${_userLabel((r['dt_user_uuid'] ?? '').toString())}',
            ),
            trailing: !_canEdit
                ? const Icon(Icons.visibility_outlined, color: Colors.grey)
                : _dipendenteLocked(r)
                    ? const Icon(Icons.lock_outline, color: Colors.green)
                    : _canDelete
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(r),
                          )
                        : null,
          ),
        ),
        );
      },
    );
  }

  Widget _buildDesktopTable() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _canInsert
              ? 'Nessun rifornimento. Usa «Nuova riga» per inserire.'
              : 'Nessun rifornimento.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      child: DataTable2(
        minWidth: _isAdminView ? 1340 : 1140,
        columns: [
          const DataColumn2(label: Text('Data'), size: ColumnSize.S),
          const DataColumn2(label: Text('Data inserimento'), size: ColumnSize.S),
          const DataColumn2(label: Text('Multicard'), size: ColumnSize.M),
          const DataColumn2(label: Text('Litri'), size: ColumnSize.S),
          const DataColumn2(label: Text('Euro'), size: ColumnSize.S),
          const DataColumn2(label: Text('Carburante'), size: ColumnSize.S),
          const DataColumn2(label: Text('Commessa'), size: ColumnSize.M),
          const DataColumn2(label: Text('DT'), size: ColumnSize.M),
          const DataColumn2(label: Text('Mezzi'), size: ColumnSize.M),
          if (_isAdminView) const DataColumn2(label: Text('Compilatore'), size: ColumnSize.M),
          const DataColumn2(label: Text(''), size: ColumnSize.S),
        ],
        rows: _rows.map((r) {
          final id = (r['id_uuid'] ?? '').toString();
          return DataRow2(
            key: ValueKey(r['id_uuid']),
            color: WidgetStateProperty.resolveWith<Color?>(
              (_) => deadlineFlashLit(id)
                  ? Colors.amber.withValues(alpha: 0.42)
                  : null,
            ),
            onTap: () => _openForm(row: r),
            cells: [
              _hoverCell(
                SizedBox(
                  key: _deadlineUuidAnchorsMatch(id)
                      ? _deadlineScrollAnchorKey
                      : null,
                  child: Text(_fmtDate(r['data_rifornimento'])),
                ),
                r,
                'data_rifornimento',
              ),
              DataCell(Text(_dataInserimentoLabel(r))),
              _hoverCell(Text((r['n_carta_carburante'] ?? '').toString()), r, 'n_carta_carburante'),
              _hoverCell(Text((r['litri'] ?? '').toString()), r, 'litri'),
              _hoverCell(Text((r['euro'] ?? '').toString()), r, 'euro'),
              _hoverCell(
                Text((r['tipo_carburante'] ?? '').toString()),
                r,
                'tipo_carburante',
              ),
              _hoverCell(Text((r['cantiere'] ?? '').toString()), r, 'cantiere'),
              DataCell(Text(_userLabel((r['dt_user_uuid'] ?? '').toString().trim()))),
              _hoverCell(Text(_mezziLabel(r)), r, 'mezzi_riforniti_json'),
              if (_isAdminView) DataCell(Text(_userLabel((r['user_uuid'] ?? '').toString().trim()))),
              DataCell(
                !_canEdit
                    ? const Icon(Icons.visibility_outlined, size: 20, color: Colors.grey)
                    : _dipendenteLocked(r)
                        ? const Icon(Icons.lock_outline, size: 20, color: Colors.green)
                        : _canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _confirmDelete(r),
                              )
                            : const SizedBox.shrink(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
