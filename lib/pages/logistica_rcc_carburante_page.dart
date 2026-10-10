import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_assignee_at_date.dart';
import '../services/mdo_rifornimento_service.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/qt_multicard_storico_assignee.dart';
import '../services/rcc_ricevuta_carburante_parser.dart';
import '../services/rcc_ricevuta_import_service.dart';
import '../services/rcc_ricevuta_ocr.dart';
import '../services/mezzi_km_service.dart';
import '../utils/carburante_euro_litro_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/modify_feedback.dart';
import '../utils/pernottamento_commessa_suggest_dialog.dart';
import '../utils/dt_user_list.dart';
import '../utils/logistica_layout.dart';
import '../utils/roles.dart';
import '../utils/rcc_mod04_excel.dart';
import '../services/qt_carburante_dipendente_mancanti_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/carburante_scontrini_mancanti_panel.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class _RccExportCompiler {
  final String uuid;
  final String label;
  const _RccExportCompiler({required this.uuid, required this.label});
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

/// Registro rifornimenti carburante (Mod.RCC — gasolio mezzi stradali).
class LogisticaRccCarburantePage extends StatefulWidget {
  final bool dipendenteMode;
  final bool forceMobileLayout;
  final int? initialFilterYear;
  final int? initialFilterMonth;

  const LogisticaRccCarburantePage({
    super.key,
    this.dipendenteMode = false,
    this.forceMobileLayout = false,
    this.initialFilterYear,
    this.initialFilterMonth,
  });

  @override
  State<LogisticaRccCarburantePage> createState() =>
      _LogisticaRccCarburantePageState();
}

class _LogisticaRccCarburantePageState extends State<LogisticaRccCarburantePage>
    with DeadlineFlashTicker {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rowsRaw = <Map<String, dynamic>>[];
  late int _filterMonth;
  late int _filterYear;
  String? _deadlineScrollUuid;
  final GlobalKey _deadlineScrollAnchorKey = GlobalKey();
  final Map<String, String> _utentiByUuid = <String, String>{};
  String _myUserUuid = '';
  int? _myUserId;
  String _myDisplayName = '';
  String _myNameNorm = '';
  String _myRole = '';
  final Set<String> _assistenteAllowedDtUuids = <String>{};
  final Map<String, String> _assistenteDtLabelsByUuid = <String, String>{};
  String? _selectedAssistenteDtUuid;
  bool _loadingMancanti = false;
  List<QtScontrinoMancanteGiorno> _giorniMancanti =
      const <QtScontrinoMancanteGiorno>[];

  bool get _isDtView => normalizeRole(_myRole) == 'dt';
  bool get _isAssistenteDtView => normalizeRole(_myRole) == 'assistente_dt';
  bool get _isAdminView => !widget.dipendenteMode;
  bool get _canInsert {
    // Assistente DT: solo per i DT a cui è autorizzato (mai per altri dipendenti).
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

  bool _canEditRow(Map<String, dynamic> row) {
    if (widget.dipendenteMode) {
      final owner = (row['user_uuid'] ?? '').toString().trim();
      return owner == _myUserUuid && isMdoRifornimentoWithinEditGrace(row);
    }
    final role = normalizeRole(_myRole);
    if (role == 'dt' || role == 'assistente_dt') return false;
    return _canEdit;
  }

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
    await _loadRows();
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
    } catch (_) {
      // fallback silenzioso: nessun permesso
    }
  }

  Future<void> _loadRows({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final fromDate = DateTime(_filterYear, _filterMonth, 1);
      final toDate = DateTime(_filterYear, _filterMonth + 1, 1);
      final fromIso = fromDate.toIso8601String().substring(0, 10);
      final toIso = toDate.toIso8601String().substring(0, 10);

      dynamic q = _supa
          .from('logistica_rcc_carburante')
          .select(
            'id_uuid,user_uuid,dt_user_uuid,mezzo_stradale_id_uuid,'
            'data_rifornimento,n_carta_carburante,km_ore,litri,euro,'
            'tipo_carburante,cantiere,commessa_uuid,nome_cognome,'
            'automezzo_mdo,targa_matricola,firma_compilatore,note,'
            'created_at,updated_at,created_by_user_uuid,updated_by_user_uuid,'
            'field_timestamps',
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
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final ids = <String>{};
      for (final r in list) {
        final c = (r['created_by_user_uuid'] ?? '').toString().trim();
        final u = (r['updated_by_user_uuid'] ?? '').toString().trim();
        final uu = (r['user_uuid'] ?? '').toString().trim();
        final dt = (r['dt_user_uuid'] ?? '').toString().trim();
        if (c.isNotEmpty) ids.add(c);
        if (u.isNotEmpty) ids.add(u);
        if (uu.isNotEmpty) ids.add(uu);
        if (dt.isNotEmpty) ids.add(dt);
        mergeFieldTimestampActorUuids(r, ids);
      }
      final userMap = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final users = await _supa
              .from('users')
              .select('id_uuid,full_name,username')
              .inFilter('id_uuid', ids.toList());
          for (final e in (users as List)) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = (m['id_uuid'] ?? '').toString();
            final full = (m['full_name'] ?? '').toString().trim();
            final user = (m['username'] ?? '').toString().trim();
            if (id.isNotEmpty) userMap[id] = full.isNotEmpty ? full : user;
          }
        } catch (_) {}
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
      if (mounted) {
        setState(() {
          _rowsRaw = <Map<String, dynamic>>[];
          _rows = <Map<String, dynamic>>[];
          if (showLoader) _loading = false;
        });
        ModifyFeedback.error(context, 'Errore caricamento: $e');
      }
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

  DateTime? _rowRifornimentoDate(Map<String, dynamic> r) {
    final raw = (r['data_rifornimento'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Iterable<String> _rowSearchTokens(Map<String, dynamic> r) sync* {
    final dtUuid = (r['dt_user_uuid'] ?? '').toString().trim();
    final userUuid = (r['user_uuid'] ?? '').toString().trim();
    yield* [
      r['n_carta_carburante'],
      r['km_ore'],
      r['cantiere'],
      r['commessa_uuid'],
      r['tipo_carburante'],
      r['automezzo_mdo'],
      r['targa_matricola'],
      r['firma_compilatore'],
      r['nome_cognome'],
      r['note'],
      r['litri'],
      r['euro'],
      r['data_rifornimento'],
      formatDateDdMmYyyy(r['data_rifornimento']),
      _kmOreLabel(r),
      _kmOreInseritoLabel(r),
      _compilatoreLabel(r),
      _dtLabel(r),
      _mezzoLabelFromRow(r),
      _utentiByUuid[userUuid],
      _utentiByUuid[dtUuid],
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
      final d = _rowRifornimentoDate(r);
      if (d != null) years.add(d.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  void _applyClientFilters() {
    if (!mounted) return;
    // Il mese è già filtrato server-side; qui resta solo la ricerca testuale.
    var list = List<Map<String, dynamic>>.from(_rowsRaw);
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
        backgroundColor:
            isCurrent ? scheme.primary.withValues(alpha: 0.10) : null,
        side: isCurrent && !selected
            ? BorderSide(color: scheme.primary, width: 1.4)
            : null,
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimary : scheme.onSurface,
          fontWeight: selected || isCurrent ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<int>(
                  initialValue: _availableYears.contains(_filterYear)
                      ? _filterYear
                      : _availableYears.first,
                  items: _availableYears
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text('$y'),
                        ),
                      )
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
        ],
      ),
    );
  }

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  String _dataInserimentoLabel(Map<String, dynamic> r) {
    final s = formatDateTimeItFromSupabase(r['created_at']);
    return s.isEmpty ? '—' : s;
  }

  String _kmOreLabel(Map<String, dynamic> r) {
    final raw = (r['km_ore'] ?? '').toString().trim();
    return raw.isEmpty ? '—' : raw;
  }

  String _kmOreInseritoLabel(Map<String, dynamic> r) {
    if (!MezziKmService.rccRowHasKmOre(r)) return '—';
    final dt = MezziKmService.kmOreInsertedAtFromRccRow(r);
    return dt == null ? '—' : formatDateDdMmYyyyFromDate(dt);
  }

  String _compilatoreLabel(Map<String, dynamic> r) {
    final u = (r['user_uuid'] ?? '').toString().trim();
    if (u.isEmpty) return '—';
    return _utentiByUuid[u] ?? u;
  }

  String _dtLabel(Map<String, dynamic> r) {
    final dt = (r['dt_user_uuid'] ?? '').toString().trim();
    if (dt.isNotEmpty) {
      final name = _utentiByUuid[dt];
      if (name != null && name.isNotEmpty) return name;
    }
    final legacy = (r['nome_cognome'] ?? '').toString().trim();
    return legacy.isEmpty ? '—' : legacy;
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
        title: Text('Rifornimento ${formatDateDdMmYyyy(r['data_rifornimento'])}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailLine('Compilatore', _compilatoreLabel(r)),
              _detailLine('DT', _dtLabel(r)),
              _detailLine('Multicard', (r['n_carta_carburante'] ?? '').toString()),
              _detailLine('Mezzo', _mezzoLabelFromRow(r)),
              _detailLine('Litri', (r['litri'] ?? '').toString()),
              _detailLine('Euro', (r['euro'] ?? '').toString()),
              _detailLine('Tipo carburante', (r['tipo_carburante'] ?? '').toString()),
              _detailLine('Cantiere', (r['cantiere'] ?? '').toString()),
              _detailLine('Nota', (r['note'] ?? '').toString()),
              _detailLine('Data inserimento', _dataInserimentoLabel(r)),
              _detailLine('KM / ore', _kmOreLabel(r)),
              if (_kmOreInseritoLabel(r) != '—')
                _detailLine('Data ins. km', _kmOreInseritoLabel(r)),
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

  String _mezzoLabelFromRow(Map<String, dynamic> r) {
    final parts = [
      (r['automezzo_mdo'] ?? '').toString().trim(),
      (r['targa_matricola'] ?? '').toString().trim(),
    ].where((x) => x.isNotEmpty);
    final joined = parts.join(' · ');
    return joined.isEmpty ? '—' : joined;
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    if (row == null) {
      if (!_canInsert) return;
    } else if (!_canEditRow(row)) {
      await _showReadOnlyDetail(row);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RccFormDialog(
        supa: _supa,
        dipendenteMode: widget.dipendenteMode,
        myUserUuid: _myUserUuid,
        myDisplayName: _myDisplayName,
        myNameNorm: _myNameNorm,
        lockDtUuid: _isDtView ? _myUserUuid : null,
        // Assistente: in giustificazione può scegliere qualsiasi DT;
        // in elenco vede solo i DT che lo hanno autorizzato.
        allowedDtUuids: const <String>[],
        initialDtUuid:
            _isAssistenteDtView ? _selectedAssistenteDtUuid : null,
        // Admin / logistica / DT: mezzo e carta anche se assegnati ad altri (es. SEDE).
        allowUnboundMulticard: !widget.dipendenteMode,
        existing: row,
      ),
    );
    if (ok == true) {
      await _loadRows();
      if (mounted) {
        ModifyFeedback.success(context, row == null ? 'Riga inserita.' : 'Riga aggiornata.');
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (!_canDelete) return;
    if (!await ensureCanPersist(context)) return;
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina riga'),
        content: const Text(
          'Eliminare questo rifornimento dal registro?',
        ),
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
      await _supa.from('logistica_rcc_carburante').delete().eq('id_uuid', id);
      await _loadRows();
      if (mounted) ModifyFeedback.success(context, 'Riga eliminata.');
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
        .from('logistica_rcc_carburante')
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

  Future<({List<_RccExportCompiler> compilers, List<String> schede})> _exportFilterOptions(
    int year,
    int month,
  ) async {
    final rows = await _fetchRowsForExportMonth(year, month);
    final byUuid = <String, String>{};
    final schedeSet = <String>{};
    for (final r in rows) {
      final card = (r['n_carta_carburante'] ?? '').toString().trim();
      if (card.isNotEmpty) schedeSet.add(card);
      final uid = (r['user_uuid'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      byUuid.putIfAbsent(uid, () => _compilatoreLabel(r));
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
        .map((e) => _RccExportCompiler(uuid: e.key, label: e.value.isEmpty ? e.key : e.value))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final schede = schedeSet.toList()..sort();
    return (compilers: compilers, schede: schede);
  }

  Future<(int year, int month, String? compilatoreUuid, String? scheda)?> _pickRccExportFilters() async {
    final now = DateTime.now();
    var selYear = now.year;
    var selMonth = now.month;
    String? selCompilatoreUuid;
    String? selScheda;
    var optionsLoading = true;
    List<_RccExportCompiler> compilers = <_RccExportCompiler>[];
    List<String> schede = <String>[];
    List<Map<String, dynamic>> monthRows = <Map<String, dynamic>>[];

    List<String> schedeFromRows(List<Map<String, dynamic>> rows) {
      final s = <String>{};
      for (final r in rows) {
        final card = (r['n_carta_carburante'] ?? '').toString().trim();
        if (card.isNotEmpty) s.add(card);
      }
      return s.toList()..sort();
    }

    void applySchedaSelection(StateSetter setSt) {
      if (selScheda != null && !schede.contains(selScheda)) selScheda = null;
      if (schede.length == 1) selScheda = schede.first;
    }

    Future<void> reload(StateSetter setSt) async {
      setSt(() => optionsLoading = true);
      monthRows = await _fetchRowsForExportMonth(selYear, selMonth);
      final opt = await _exportFilterOptions(selYear, selMonth);
      if (!mounted) return;
      setSt(() {
        optionsLoading = false;
        compilers = opt.compilers;
        schede = schedeFromRows(monthRows);
        if (selCompilatoreUuid != null &&
            !compilers.any((c) => c.uuid == selCompilatoreUuid)) {
          selCompilatoreUuid = null;
        }
        applySchedaSelection(setSt);
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
        schede = schedeFromRows(rows);
        applySchedaSelection(setSt);
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
          final showSchedaPicker = schede.length > 1;
          return AlertDialog(
            title: const Text('Export Mod.RCC'),
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
                    if (showSchedaPicker) ...[
                      const SizedBox(height: 12),
                      DropdownSearch<String?>(
                        selectedItem: selScheda,
                        items: [null, ...schede],
                        itemAsString: (s) =>
                            (s ?? '').trim().isEmpty ? 'Tutte le schede carburante' : s!,
                        compareFn: (a, b) => (a ?? '') == (b ?? ''),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'N° scheda carburante',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        popupProps: const PopupProps.menu(showSearchBox: true, fit: FlexFit.loose),
                        onChanged: (v) => setSt(() => selScheda = v),
                      ),
                    ] else if (schede.length == 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Scheda: ${schede.first}',
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
                    : () => Navigator.pop(ctx, (selYear, selMonth, selCompilatoreUuid, selScheda)),
                child: const Text('Esporta'),
              ),
            ],
          );
        },
      ),
    );
    return result;
  }

  Future<void> _exportModRcc() async {
    if (widget.dipendenteMode) return;
    final picked = await _pickRccExportFilters();
    if (picked == null || !mounted) return;
    final (y, m, compilatoreUuid, scheda) = picked;
    try {
      var list = await _fetchRowsForExportMonth(y, m);
      if ((compilatoreUuid ?? '').trim().isNotEmpty) {
        list = list
            .where((r) => (r['user_uuid'] ?? '').toString().trim() == compilatoreUuid!.trim())
            .toList(growable: false);
      }
      if ((scheda ?? '').trim().isNotEmpty) {
        list = list
            .where((r) => (r['n_carta_carburante'] ?? '').toString().trim() == scheda!.trim())
            .toList(growable: false);
      }
      if (list.isEmpty) {
        ModifyFeedback.hint(context, 'Nessun rifornimento per i filtri selezionati.');
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

      final bytes = await buildRccMod04ExcelBytes(
        year: y,
        month: m,
        rows: list,
        userNamesByUuid: userMap,
      );
      final schedaSuffix = (scheda ?? '').trim().isEmpty
          ? ''
          : '_${scheda!.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
      final diag = lastRccMod04ExportInfo;
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Mod_RCC_${y}_${m.toString().padLeft(2, '0')}$schedaSuffix',
        bytes: bytes,
        openFile: true,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      final mediaNote = diag != null
          ? '\nLogo/certificazioni: ${diag.embeddedMediaCount} immagini (Python: ${diag.pythonExecutable}).'
          : '';
      ModifyFeedback.success(
        context,
        p.isEmpty
            ? 'Export Mod.RCC completato.$mediaNote\nScorri in basso nel foglio (riga 36+) per FIRMA D.T. e certificazioni.'
            : 'Export Mod.RCC completato.$mediaNote\n$p\nScorri in basso (riga 36+) per firma e logo.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore export: $e');
    }
  }

  bool _useNarrowLayout(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  @override
  Widget build(BuildContext context) {
    final title = widget.dipendenteMode
        ? 'Registro carburante (RCC)'
        : (_isDtView
            ? 'Registro carburante'
            : (_isAssistenteDtView
                ? 'Registro carburante (Assistente DT)'
                : 'Registro carburante Mod.RCC'));

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
              tooltip: 'Export Mod.RCC',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: _loading ? null : _exportModRcc,
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
                    child: isLogisticaCompactLayout(context)
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
                                  initialValue: (_selectedAssistenteDtUuid ?? '').trim().isEmpty
                                      ? null
                                      : _selectedAssistenteDtUuid,
                                  items: _assistenteAllowedDtUuids
                                      .map(
                                        (id) => DropdownMenuItem(
                                          value: id,
                                          child: Text(
                                            _assistenteDtLabelsByUuid[id] ?? id,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) async {
                                    setState(() => _selectedAssistenteDtUuid = v);
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
                                    initialValue: (_selectedAssistenteDtUuid ?? '').trim().isEmpty
                                        ? null
                                        : _selectedAssistenteDtUuid,
                                    items: _assistenteAllowedDtUuids
                                        .map(
                                          (id) => DropdownMenuItem(
                                            value: id,
                                            child: Text(
                                              _assistenteDtLabelsByUuid[id] ?? id,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) async {
                                      setState(() => _selectedAssistenteDtUuid = v);
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
                  _buildMonthYearFilters(),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isAssistenteDtView && _assistenteAllowedDtUuids.isEmpty
                ? 'Nessun DT autorizzato.\nChiedi al DT di abilitarti in «Permessi Assistenti DT».'
                : (_canInsert
                    ? 'Nessun rifornimento. Tocca + per aggiungerne uno.'
                    : 'Nessun rifornimento registrato.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
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
              : ValueKey<String>('rcc_mobile_$id'),
          child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: flash ? Colors.amber : Colors.transparent,
              width: flash ? 3 : 0,
            ),
          ),
          child: InkWell(
            onTap: () =>
                _canEditRow(r) ? _openForm(row: r) : _showReadOnlyDetail(r),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fmtDate(r['data_rifornimento']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_canDelete)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(r),
                          tooltip: 'Elimina',
                        )
                      else if (!_canEditRow(r))
                        const Icon(Icons.visibility_outlined, color: Colors.grey),
                    ],
                  ),
                  if (_isAdminView)
                    Text(
                      'Compilatore: ${_compilatoreLabel(r)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Litri: ${r['litri'] ?? '—'}  ·  Euro: ${r['euro'] ?? '—'}',
                  ),
                  Text('KM / ore: ${_kmOreLabel(r)}'),
                  if (_kmOreInseritoLabel(r) != '—')
                    Text('Data ins. km: ${_kmOreInseritoLabel(r)}'),
                  Text('Data inserimento: ${_dataInserimentoLabel(r)}'),
                  Text('Cantiere: ${(r['cantiere'] ?? '').toString().trim().isEmpty ? '—' : r['cantiere']}'),
                  if ((r['note'] ?? '').toString().trim().isNotEmpty)
                    Text('Nota: ${r['note']}'),
                  Text('DT: ${_dtLabel(r)}'),
                  Text('Carta: ${(r['n_carta_carburante'] ?? '').toString().trim().isEmpty ? '—' : r['n_carta_carburante']}'),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildDesktopTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      child: DataTable2(
        minWidth: _isAdminView ? 1520 : 1320,
        horizontalScrollController: ScrollController(),
        columns: [
          const DataColumn2(label: Text('Data'), size: ColumnSize.S),
          const DataColumn2(label: Text('Data inserimento'), size: ColumnSize.S),
          const DataColumn2(label: Text('Carta'), size: ColumnSize.S),
          const DataColumn2(label: Text('KM / ore'), size: ColumnSize.S),
          const DataColumn2(label: Text('Data ins. km'), size: ColumnSize.S),
          const DataColumn2(label: Text('Litri'), size: ColumnSize.S),
          const DataColumn2(label: Text('Euro'), size: ColumnSize.S),
          const DataColumn2(label: Text('Cantiere'), size: ColumnSize.M),
          const DataColumn2(label: Text('Nota'), size: ColumnSize.M),
          const DataColumn2(label: Text('DT'), size: ColumnSize.M),
          if (_isAdminView)
            const DataColumn2(
              label: Text('Compilatore'),
              size: ColumnSize.M,
            ),
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
            onTap: () =>
                _canEditRow(r) ? _openForm(row: r) : _showReadOnlyDetail(r),
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
              _hoverCell(Text(_kmOreLabel(r)), r, 'km_ore'),
              _hoverCell(Text(_kmOreInseritoLabel(r)), r, 'km_ore'),
              _hoverCell(Text((r['litri'] ?? '').toString()), r, 'litri'),
              _hoverCell(Text((r['euro'] ?? '').toString()), r, 'euro'),
              _hoverCell(Text((r['cantiere'] ?? '').toString()), r, 'cantiere'),
              _hoverCell(
                Text(
                  (r['note'] ?? '').toString().trim().isEmpty
                      ? '—'
                      : (r['note'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                r,
                'note',
              ),
              _hoverCell(Text(_dtLabel(r)), r, 'dt_user_uuid'),
              if (_isAdminView)
                _hoverCell(Text(_compilatoreLabel(r)), r, 'created_by_user_uuid'),
              DataCell(
                _canDelete
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmDelete(r),
                        tooltip: 'Elimina',
                      )
                    : (!_canEditRow(r)
                        ? const Icon(Icons.visibility_outlined, size: 20, color: Colors.grey)
                        : const SizedBox.shrink()),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

const _tipiCarburanteRcc = ['Gasolio', 'HVO', 'Benzina', 'AdBlue'];

class _UserPick {
  final String uuid;
  final String label;
  const _UserPick({required this.uuid, required this.label});
}

class _RccFormDialog extends StatefulWidget {
  final SupabaseClient supa;
  final bool dipendenteMode;
  final String myUserUuid;
  final String myDisplayName;
  final String myNameNorm;
  final String? lockDtUuid;
  final List<String> allowedDtUuids;
  final String? initialDtUuid;
  /// Admin/logistica/DT: carta e mezzo anche se non assegnati al compilatore.
  final bool allowUnboundMulticard;
  final Map<String, dynamic>? existing;

  const _RccFormDialog({
    required this.supa,
    required this.dipendenteMode,
    required this.myUserUuid,
    required this.myDisplayName,
    required this.myNameNorm,
    this.lockDtUuid,
    this.allowedDtUuids = const <String>[],
    this.initialDtUuid,
    this.allowUnboundMulticard = false,
    this.existing,
  });

  @override
  State<_RccFormDialog> createState() => _RccFormDialogState();
}

class _RccFormDialogState extends State<_RccFormDialog> {
  final _dataCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _litriCtrl = TextEditingController();
  final _euroCtrl = TextEditingController();
  final _schedaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  bool _loadingRefs = true;
  String? _selUserUuid;
  String? _selDtUuid;
  String? _selMezzoId;
  final List<_UserPick> _userPicks = <_UserPick>[];
  String? _selTipoCarburante;
  String? _selCommessaUuid;
  final Map<String, Map<String, dynamic>> _mezzoById = <String, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> _mezzi = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _multicards = <Map<String, dynamic>>[];
  List<QtMulticardAssigneeProfile> _mezzoProfiles =
      const <QtMulticardAssigneeProfile>[];
  final Map<String, String> _commesseByUuid = <String, String>{};
  final Map<String, String> _dtLabelsByUuid = <String, String>{};
  String? _suggestedCommessaUuid;
  bool _loadingSuggestion = false;
  bool _suggestionDismissed = false;
  String? _suggestionDismissedForIso;
  bool _importingRicevuta = false;

  bool get _cartaLibera => widget.allowUnboundMulticard;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _dataCtrl.text = formatDateDdMmYyyy(ex['data_rifornimento']);
      _kmCtrl.text = (ex['km_ore'] ?? '').toString();
      _litriCtrl.text = _numToIt(ex['litri']);
      _euroCtrl.text = _numToIt(ex['euro']);
      final tipo = (ex['tipo_carburante'] ?? '').toString().trim();
      if (tipo.isNotEmpty && _tipiCarburanteRcc.contains(tipo)) {
        _selTipoCarburante = tipo;
      }
      _selUserUuid = (ex['user_uuid'] ?? '').toString().trim();
      if (_selUserUuid != null && _selUserUuid!.isEmpty) _selUserUuid = null;
      _selDtUuid = (ex['dt_user_uuid'] ?? '').toString().trim();
      final exMezzo = (ex['mezzo_stradale_id_uuid'] ?? '').toString().trim();
      if (exMezzo.isNotEmpty) _selMezzoId = exMezzo;
      _schedaCtrl.text = (ex['n_carta_carburante'] ?? '').toString().trim();
      final exComm = (ex['commessa_uuid'] ?? '').toString().trim();
      if (exComm.isNotEmpty) {
        _selCommessaUuid = exComm;
      }
      _noteCtrl.text = (ex['note'] ?? '').toString();
    } else {
      _dataCtrl.text = formatDateDdMmYyyyFromDate(DateTime.now());
      final lockedDt = (widget.lockDtUuid ?? '').trim();
      if (lockedDt.isNotEmpty) {
        _selDtUuid = lockedDt;
      } else {
        final initial = (widget.initialDtUuid ?? '').trim();
        if (initial.isNotEmpty) _selDtUuid = initial;
      }
    }
    if (!_isEdit) {
      unawaited(RccRicevutaOcrPlatform.warmup());
    }
    unawaited(_loadRefs());
  }

  String _numToIt(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      if (v is int) return v.toString();
      return v.toString().replaceAll('.', ',');
    }
    return v.toString();
  }

  @override
  void dispose() {
    _dataCtrl.dispose();
    _kmCtrl.dispose();
    _litriCtrl.dispose();
    _euroCtrl.dispose();
    _schedaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _syncSchedaFromMezzo() {
    final id = (_selMezzoId ?? '').trim();
    if (id.isEmpty) {
      _schedaCtrl.text = '';
      return;
    }
    _schedaCtrl.text = _schedaForMezzo(id) ?? '';
  }

  String? _schedaForMezzo(String mezzoId) {
    final m = _mezzoById[mezzoId];
    if (m == null) return null;
    final targa = (m['targa'] ?? '').toString().trim().toLowerCase();
    if (targa.isNotEmpty) {
      for (final c in _multicards) {
        if ((c['mezzo_targa'] ?? '').toString().trim().toLowerCase() == targa) {
          final n = (c['multicard'] ?? '').toString().trim();
          if (n.isNotEmpty) {
            final digits = n.replaceAll(RegExp(r'\D'), '');
            return digits.length >= 12 ? digits : n;
          }
        }
      }
    }
    final onMezzo = (m['multicard'] ?? '').toString().trim();
    if (onMezzo.isEmpty) return null;
    final digits = onMezzo.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 12 ? digits : onMezzo;
  }

  static const String _kNessunaCarta = '__none__';

  List<String> _multicardNumbers() {
    final out = <String>{};
    for (final c in _multicards) {
      final n = (c['multicard'] ?? '').toString().trim();
      if (n.isEmpty) continue;
      final digits = n.replaceAll(RegExp(r'\D'), '');
      out.add(digits.length >= 12 ? digits : n);
    }
    final current = _schedaCtrl.text.trim();
    if (current.isNotEmpty) out.add(current);
    final list = out.toList()..sort();
    return list;
  }

  String _multicardDropdownLabel(String value) {
    if (value == _kNessunaCarta || value.trim().isEmpty) {
      return 'Nessuna';
    }
    for (final c in _multicards) {
      final n = (c['multicard'] ?? '').toString().trim();
      if (n.isEmpty || !_carteMatch(value, n)) continue;
      final targa = (c['mezzo_targa'] ?? '').toString().trim();
      final who = (c['assegnatario_attuale'] ?? '').toString().trim();
      final bind = targa.isEmpty ? 'non abbinata' : targa;
      if (who.isNotEmpty) return '$value · $bind · $who';
      return '$value · $bind';
    }
    return value;
  }

  String _selectedCartaKey() {
    final t = _schedaCtrl.text.trim();
    if (t.isEmpty) return _kNessunaCarta;
    return t;
  }

  Future<void> _loadRefs() async {
    try {
      final mezziRes = await widget.supa
          .from('logistica_mezzi_stradali')
          .select(
            'id_uuid,targa,marca,modello,tipologia_mezzo,assegnatario_user_uuid,assegnatario_attuale,multicard,active',
          )
          .eq('active', true)
          .order('targa', ascending: true);
      _mezzi
        ..clear()
        ..addAll(
          List<Map<String, dynamic>>.from(
            (mezziRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
        );
      _mezzoById
        ..clear()
        ..addEntries(
          _mezzi
              .where((m) => (m['id_uuid'] ?? '').toString().trim().isNotEmpty)
              .map((m) => MapEntry((m['id_uuid'] ?? '').toString().trim(), m)),
        );

      final cardRes = await widget.supa
          .from('logistica_multicard')
          .select('multicard,mezzo_targa,assegnatario_attuale')
          .order('mezzo_targa', ascending: true);
      _multicards
        ..clear()
        ..addAll(
          List<Map<String, dynamic>>.from(
            (cardRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
        );
      _mezzoProfiles = await MezzoStoricoAssigneeLoader.load(widget.supa);

      final commRes =
          await widget.supa.from('commesse').select('id_uuid,nome').order('nome', ascending: true);
      for (final e in (commRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        _commesseByUuid[id] =
            (m['nome'] ?? '').toString().trim().isEmpty ? id : (m['nome'] ?? '').toString().trim();
      }

      if (!widget.dipendenteMode) {
        final usersRes = await widget.supa
            .from('users')
            .select('id_uuid,full_name,username')
            .order('full_name', ascending: true)
            .limit(2500);
        _userPicks.clear();
        for (final e in (usersRes as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          _userPicks.add(
            _UserPick(
              uuid: id,
              label: full.isNotEmpty ? full : (user.isNotEmpty ? user : id),
            ),
          );
        }
      }

      final allowed = widget.allowedDtUuids
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (allowed.isEmpty) {
        _dtLabelsByUuid.addAll(await loadDtOptionsByUuid());
      } else {
        final dtRes = await widget.supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', allowed.toList());
        for (final e in (dtRes as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          _dtLabelsByUuid[id] = full.isNotEmpty ? full : (user.isNotEmpty ? user : id);
        }
      }

      final ex = widget.existing;
      if (ex != null) {
        final exMezzo = (ex['mezzo_stradale_id_uuid'] ?? '').toString().trim();
        if (exMezzo.isNotEmpty) {
          _selMezzoId = exMezzo;
        } else {
          final targa = (ex['targa_matricola'] ?? '').toString().trim().toLowerCase();
          if (targa.isNotEmpty) {
            for (final m in _mezzi) {
              if ((m['targa'] ?? '').toString().trim().toLowerCase() == targa) {
                _selMezzoId = (m['id_uuid'] ?? '').toString().trim();
                break;
              }
            }
          }
        }
        final exComm = (ex['commessa_uuid'] ?? '').toString().trim();
        if (exComm.isNotEmpty) {
          _selCommessaUuid = exComm;
        } else {
          final cantiere = (ex['cantiere'] ?? '').toString().trim();
          if (cantiere.isNotEmpty) {
            for (final e in _commesseByUuid.entries) {
              if (e.value == cantiere) {
                _selCommessaUuid = e.key;
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    final visible = _mezziVisible();
    if ((_selMezzoId == null || _selMezzoId!.isEmpty)) {
      if (_cartaLibera || visible.length == 1) {
        _autoSelectMezzoForOwner();
      }
    }
    if (_schedaCtrl.text.isEmpty ||
        _schedaCtrl.text.replaceAll(RegExp(r'\D'), '').length < 12) {
      _syncSchedaFromMezzo();
    }

    if (!mounted) return;
    final lockedDt = (widget.lockDtUuid ?? '').trim();
    if (lockedDt.isNotEmpty && _dtLabelsByUuid.containsKey(lockedDt)) {
      _selDtUuid = lockedDt;
    } else if ((_selDtUuid ?? '').trim().isEmpty && _dtLabelsByUuid.isNotEmpty) {
      final initial = (widget.initialDtUuid ?? '').trim();
      if (initial.isNotEmpty && _dtLabelsByUuid.containsKey(initial)) {
        _selDtUuid = initial;
      } else {
        _selDtUuid = _dtLabelsByUuid.keys.first;
      }
    } else if ((_selDtUuid ?? '').trim().isNotEmpty &&
        !_dtLabelsByUuid.containsKey(_selDtUuid)) {
      _selDtUuid = _dtLabelsByUuid.isEmpty ? null : _dtLabelsByUuid.keys.first;
    }
    setState(() => _loadingRefs = false);
    unawaited(_loadCommessaSuggestion());
  }

  Future<void> _loadCommessaSuggestion() async {
    final iso = _isoDate();
    final owner = _ownerUuid();
    if ((iso ?? '').isEmpty || owner.isEmpty) {
      if (!mounted) return;
      setState(() => _suggestedCommessaUuid = null);
      return;
    }
    if (_suggestionDismissedForIso != iso) {
      _suggestionDismissed = false;
      _suggestionDismissedForIso = iso;
    }
    setState(() => _loadingSuggestion = true);
    final sug = await suggestCommessaUuidFromPernottamento(
      supa: widget.supa,
      compilatoreUserUuid: owner,
      isoRefuelDate: iso!,
    );
    if (!mounted) return;
    setState(() {
      _loadingSuggestion = false;
      _suggestedCommessaUuid = sug;
    });
    await _maybeShowCommessaSuggestDialog();
  }

  Future<void> _maybeShowCommessaSuggestDialog() async {
    final sug = (_suggestedCommessaUuid ?? '').trim();
    if (sug.isEmpty || _suggestionDismissed) return;
    if (sug == (_selCommessaUuid ?? '').trim()) return;
    if ((_selCommessaUuid ?? '').trim().isNotEmpty) return;

    final label = _commesseByUuid[sug] ?? sug;
    final yes = await showPernottamentoCommessaSuggestDialog(
      context: context,
      dateLabel: _dataCtrl.text.trim(),
      commessaLabel: label,
    );
    if (!mounted) return;
    setState(() => _suggestionDismissed = true);
    if (yes == true && _commesseByUuid.containsKey(sug)) {
      setState(() => _selCommessaUuid = sug);
    }
  }

  void _onRefuelDateChanged() {
    setState(() {
      final visible = _mezziVisible();
      final sel = (_selMezzoId ?? '').trim();
      if (sel.isNotEmpty &&
          !visible.any((m) => (m['id_uuid'] ?? '').toString().trim() == sel)) {
        _selMezzoId = null;
        _schedaCtrl.text = '';
      }
    });
    unawaited(_loadCommessaSuggestion());
  }

  String _ownerUuid() =>
      widget.dipendenteMode ? widget.myUserUuid : (_selUserUuid ?? '').trim();

  String _ownerNameNorm() {
    if (widget.dipendenteMode) return widget.myNameNorm;
    return _normNameFromUser(_selUserUuid ?? '');
  }

  String _normNameFromUser(String userUuid) {
    final u = _userPicks.where((x) => x.uuid == userUuid).toList();
    if (u.isEmpty) return '';
    return MezziKmService.normalizePersonName(u.first.label);
  }

  String _compilatoreLabel(String uuid) {
    final u = _userPicks.where((x) => x.uuid == uuid).toList();
    return u.isEmpty ? uuid : u.first.label;
  }

  List<Map<String, dynamic>> _mezziForOwner() {
    final uuid = _ownerUuid();
    final norm = _ownerNameNorm();
    if (!widget.dipendenteMode && uuid.isEmpty && norm.isEmpty) {
      return const [];
    }
    final iso = _isoDate();
    final refuelDate = iso != null ? DateTime.tryParse(iso) : null;

    return _mezzi.where((m) {
      if (refuelDate != null && norm.isNotEmpty) {
        final targa = (m['targa'] ?? '').toString().trim();
        final profile = MezzoStoricoAssigneeLoader.findByTarga(
          targa,
          _mezzoProfiles,
        );
        if (LogisticaAssigneeAtDate.wasMezzoAssigneeAtDate(
          profile: profile,
          date: refuelDate,
          nameNorm: norm,
          userUuid: uuid,
          mezzoRow: m,
        )) {
          return true;
        }
      }
      return MezziKmService.isRowAssignedToCurrentUser(m, uuid, norm);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _mezziVisible() {
    // Admin/logistica/DT: qualsiasi mezzo (anche SEDE / altrui); la targa del
    // compilatore viene comunque precompilata con [_autoSelectMezzoForOwner].
    if (_cartaLibera) {
      return List<Map<String, dynamic>>.from(_mezzi);
    }
    return _mezziForOwner();
  }

  /// Seleziona il mezzo assegnato al compilatore (preferisce match su user uuid).
  void _autoSelectMezzoForOwner() {
    final assigned = _mezziForOwner();
    if (assigned.isEmpty) {
      _selMezzoId = null;
      _schedaCtrl.text = '';
      return;
    }
    final uuid = _ownerUuid();
    Map<String, dynamic> pick = assigned.first;
    if (uuid.isNotEmpty) {
      for (final m in assigned) {
        if ((m['assegnatario_user_uuid'] ?? '').toString().trim() == uuid) {
          pick = m;
          break;
        }
      }
    }
    _selMezzoId = (pick['id_uuid'] ?? '').toString().trim();
    _syncSchedaFromMezzo();
  }

  String _mezzoLabel(String id) {
    final r = _mezzoById[id];
    if (r == null) return id;
    final t = (r['targa'] ?? '').toString().trim();
    final m = [(r['marca'] ?? '').toString().trim(), (r['modello'] ?? '').toString().trim()]
        .where((x) => x.isNotEmpty)
        .join(' ');
    final ass = (r['assegnatario_attuale'] ?? '').toString().trim();
    final base = t.isNotEmpty ? (m.isNotEmpty ? '$t · $m' : t) : m;
    if (!_cartaLibera || ass.isEmpty) return base;
    return base.isEmpty ? ass : '$base · $ass';
  }

  String? _isoDate() => parseFlexibleDateToIsoDate(_dataCtrl.text.trim());

  double? _dec(String raw) {
    var t = raw.trim().replaceAll(' ', '');
    if (t.isEmpty) return null;
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  Future<void> _importFromRicevuta() async {
    if (_loadingRefs || _importingRicevuta || _isEdit) return;
    setState(() => _importingRicevuta = true);
    try {
      final parsed = await RccRicevutaImportService.importInteractive(context);
      if (!mounted || parsed == null) return;
      _applyParsedRicevuta(parsed);
      setState(() {});
      _onRefuelDateChanged();
      ModifyFeedback.success(
        context,
        'Campi compilati dalla ricevuta. Completa DT e commessa.',
      );
    } finally {
      if (mounted) setState(() => _importingRicevuta = false);
    }
  }

  void _applyParsedRicevuta(RccRicevutaParsed parsed) {
    if ((parsed.dataGgMmAaaa ?? '').isNotEmpty) {
      _dataCtrl.text = parsed.dataGgMmAaaa!.trim();
    }
    if ((parsed.km ?? '').isNotEmpty) {
      _kmCtrl.text = parsed.km!.trim();
    }
    if ((parsed.litri ?? '').isNotEmpty) {
      _litriCtrl.text = parsed.litri!.trim();
    }
    if ((parsed.euro ?? '').isNotEmpty) {
      _euroCtrl.text = parsed.euro!.trim();
    }
    final tipo = (parsed.tipoCarburante ?? '').trim();
    if (tipo.isNotEmpty && _tipiCarburanteRcc.contains(tipo)) {
      _selTipoCarburante = tipo;
    }
    final carta = (parsed.numeroCarta ?? '').trim();
    if (carta.isNotEmpty) {
      _applyMezzoFromCarta(carta);
    }
  }

  bool _carteMatch(String a, String b) {
    return RccRicevutaCarburanteParser.carteCompatibili(a, b);
  }

  void _applyMezzoFromCarta(String carta) {
    final digits = carta.replaceAll(RegExp(r'\D'), '');
    final masked = RccRicevutaCarburanteParser.isCartaMascherata(carta);
    if (!masked && digits.length < 12) return;
    for (final c in _multicards) {
      final mc = (c['multicard'] ?? '').toString().trim();
      if (!_carteMatch(carta, mc)) continue;
      final targa = (c['mezzo_targa'] ?? '').toString().trim().toLowerCase();
      if (targa.isEmpty) break;
      for (final m in _mezzi) {
        if ((m['targa'] ?? '').toString().trim().toLowerCase() != targa) {
          continue;
        }
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        if (!widget.dipendenteMode) {
          final uid = (m['assegnatario_user_uuid'] ?? '').toString().trim();
          if (uid.isNotEmpty && _userPicks.any((u) => u.uuid == uid)) {
            _selUserUuid = uid;
          }
        }
        final visible = _mezziVisible();
        if (_cartaLibera ||
            visible.any((x) => (x['id_uuid'] ?? '').toString().trim() == id)) {
          _selMezzoId = id;
          _syncSchedaFromMezzo();
          if (_schedaCtrl.text.trim().isEmpty) {
            _schedaCtrl.text = mc;
          }
          return;
        }
      }
      break;
    }
    _schedaCtrl.text = carta;
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_isoDate() ?? '') ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('it', 'IT'),
    );
    if (d != null) {
      setState(() => _dataCtrl.text = formatDateDdMmYyyyFromDate(d));
      _onRefuelDateChanged();
    }
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final iso = _isoDate();
    if ((iso ?? '').isEmpty) {
      ModifyFeedback.error(context, 'Indicare una data valida (gg/mm/aaaa).');
      return;
    }
    final owner = _ownerUuid();
    if (owner.isEmpty) {
      ModifyFeedback.error(
        context,
        widget.dipendenteMode
            ? 'Utente non identificato.'
            : 'Selezionare il compilatore (assegnatario del mezzo).',
      );
      return;
    }
    final dt = (_selDtUuid ?? '').trim();
    if (dt.isEmpty || !_dtLabelsByUuid.containsKey(dt)) {
      ModifyFeedback.error(context, 'Selezionare il DT (direttore tecnico).');
      return;
    }
    final allowedDt = widget.allowedDtUuids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (allowedDt.isNotEmpty && !allowedDt.contains(dt)) {
      ModifyFeedback.error(context, 'DT non autorizzato per questo assistente.');
      return;
    }
    final mezzoId = (_selMezzoId ?? '').trim();
    if (mezzoId.isEmpty || !_mezzoById.containsKey(mezzoId)) {
      ModifyFeedback.error(context, 'Selezionare il mezzo.');
      return;
    }
    if (!_cartaLibera) {
      final mezziOk = _mezziVisible();
      if (!mezziOk.any((m) => (m['id_uuid'] ?? '').toString().trim() == mezzoId)) {
        ModifyFeedback.error(
          context,
          'Il mezzo non è assegnato al compilatore per la data del rifornimento.',
        );
        return;
      }
    }
    final scheda = _schedaCtrl.text.trim();
    if (!_cartaLibera && scheda.isEmpty) {
      ModifyFeedback.error(
        context,
        'Nessuna scheda carburante abbinata alla targa del mezzo selezionato.',
      );
      return;
    }
    final commessaUuid = (_selCommessaUuid ?? '').trim();
    if (commessaUuid.isEmpty || !_commesseByUuid.containsKey(commessaUuid)) {
      ModifyFeedback.error(context, 'Selezionare il cantiere.');
      return;
    }
    final tipo = (_selTipoCarburante ?? '').trim();
    if (tipo.isEmpty) {
      ModifyFeedback.error(context, 'Selezionare il tipo carburante.');
      return;
    }

    final blocked = await CarburanteEuroLitroGuard.confirmBlockIfNeeded(
      context: context,
      tipoCarburante: tipo,
      litri: _dec(_litriCtrl.text),
      euro: _dec(_euroCtrl.text),
    );
    if (blocked) return;

    final m = _mezzoById[mezzoId]!;
    final automezzo = [
      (m['tipologia_mezzo'] ?? '').toString(),
      (m['marca'] ?? '').toString(),
      (m['modello'] ?? '').toString(),
    ].map((x) => x.trim()).where((x) => x.isNotEmpty).join(' ');

    final compName = widget.dipendenteMode
        ? widget.myDisplayName
        : _compilatoreLabel(owner);

    final payload = <String, dynamic>{
      'user_uuid': owner,
      'dt_user_uuid': dt,
      'mezzo_stradale_id_uuid': mezzoId,
      'data_rifornimento': iso,
      'n_carta_carburante': scheda,
      'km_ore': _nullIfEmpty(_kmCtrl.text),
      'litri': _dec(_litriCtrl.text),
      'euro': _dec(_euroCtrl.text),
      'tipo_carburante': tipo,
      'cantiere': _commesseByUuid[commessaUuid],
      'commessa_uuid': commessaUuid,
      'note': _nullIfEmpty(_noteCtrl.text),
      'nome_cognome': compName,
      'automezzo_mdo': automezzo.isEmpty ? null : automezzo,
      'targa_matricola': (m['targa'] ?? '').toString().trim(),
      'firma_compilatore': null,
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.supa
            .from('logistica_rcc_carburante')
            .update(payload)
            .eq('id_uuid', widget.existing!['id_uuid']);
      } else {
        await widget.supa.from('logistica_rcc_carburante').insert(payload);
      }
      try {
        await MezziKmService.syncLatestKmFromRccForMezzo(mezzoId);
      } catch (_) {
        // Il rifornimento è già salvato: non bloccare per sync km.
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Salvataggio fallito: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final mezzoIds = _mezziVisible()
        .map((m) => (m['id_uuid'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
    final dtIds = _dtLabelsByUuid.keys.toList()
      ..sort((a, b) => (_dtLabelsByUuid[a] ?? '').compareTo(_dtLabelsByUuid[b] ?? ''));
    final compilatoreIds = _userPicks.map((u) => u.uuid).toList();

    return AlertDialog(
      title: Text(_isEdit ? 'Modifica rifornimento' : 'Nuovo rifornimento'),
      content: SizedBox(
        width: 460,
        child: _loadingRefs
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isEdit) ...[
                      OutlinedButton.icon(
                        onPressed: _loadingRefs || _importingRicevuta
                            ? null
                            : _importFromRicevuta,
                        icon: _importingRicevuta
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.document_scanner_outlined),
                        label: const Text('Compila da screenshot o scontrino'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          'Legge data, carta, litri, euro, KM e tipo carburante '
                          'dallo screenshot dell’app o dalla foto dello scontrino '
                          '(anche se la Multicard è parzialmente coperta). '
                          'Compilatore, DT e commessa li inserisci tu.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    if (!widget.dipendenteMode) ...[
                      DropdownSearch<String>(
                        items: compilatoreIds,
                        selectedItem: compilatoreIds.contains(_selUserUuid)
                            ? _selUserUuid
                            : null,
                        itemAsString: (id) => _compilatoreLabel(id),
                        popupProps: const PopupProps.menu(
                          showSearchBox: true,
                          fit: FlexFit.loose,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Cerca compilatore…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'Compilatore',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        onChanged: (v) {
                          setState(() {
                            _selUserUuid = v;
                            _schedaCtrl.text = '';
                            _autoSelectMezzoForOwner();
                          });
                          unawaited(_loadCommessaSuggestion());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: dtIds.contains(_selDtUuid) ? _selDtUuid : null,
                      items: dtIds
                          .map(
                            (id) => DropdownMenuItem(
                              value: id,
                              child: Text(_dtLabelsByUuid[id] ?? id),
                            ),
                          )
                          .toList(),
                      onChanged: (widget.lockDtUuid ?? '').trim().isNotEmpty
                          ? null
                          : (v) => setState(() => _selDtUuid = v),
                      decoration: const InputDecoration(
                        labelText: 'DT (direttore tecnico)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownSearch<String>(
                      items: mezzoIds,
                      selectedItem:
                          mezzoIds.contains(_selMezzoId) ? _selMezzoId : null,
                      itemAsString: (id) => _mezzoLabel(id),
                      enabled: mezzoIds.isNotEmpty,
                      popupProps: const PopupProps.menu(
                        showSearchBox: true,
                        fit: FlexFit.loose,
                        searchFieldProps: TextFieldProps(
                          decoration: InputDecoration(
                            hintText: 'Cerca targa o mezzo…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          labelText: 'Mezzo (da Mezzi stradali)',
                          hintText: !widget.dipendenteMode &&
                                  !_cartaLibera &&
                                  (_selUserUuid ?? '').isEmpty
                              ? 'Seleziona prima il compilatore'
                              : (mezzoIds.isEmpty
                                  ? 'Nessun mezzo assegnato'
                                  : 'Seleziona…'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      onChanged: mezzoIds.isEmpty
                          ? null
                          : (v) => setState(() {
                                _selMezzoId = v;
                                _syncSchedaFromMezzo();
                              }),
                    ),
                    const SizedBox(height: 12),
                    if (_cartaLibera) ...[
                      DropdownSearch<String>(
                        items: [_kNessunaCarta, ..._multicardNumbers()],
                        selectedItem: _selectedCartaKey(),
                        itemAsString: _multicardDropdownLabel,
                        popupProps: const PopupProps.menu(
                          showSearchBox: true,
                          fit: FlexFit.loose,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Cerca numero carta…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'N° scheda carburante (Multicard)',
                            helperText:
                                'Anche carta non tua o non abbinata, oppure Nessuna',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          _schedaCtrl.text =
                              (v == null || v == _kNessunaCarta) ? '' : v;
                        }),
                      ),
                    ] else
                      TextField(
                        controller: _schedaCtrl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'N° scheda carburante (per targa)',
                          hintText: (_selMezzoId ?? '').isEmpty
                              ? 'Seleziona prima il mezzo'
                              : 'Nessuna scheda abbinata',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dataCtrl,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        labelText: 'Data rifornimento',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _kmCtrl,
                      decoration: const InputDecoration(
                        labelText: 'KM / ore',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _litriCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Litri',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _euroCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Euro',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _tipiCarburanteRcc.contains(_selTipoCarburante)
                          ? _selTipoCarburante
                          : null,
                      items: _tipiCarburanteRcc
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _selTipoCarburante = v),
                      decoration: const InputDecoration(
                        labelText: 'Tipo carburante',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (_loadingSuggestion)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    CommessaUuidAutocompleteField(
                      commesseByUuid: _commesseByUuid,
                      selectedUuid: _selCommessaUuid,
                      onSelected: (v) => setState(() => _selCommessaUuid = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nota (opzionale)',
                        hintText: 'Es. scontrino illeggibile, rifornimento parziale…',
                        border: OutlineInputBorder(),
                        isDense: true,
                        alignLabelWithHint: true,
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
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}
