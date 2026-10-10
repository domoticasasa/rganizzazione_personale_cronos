import 'package:dropdown_search/dropdown_search.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/employee_programmazione_service.dart';
import '../services/assenza_rfp03_excel_export.dart';
import '../services/assenza_richiesta_pdf_export.dart';
import '../services/mdo_rifornimento_service.dart';
import '../services/notification_sender.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

const List<String> kTipiAssenza = <String>[
  'FERIE',
  'PERMESSO',
  'MALATTIA',
  'INFORTUNIO',
  'ALTRO',
];

const List<String> kTipiRichiestaWorkflow = <String>['FERIE', 'PERMESSO'];

const List<String> kMesiNomi = <String>[
  'Gennaio',
  'Febbraio',
  'Marzo',
  'Aprile',
  'Maggio',
  'Giugno',
  'Luglio',
  'Agosto',
  'Settembre',
  'Ottobre',
  'Novembre',
  'Dicembre',
];

const List<String> kTipiSegnalazioneAdmin = <String>[
  'FERIE',
  'PERMESSO',
  'MALATTIA',
  'INFORTUNIO',
  'ALTRO',
];

/// Modalità pagina assenze.
enum DipendenteAssenzePageMode {
  /// Dipendente: proprie richieste workflow.
  dipendente,
  /// Admin / DT: approvazione richieste ferie e permessi.
  richiesteWorkflow,
  /// Admin: registro segnalazioni (malattia, infortunio, …).
  registroSegnalazioni,
}

const String _stInviataDt = 'INVIATA_AL_DT';
const String _stApprovataDt = 'APPROVATA_DT';
const String _stRifiutataDt = 'RIFIUTATA_DT';
const String _stApprovataAdmin = 'APPROVATA_ADMIN';
const String _stRifiutataAdmin = 'RIFIUTATA_ADMIN';

String _s(dynamic v) => (v ?? '').toString().trim();

String labelTipoAssenza(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'FERIE':
      return 'Ferie';
    case 'PERMESSO':
      return 'Permesso';
    case 'MALATTIA':
      return 'Malattia';
    case 'INFORTUNIO':
      return 'Infortunio';
    case 'ALTRO':
      return 'Altro';
    default:
      return tipo;
  }
}

String _formatDbTime(dynamic v) {
  final raw = (v ?? '').toString().trim();
  if (raw.isEmpty) return '';
  final parts = raw.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  return raw;
}

/// Etichetta periodo per liste, notifiche ed export.
String formatAssenzaPeriodoDetail(Map<String, dynamic> r) {
  final dal = formatDateDdMmYyyy(r['data_dal']);
  final al = formatDateDdMmYyyy(r['data_al']);
  final tipo = _s(r['tipo_assenza']).toUpperCase();
  final sameDay = dal == al || tipo == 'PERMESSO';
  var line = sameDay ? dal : '$dal – $al';

  final oreRaw = r['ore_permesso'];
  double? ore;
  if (oreRaw is num) {
    ore = oreRaw.toDouble();
  } else {
    ore = double.tryParse(oreRaw?.toString() ?? '');
  }
  if (ore != null && ore > 0) {
    final oreLabel = ore == ore.roundToDouble()
        ? '${ore.toInt()}'
        : ore.toStringAsFixed(1);
    line += ' • $oreLabel h';
  }

  final oi = _formatDbTime(r['ora_inizio']);
  final of = _formatDbTime(r['ora_fine']);
  if (oi.isNotEmpty && of.isNotEmpty) {
    line += ' ($oi–$of)';
  } else if (oi.isNotEmpty) {
    line += ' (dalle $oi)';
  }
  return line;
}

String labelWorkflow(String status) {
  switch (status) {
    case _stInviataDt:
      return 'Inviata al DT';
    case _stApprovataDt:
      return 'In attesa approvazione admin';
    case _stRifiutataDt:
      return 'Rifiutata dal DT';
    case _stApprovataAdmin:
      return 'Approvata admin';
    case _stRifiutataAdmin:
      return 'Rifiutata admin';
    default:
      return status;
  }
}

Color colorWorkflow(String status) {
  switch (status) {
    case _stInviataDt:
      return Colors.blue.shade700;
    case _stApprovataDt:
      return Colors.indigo.shade700;
    case _stRifiutataDt:
    case _stRifiutataAdmin:
      return Colors.red.shade700;
    case _stApprovataAdmin:
      return Colors.green.shade700;
    default:
      return Colors.blueGrey.shade700;
  }
}

class DipendenteAssenzePage extends StatefulWidget {
  final DipendenteAssenzePageMode pageMode;
  /// Legacy: se true e [pageMode] è [DipendenteAssenzePageMode.dipendente], equivale a registro admin.
  final bool adminMode;
  final bool readOnly;
  final int? userId;
  final String? role;
  final String? fullName;

  const DipendenteAssenzePage({
    super.key,
    this.pageMode = DipendenteAssenzePageMode.dipendente,
    this.adminMode = false,
    this.readOnly = false,
    this.userId,
    this.role,
    this.fullName,
  });

  @override
  State<DipendenteAssenzePage> createState() => _DipendenteAssenzePageState();
}

class _DipendenteAssenzePageState extends State<DipendenteAssenzePage> {
  bool _loading = true;
  String _search = '';
  String? _tipoFilter;
  int? _meseFilter; // 1..12, null = tutti i mesi
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Set<String> _selectedUuids = <String>{};
  final Map<String, Map<String, dynamic>> _personaleById =
      <String, Map<String, dynamic>>{};
  final List<Map<String, String>> _personaleOptions = <Map<String, String>>[];
  final Map<String, String> _usersByUuid = <String, String>{};
  final List<Map<String, String>> _dtOptions = <Map<String, String>>[];

  String _myRole = '';
  String _mySecondaryRole = '';
  String _myUserUuid = '';
  String? _myPersonaleUuid;

  bool get _hasDtRole => hasDtWorkflowRole(_myRole, _mySecondaryRole);

  DipendenteAssenzePageMode get _mode {
    if (widget.pageMode != DipendenteAssenzePageMode.dipendente) {
      return widget.pageMode;
    }
    if (widget.adminMode && canManageDipendenteAssenze(_myRole)) {
      return DipendenteAssenzePageMode.registroSegnalazioni;
    }
    return DipendenteAssenzePageMode.dipendente;
  }

  bool get _isRichiesteMode =>
      _mode == DipendenteAssenzePageMode.richiesteWorkflow;
  bool get _isRegistroMode =>
      _mode == DipendenteAssenzePageMode.registroSegnalazioni;
  bool get _isDipendenteMode => _mode == DipendenteAssenzePageMode.dipendente;

  String get _roleForPerms =>
      _myRole.trim().isNotEmpty ? _myRole : (widget.role ?? '');

  /// Registro segnalazioni: DT/assistente solo consultazione (anche se manca [readOnly] dal caller).
  bool get _registroWriteBlocked {
    if (widget.readOnly) return true;
    if (!_isRegistroMode) return false;
    final r = normalizeRole(_roleForPerms);
    if (r == 'dt' || r == 'assistente_dt') return true;
    if (isAdminVistaRole(_roleForPerms)) return true;
    // Ruolo secondario DT senza permessi admin: sola lettura sul registro.
    if (_hasDtRole && !canMutateSegnalazioneAssenze(_roleForPerms)) return true;
    return false;
  }

  bool get _canAdminReview {
    if (_registroWriteBlocked) return false;
    if (_isRegistroMode) {
      return canMutateSegnalazioneAssenze(_roleForPerms);
    }
    return !widget.readOnly &&
        (widget.adminMode || canManageDipendenteAssenze(_roleForPerms));
  }

  bool get _canDtReview => !widget.readOnly && _hasDtRole;

  bool get _canDtInsertRequest =>
      _isRichiesteMode && _hasDtRole && !widget.readOnly;
  bool get _canInsertSegnalazione => _isRegistroMode && _canAdminReview;
  /// Export elenco: ok anche in sola lettura (DT).
  bool get _canExportExcelList =>
      _isRegistroMode || _canAdminReview;

  List<String> get _tipiFiltroDropdown {
    if (_isRichiesteMode) return kTipiRichiestaWorkflow;
    if (_isRegistroMode) return kTipiSegnalazioneAdmin;
    return kTipiAssenza;
  }

  String get _pageTitle {
    switch (_mode) {
      case DipendenteAssenzePageMode.richiesteWorkflow:
        return 'Richieste ferie / permessi';
      case DipendenteAssenzePageMode.registroSegnalazioni:
        return 'Segnalazione assenze';
      case DipendenteAssenzePageMode.dipendente:
        return 'Le mie ferie / permessi';
    }
  }

  @override
  void initState() {
    super.initState();
    // All'apertura mostra il mese corrente (es. se oggi è giugno -> Giugno).
    _meseFilter = DateTime.now().month;
    _load();
  }

  String _fmtDate(dynamic v) {
    final s = formatDateDdMmYyyy(v);
    return s.isEmpty ? '—' : s;
  }

  String _userLabelByUuid(String? uuid) {
    final u = (uuid ?? '').trim();
    if (u.isEmpty) return '—';
    return _usersByUuid[u] ?? u;
  }

  String _inseritoDaLabel(Map<String, dynamic> r) {
    final byCreated = _userLabelByUuid(_s(r['created_by_user_uuid']));
    if (byCreated != '—') return byCreated;
    return _userLabelByUuid(_s(r['requester_user_uuid']));
  }

  String _inserimentoAuditLine(Map<String, dynamic> r) {
    final quando = formatDateTimeItFromSupabase(r['created_at']).trim();
    final chi = _inseritoDaLabel(r);
    if (quando.isEmpty && chi == '—') return '';
    if (quando.isEmpty) return 'Inserito da: $chi';
    if (chi == '—') return 'Inserito il: $quando';
    return 'Inserito il $quando · da $chi';
  }

  String _decisionAuditLine({
    required String verb,
    required dynamic decidedAt,
    required String decidedByUuid,
  }) {
    final chi = _userLabelByUuid(decidedByUuid);
    if (chi == '—') return '';
    final quando = formatDateTimeItFromSupabase(decidedAt).trim();
    if (quando.isEmpty) return '$verb · da $chi';
    return '$verb il $quando · da $chi';
  }

  List<String> _workflowDecisionLines(Map<String, dynamic> r) {
    final st = _s(r['workflow_status']);
    final lines = <String>[];

    final dtUuid = _s(r['dt_decision_by_user_uuid']);
    if (dtUuid.isNotEmpty) {
      final dtVerb = st == _stRifiutataDt
          ? 'Rifiutata dal DT'
          : 'Approvata dal DT';
      final dtLine = _decisionAuditLine(
        verb: dtVerb,
        decidedAt: r['dt_decision_at'],
        decidedByUuid: dtUuid,
      );
      if (dtLine.isNotEmpty) lines.add(dtLine);
    }

    final adminUuid = _s(r['admin_decision_by_user_uuid']);
    if (adminUuid.isNotEmpty) {
      final adminVerb = st == _stRifiutataAdmin
          ? 'Rifiutata da admin'
          : 'Autorizzata admin';
      final adminLine = _decisionAuditLine(
        verb: adminVerb,
        decidedAt: r['admin_decision_at'],
        decidedByUuid: adminUuid,
      );
      if (adminLine.isNotEmpty) lines.add(adminLine);
    }

    return lines;
  }

  Widget _buildMetaLine(
    String text, {
    IconData icon = Icons.schedule_outlined,
    bool bounded = true,
  }) {
    final label = Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        if (bounded) Expanded(child: label) else label,
      ],
    );
  }

  String _dipendenteLabel(Map<String, dynamic> r) {
    final nome = _s(r['dipendente_nome']);
    if (nome.isNotEmpty) return nome;
    final pid = _s(r['personale_id_uuid']);
    return _s(_personaleById[pid]?['full_name']);
  }

  int? _giorni(Map<String, dynamic> r) {
    final dal = parseFlexibleDateToDateTime(r['data_dal']);
    final al = parseFlexibleDateToDateTime(r['prolungato_fino_al'] ?? r['data_al']);
    if (dal == null || al == null) return null;
    return al.difference(dal).inDays + 1;
  }

  /// La riga "appartiene" al mese [month] (1..12) se il periodo
  /// data_dal → data_al/prolungato attraversa quel mese (in qualsiasi anno).
  bool _rowCoversMonth(Map<String, dynamic> r, int month) {
    final dal = parseFlexibleDateToDateTime(r['data_dal']);
    final al = parseFlexibleDateToDateTime(
          r['prolungato_fino_al'] ?? r['data_al'],
        ) ??
        dal;
    if (dal == null) return false;
    final start = dal.year * 12 + (dal.month - 1);
    final end = (al ?? dal).year * 12 + ((al ?? dal).month - 1);
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    for (var i = lo; i <= hi; i++) {
      if ((i % 12) + 1 == month) return true;
    }
    return false;
  }

  bool _isInAtto(Map<String, dynamic> r) {
    final dal = parseFlexibleDateToDateTime(r['data_dal']);
    final al = parseFlexibleDateToDateTime(r['prolungato_fino_al'] ?? r['data_al']);
    if (dal == null || al == null) return false;
    final start = DateTime(dal.year, dal.month, dal.day);
    final end = DateTime(al.year, al.month, al.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  bool _isScaduta(Map<String, dynamic> r) {
    final al = parseFlexibleDateToDateTime(r['prolungato_fino_al'] ?? r['data_al']);
    if (al == null) return false;
    final end = DateTime(al.year, al.month, al.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.isBefore(today);
  }

  Future<void> _resolveMe() async {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return;
    final me = await Supabase.instance.client
        .from('users')
        .select('id,id_uuid,role,secondary_role,full_name')
        .eq('auth_id', authId!)
        .maybeSingle();
    if (me == null) return;
    _myUserUuid = _s(me['id_uuid']);
    _myRole = _s(me['role']);
    _mySecondaryRole = _s(me['secondary_role']);
    if (_myRole.isEmpty) _myRole = widget.role ?? 'user';
    if (_mySecondaryRole.isEmpty &&
        (widget.role ?? '').trim().isNotEmpty &&
        hasDtWorkflowRole(widget.role, null) &&
        !hasDtWorkflowRole(_myRole, null)) {
      _mySecondaryRole = widget.role!;
    }
    _usersByUuid[_myUserUuid] = _s(me['full_name']);
  }

  Future<void> _loadDizionari() async {
    _personaleById.clear();
    _personaleOptions.clear();
    _dtOptions.clear();
    final personaleRes = await Supabase.instance.client
        .from('personale')
        .select('id_uuid, full_name, matricola, active')
        .eq('active', true)
        .order('full_name', ascending: true);
    for (final e in (personaleRes as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = _s(m['id_uuid']);
      if (id.isEmpty) continue;
      _personaleById[id] = m;
      final name = _s(m['full_name']);
      if (name.isNotEmpty) {
        _personaleOptions.add(<String, String>{'id': id, 'name': name});
      }
    }

    final users = await Supabase.instance.client
        .from('users')
        .select('id_uuid,full_name,username,role,secondary_role')
        .order('full_name', ascending: true);
    for (final raw in (users as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final uuid = _s(m['id_uuid']);
      if (uuid.isEmpty) continue;
      final full = _s(m['full_name']);
      final user = _s(m['username']);
      final label = full.isNotEmpty ? full : user;
      if (label.isNotEmpty) _usersByUuid[uuid] = label;
      if (isDtSelectableRole(m['role']?.toString(), m['secondary_role']?.toString())) {
        _dtOptions.add({'id': uuid, 'name': label});
      }
    }

    _myPersonaleUuid = await EmployeeProgrammazioneService.resolveOwnPersonaleUuid(
      employeeFullName: widget.fullName,
    );
  }

  Future<void> _loadRows() async {
    var q = Supabase.instance.client
        .from('dipendente_assenze')
        .select()
        .eq('active', true);
    if (_isRichiesteMode) {
      q = q.eq('segnalazione_admin', false);
      q = q.inFilter('tipo_assenza', kTipiRichiestaWorkflow);
    } else if (_isRegistroMode) {
      q = q.eq('segnalazione_admin', true);
    }
    if (_isRichiesteMode && _hasDtRole && !_canAdminReview) {
      q = q.eq('assigned_dt_user_uuid', _myUserUuid);
    } else if (_isDipendenteMode) {
      if ((_myPersonaleUuid ?? '').isNotEmpty) {
        q = q.eq('personale_id_uuid', _myPersonaleUuid!);
      } else {
        q = q.eq('requester_user_uuid', _myUserUuid);
      }
      q = q.eq('segnalazione_admin', false);
      q = q.inFilter('tipo_assenza', kTipiRichiestaWorkflow);
    }
    final res = await q
        .order('data_dal', ascending: false)
        .order('created_at', ascending: false);
    _rows
      ..clear()
      ..addAll((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    _selectedUuids.removeWhere(
      (id) => !_rows.any((r) => _rowUuid(r) == id),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _resolveMe();
      await _loadDizionari();
      await _loadRows();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore caricamento: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    var list = List<Map<String, dynamic>>.from(_rows);
    final tipo = (_tipoFilter ?? '').trim().toUpperCase();
    if (tipo.isNotEmpty) {
      list = list.where((r) => _s(r['tipo_assenza']).toUpperCase() == tipo).toList();
    }
    final mese = _meseFilter;
    if (mese != null) {
      list = list.where((r) => _rowCoversMonth(r, mese)).toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) {
      list.sort((a, b) => _sortByPriority(a, b));
      return list;
    }
    final filtered = list.where((r) {
      final pid = _s(r['personale_id_uuid']);
      final tokens = <String>[
        _dipendenteLabel(r),
        _s(_personaleById[pid]?['matricola']),
        labelTipoAssenza(_s(r['tipo_assenza'])),
        labelWorkflow(_s(r['workflow_status'])),
        _fmtDate(r['data_dal']),
        _fmtDate(r['data_al']),
        _fmtDate(r['prolungato_fino_al']),
        _s(r['dt_comment']),
        _s(r['admin_comment']),
        _s(r['note']),
        _inserimentoAuditLine(r),
        ..._workflowDecisionLines(r),
        formatDateTimeItFromSupabase(r['created_at']),
        _inseritoDaLabel(r),
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
    filtered.sort((a, b) => _sortByPriority(a, b));
    return filtered;
  }

  int _sortByPriority(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aInAtto = _isInAtto(a);
    final bInAtto = _isInAtto(b);
    if (aInAtto != bInAtto) {
      return aInAtto ? -1 : 1;
    }

    final da = parseFlexibleDateToDateTime(a['data_dal']) ??
        parseFlexibleDateToDateTime(a['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final db = parseFlexibleDateToDateTime(b['data_dal']) ??
        parseFlexibleDateToDateTime(b['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  }

  bool _canDtAct(Map<String, dynamic> r) {
    if (!_canDtReview) return false;
    if (_s(r['workflow_status']) != _stInviataDt) return false;
    return _s(r['assigned_dt_user_uuid']) == _myUserUuid;
  }

  bool _canAdminAct(Map<String, dynamic> r) {
    if (!_canAdminReview) return false;
    return _s(r['workflow_status']) == _stApprovataDt;
  }

  bool _isOwnEmployeeRow(Map<String, dynamic> r) {
    final pid = _s(r['personale_id_uuid']);
    if ((_myPersonaleUuid ?? '').isNotEmpty && pid.isNotEmpty) {
      return pid == _myPersonaleUuid;
    }
    return _s(r['requester_user_uuid']) == _myUserUuid;
  }

  bool _canDipendenteCancel(Map<String, dynamic> r) => false;

  String _rowUuid(Map<String, dynamic> r) => _s(r['id_uuid']);

  bool get _showSelectionUi =>
      (_isRichiesteMode && _canAdminReview) ||
      (_isRegistroMode && _canAdminReview);

  bool _canCancelRow(Map<String, dynamic> r) {
    if (_isRegistroMode && _canAdminReview) return true;
    if (_isRichiesteMode && _canAdminReview) return true;
    return _canDipendenteCancel(r);
  }

  List<Map<String, dynamic>> get _selectableFilteredRows =>
      _filteredRows.where(_canCancelRow).toList(growable: false);

  List<Map<String, dynamic>> get _selectedRows => _filteredRows
      .where((r) => _selectedUuids.contains(_rowUuid(r)))
      .toList(growable: false);

  void _toggleSelectAll() {
    final selectable = _selectableFilteredRows;
    setState(() {
      if (selectable.isEmpty) {
        _selectedUuids.clear();
        return;
      }
      final allSelected = selectable.every((r) => _selectedUuids.contains(_rowUuid(r)));
      if (allSelected) {
        _selectedUuids.clear();
      } else {
        _selectedUuids
          ..clear()
          ..addAll(selectable.map(_rowUuid));
      }
    });
  }

  void _toggleRowSelection(Map<String, dynamic> r, bool selected) {
    final id = _rowUuid(r);
    if (id.isEmpty) return;
    setState(() {
      if (selected) {
        _selectedUuids.add(id);
      } else {
        _selectedUuids.remove(id);
      }
    });
  }

  Future<void> _cancelRows(
    List<Map<String, dynamic>> rows, {
    bool confirm = true,
  }) async {
    if (rows.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    if (confirm) {
      final hasApproved = rows.any((r) => _isRichiestaApprovataAdmin(r));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(rows.length == 1 ? 'Cancella richiesta' : 'Cancella selezionate (${rows.length})'),
          content: Text(
            hasApproved
                ? 'Confermi la cancellazione? Alcune richieste sono già approvate: '
                    'verranno rimosse definitivamente dal sistema.'
                : _isRegistroMode
                    ? 'Eliminare le segnalazioni selezionate dal registro?'
                    : 'Rimuovere le richieste selezionate? L\'azione è irreversibile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancella'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    var deleted = 0;
    var failed = 0;
    for (final r in rows) {
      try {
        await Supabase.instance.client
            .from('dipendente_assenze')
            .delete()
            .eq('id_uuid', _rowUuid(r));
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    _selectedUuids.removeWhere((id) => rows.any((r) => _rowUuid(r) == id));
    await _load();
    if (!mounted) return;
    if (failed == 0) {
      ModifyFeedback.success(
        context,
        deleted == 1 ? 'Richiesta rimossa.' : '$deleted richieste rimosse.',
      );
    } else {
      ModifyFeedback.error(
        context,
        'Rimosse: $deleted, non riuscite: $failed.',
      );
    }
  }

  Future<void> _bulkCancelSelected() async {
    final rows = _selectedRows.where(_canCancelRow).toList(growable: false);
    await _cancelRows(rows);
  }

  bool _isRichiestaApprovataAdmin(Map<String, dynamic> r) =>
      _s(r['workflow_status']) == _stApprovataAdmin;

  bool _canExportPdfForRow(Map<String, dynamic> r) {
    if (_isRegistroMode) return false;
    if (!_isRichiestaApprovataAdmin(r)) return false;
    if (_canAdminReview && _isRichiesteMode) return true;
    if (_isRichiesteMode && _hasDtRole) return true;
    if (_isDipendenteMode && _isOwnEmployeeRow(r)) return true;
    return false;
  }

  bool _canExportRfp03ForRow(Map<String, dynamic> r) {
    if (_isRegistroMode) return false;
    if (!_isRichiestaApprovataAdmin(r)) return false;
    return _canAdminReview && _isRichiesteMode;
  }

  String _currentUserLabel() {
    final byUuid = _usersByUuid[_myUserUuid];
    if ((byUuid ?? '').trim().isNotEmpty) return byUuid!.trim();
    return (widget.fullName ?? '').trim().isNotEmpty
        ? widget.fullName!.trim()
        : 'Admin';
  }

  String _approvatoreAdminLabelForRow(Map<String, dynamic> r) {
    final adminUuid = _s(r['admin_decision_by_user_uuid']);
    if (adminUuid.isNotEmpty) {
      final label = _usersByUuid[adminUuid];
      if ((label ?? '').trim().isNotEmpty) return label!.trim();
    }
    return _currentUserLabel();
  }

  Future<bool> _exportRfp03Modulo(
    Map<String, dynamic> r, {
    bool showFeedback = true,
  }) async {
    try {
      final bytes = await buildAssenzaRfp03ExcelBytes(
        row: r,
        approvatoreAdminLabel: _approvatoreAdminLabelForRow(r),
        dtLabel: _userLabelByUuid(_s(r['assigned_dt_user_uuid'])),
        adminComment: _s(r['admin_comment']),
      );
      final dip = _dipendenteLabel(r).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final dal = formatDateDdMmYyyy(_s(r['data_dal'])).replaceAll('/', '-');
      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: 'Mod_RFP_03_${dip}_$dal',
        bytes: bytes,
        extension: 'xlsx',
        openFile: true,
      );
      if (showFeedback && ok && mounted) {
        ModifyFeedback.success(context, 'Mod.RFP_03 esportato.');
      }
      return ok;
    } catch (e) {
      if (showFeedback && mounted) {
        ModifyFeedback.error(context, 'Export Mod.RFP_03 non riuscito: $e');
      }
      return false;
    }
  }

  Future<bool> _exportRfp03WhenAdminApproved(
    Map<String, dynamic> approvedRow, {
    String? adminComment,
  }) async {
    final row = Map<String, dynamic>.from(approvedRow);
    if ((adminComment ?? '').trim().isNotEmpty) {
      row['admin_comment'] = adminComment!.trim();
    }
    return _exportRfp03Modulo(row, showFeedback: false);
  }

  Future<void> _exportRichiestaPdf(Map<String, dynamic> r) async {
    try {
      final bytes = await buildAssenzaRichiestaPdfBytes(
        row: r,
        dipendenteLabel: _dipendenteLabel(r),
        dtLabel: _userLabelByUuid(_s(r['assigned_dt_user_uuid'])),
        approvatoreAdminLabel: _approvatoreAdminLabelForRow(r),
        adminComment: _s(r['admin_comment']),
      );
      final tipo = _s(r['tipo_assenza']).toLowerCase();
      final dal = formatDateDdMmYyyy(_s(r['data_dal'])).replaceAll('/', '-');
      final alRaw = _s(r['prolungato_fino_al']).isNotEmpty
          ? _s(r['prolungato_fino_al'])
          : _s(r['data_al']);
      final al = formatDateDdMmYyyy(alRaw).replaceAll('/', '-');
      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: 'Richiesta_${tipo}_${dal}_$al',
        bytes: bytes,
        extension: 'pdf',
        openFile: true,
      );
      if (ok && mounted) {
        ModifyFeedback.success(context, 'PDF esportato correttamente.');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ModifyFeedback.error(
        context,
        msg.contains('Gotenberg') || msg.contains('ExcelTS') || msg.contains('convertire')
            ? msg
            : 'Errore export PDF da Excel: $msg',
      );
    }
  }

  Future<void> _exportExcel() async {
    final items = _filteredRows;
    if (items.isEmpty) {
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final excel = Excel.createExcel();
      // Su web excel.delete() fallisce: liste interne non modificabili.
      final sheet = excel['Sheet1'];
      sheet.appendRow(<String>[
        'Dipendente',
        'Tipo',
        'Dal',
        'Al',
        'Prolungato fino al',
        'Stato',
        'Inserito il',
        'Inserito da',
        'DT assegnato',
        'Approvata dal DT il',
        'Approvata dal DT da',
        'Autorizzata admin il',
        'Autorizzata admin da',
        'Commento DT',
        'Commento Admin',
        'Note',
      ]);
      for (final r in items) {
        sheet.appendRow(<String>[
          _dipendenteLabel(r),
          labelTipoAssenza(_s(r['tipo_assenza'])),
          _fmtDate(r['data_dal']),
          _fmtDate(r['data_al']),
          _fmtDate(r['prolungato_fino_al']),
          _isRegistroMode ? 'Registrata' : labelWorkflow(_s(r['workflow_status'])),
          formatDateTimeItFromSupabase(r['created_at']),
          _inseritoDaLabel(r),
          _userLabelByUuid(_s(r['assigned_dt_user_uuid'])),
          formatDateTimeItFromSupabase(r['dt_decision_at']),
          _userLabelByUuid(_s(r['dt_decision_by_user_uuid'])),
          formatDateTimeItFromSupabase(r['admin_decision_at']),
          _userLabelByUuid(_s(r['admin_decision_by_user_uuid'])),
          _s(r['dt_comment']),
          _s(r['admin_comment']),
          _s(r['note']),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      await ExcelExportHelper.saveAndReveal(
        pageName: _isRegistroMode ? 'Segnalazioni_Assenze' : 'Richieste_Ferie_Permessi',
        bytes: bytes,
      );
      if (!mounted) return;
      ModifyFeedback.success(
        context,
        'Export Excel: ${ExcelExportHelper.lastSavedPath ?? 'completato'}',
      );
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    }
  }

  Future<String?> _askComment({
    required String title,
    required bool requiredComment,
  }) async {
    final ctrl = TextEditingController();
    final out = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: requiredComment ? 'Commento obbligatorio' : 'Commento (opzionale)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (requiredComment && v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  String _assenzaPeriodo(Map<String, dynamic> r) => formatAssenzaPeriodoDetail(r);

  Future<int?> _requesterUserIdFor(Map<String, dynamic> r) async {
    if (widget.userId != null &&
        _s(r['requester_user_uuid']) == _myUserUuid) {
      return widget.userId;
    }
    return NotificationSender.resolveUserId(_s(r['requester_user_uuid']));
  }

  Future<bool> _applyWorkflowUpdate({
    required String idUuid,
    required Map<String, dynamic> payload,
  }) async {
    final updated = await Supabase.instance.client
        .from('dipendente_assenze')
        .update(payload)
        .eq('id_uuid', idUuid)
        .select('id_uuid');
    return (updated as List).isNotEmpty;
  }

  Future<void> _dtApprove(Map<String, dynamic> r) async {
    if (!await ensureCanPersist(context)) return;
    try {
      final ok = await _applyWorkflowUpdate(
        idUuid: _s(r['id_uuid']),
        payload: <String, dynamic>{
          'workflow_status': _stApprovataDt,
          'dt_comment': null,
        },
      );
      if (!ok) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Approvazione non salvata. Verifica di essere il DT assegnato e che la richiesta sia ancora in attesa.',
          );
        }
        return;
      }
      try {
        final reqId = await _requesterUserIdFor(r);
        await NotificationSender.notifyAssenzaDtApprovedToRequester(
          assenzaIdUuid: _s(r['id_uuid']),
          requesterUserId: reqId,
          tipoLabel: labelTipoAssenza(_s(r['tipo_assenza'])),
          periodoLabel: _assenzaPeriodo(r),
        );
        await NotificationSender.notifyAssenzaDtApprovedToAdmin(
          assenzaIdUuid: _s(r['id_uuid']),
          requesterUserId: reqId,
          dipendenteNome: _dipendenteLabel(r),
          tipoLabel: labelTipoAssenza(_s(r['tipo_assenza'])),
          periodoLabel: _assenzaPeriodo(r),
          actorUserId: widget.userId,
        );
      } catch (e) {
        // ignore: avoid_print
        print('>>> Notifica assenza (DT approva) non inviata: $e');
      }
      await _load();
      if (mounted) {
        ModifyFeedback.success(
          context,
          'Richiesta approvata dal DT e inoltrata agli admin per la conferma finale.',
        );
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore approvazione DT: $e');
    }
  }

  Future<void> _dtReject(Map<String, dynamic> r) async {
    if (!await ensureCanPersist(context)) return;
    final c = await _askComment(
      title: 'Rifiuta richiesta (DT)',
      requiredComment: true,
    );
    if (c == null) return;
    try {
      final ok = await _applyWorkflowUpdate(
        idUuid: _s(r['id_uuid']),
        payload: <String, dynamic>{
          'workflow_status': _stRifiutataDt,
          'dt_comment': c.trim(),
        },
      );
      if (!ok) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Rifiuto non salvato. Verifica di essere il DT assegnato e che la richiesta sia ancora in attesa.',
          );
        }
        return;
      }
      try {
        final reqId = await _requesterUserIdFor(r);
        await NotificationSender.notifyAssenzaDtRejectedToRequester(
          assenzaIdUuid: _s(r['id_uuid']),
          requesterUserId: reqId,
          tipoLabel: labelTipoAssenza(_s(r['tipo_assenza'])),
          comment: c.trim(),
          periodoLabel: _assenzaPeriodo(r),
        );
      } catch (e) {
        // ignore: avoid_print
        print('>>> Notifica assenza (DT rifiuta) non inviata: $e');
      }
      await _load();
      if (mounted) ModifyFeedback.success(context, 'Richiesta rifiutata dal DT.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore rifiuto DT: $e');
    }
  }

  Future<void> _adminApprove(Map<String, dynamic> r) async {
    if (!await ensureCanPersist(context)) return;
    final c = await _askComment(
      title: 'Approva richiesta (Admin)',
      requiredComment: false,
    );
    if (c == null) return;
    try {
      final ok = await _applyWorkflowUpdate(
        idUuid: _s(r['id_uuid']),
        payload: <String, dynamic>{
          'workflow_status': _stApprovataAdmin,
          'admin_comment': c.trim().isEmpty ? null : c.trim(),
        },
      );
      if (!ok) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Approvazione admin non salvata. Verifica i permessi e che la richiesta sia ancora in attesa admin.',
          );
        }
        return;
      }
      final approvedRow = Map<String, dynamic>.from(r)
        ..['workflow_status'] = _stApprovataAdmin
        ..['admin_comment'] = c.trim().isEmpty ? null : c.trim();
      try {
        final reqId = await _requesterUserIdFor(r);
        await NotificationSender.notifyAssenzaAdminApprovedToRequester(
          assenzaIdUuid: _s(r['id_uuid']),
          requesterUserId: reqId,
          tipoLabel: labelTipoAssenza(_s(r['tipo_assenza'])),
          periodoLabel: _assenzaPeriodo(r),
        );
      } catch (e) {
        // ignore: avoid_print
        print('>>> Notifica assenza (admin approva) non inviata: $e');
      }
      final exported = await _exportRfp03WhenAdminApproved(
        approvedRow,
        adminComment: c.trim(),
      );
      await _load();
      if (mounted) {
        ModifyFeedback.success(
          context,
          exported
              ? 'Richiesta approvata. Mod.RFP_03 esportato.'
              : 'Richiesta approvata. Puoi riesportare Mod.RFP_03 o PDF dalla scheda.',
        );
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore approvazione admin: $e');
    }
  }

  Future<void> _adminReject(Map<String, dynamic> r) async {
    if (!await ensureCanPersist(context)) return;
    final c = await _askComment(
      title: 'Rifiuta richiesta (Admin)',
      requiredComment: true,
    );
    if (c == null) return;
    try {
      final ok = await _applyWorkflowUpdate(
        idUuid: _s(r['id_uuid']),
        payload: <String, dynamic>{
          'workflow_status': _stRifiutataAdmin,
          'admin_comment': c.trim(),
        },
      );
      if (!ok) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Rifiuto admin non salvato. Verifica i permessi e lo stato della richiesta.',
          );
        }
        return;
      }
      try {
        final reqId = await _requesterUserIdFor(r);
        await NotificationSender.notifyAssenzaAdminRejectedToRequester(
          assenzaIdUuid: _s(r['id_uuid']),
          requesterUserId: reqId,
          tipoLabel: labelTipoAssenza(_s(r['tipo_assenza'])),
          comment: c.trim(),
          periodoLabel: _assenzaPeriodo(r),
        );
      } catch (e) {
        // ignore: avoid_print
        print('>>> Notifica assenza (admin rifiuta) non inviata: $e');
      }
      await _load();
      if (mounted) ModifyFeedback.success(context, 'Richiesta rifiutata da admin.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore rifiuto admin: $e');
    }
  }

  Future<void> _cancelRejected(Map<String, dynamic> r) async {
    await _cancelRows([r]);
  }

  Future<void> _openAdminSegnalazioneDialog({Map<String, dynamic>? existing}) async {
    if (!_canInsertSegnalazione) return;
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AdminSegnalazioneDialog(
        personaleOptions: _personaleOptions,
        existing: existing,
        inserimentoInfo: existing != null ? _inserimentoAuditLine(existing) : null,
      ),
    );
    if (ok == true) {
      await _load();
      if (mounted) {
        ModifyFeedback.success(
          context,
          existing == null ? 'Segnalazione registrata.' : 'Segnalazione aggiornata.',
        );
      }
    }
  }

  Future<void> _deleteSegnalazione(Map<String, dynamic> r) async {
    if (!_isRegistroMode || !_canAdminReview) return;
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina segnalazione'),
        content: const Text('Eliminare questa segnalazione dal registro?'),
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
    await _cancelRows([r], confirm: false);
  }
  Future<void> _openDtInsertRequestDialog() async {
    if (!_canDtInsertRequest) return;
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DtInserisceRichiestaDialog(
        personaleOptions: _personaleOptions,
        dtUserUuid: _myUserUuid,
        actorUserId: widget.userId,
      ),
    );
    if (ok == true) {
      await _load();
      if (mounted) {
        ModifyFeedback.success(
          context,
          'Richiesta registrata. In attesa di approvazione admin.',
        );
      }
    }
  }

  Widget _statusChip(String status) {
    final color = colorWorkflow(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        labelWorkflow(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<String> _cardSummaryParts(Map<String, dynamic> r, int? giorni) {
    return [
      _dipendenteLabel(r),
      labelTipoAssenza(_s(r['tipo_assenza'])),
      formatAssenzaPeriodoDetail(r),
      if (_s(r['prolungato_fino_al']).isNotEmpty)
        'Prolungato: ${_fmtDate(r['prolungato_fino_al'])}',
      if (_isRichiesteMode || _isDipendenteMode)
        'DT: ${_userLabelByUuid(_s(r['assigned_dt_user_uuid']))}',
      if (_s(r['dt_comment']).isNotEmpty) 'Commento DT: ${_s(r['dt_comment'])}',
      if (_s(r['admin_comment']).isNotEmpty)
        'Commento Admin: ${_s(r['admin_comment'])}',
      if (_s(r['note']).isNotEmpty) 'Note: ${_s(r['note'])}',
      if (giorni != null) '$giorni gg',
    ];
  }

  Widget _buildStatusBadge(Map<String, dynamic> r, String st) {
    if (_isRegistroMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.green.shade700),
        ),
        child: Text(
          'Registrata',
          style: TextStyle(
            color: Colors.green.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return _statusChip(st);
  }

  List<Widget> _buildCardActions(Map<String, dynamic> r) {
    return [
      if (_canDtAct(r)) ...[
        FilledButton(
          onPressed: () => _dtApprove(r),
          child: const Text('Approva DT'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: () => _dtReject(r),
          child: const Text('Rifiuta DT'),
        ),
      ],
      if (_canAdminAct(r)) ...[
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => _adminApprove(r),
          child: const Text('Approva Admin'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: () => _adminReject(r),
          child: const Text('Rifiuta Admin'),
        ),
      ],
      if (_canDipendenteCancel(r)) ...[
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _cancelRejected(r),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Cancella richiesta rifiutata'),
        ),
      ],
      if (_canExportRfp03ForRow(r)) ...[
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _exportRfp03Modulo(r),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('Mod.RFP_03 Excel'),
        ),
      ],
      if (_canExportPdfForRow(r)) ...[
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _exportRichiestaPdf(r),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Export PDF'),
        ),
      ],
      if (_isRegistroMode && _canAdminReview) ...[
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _openAdminSegnalazioneDialog(existing: r),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Modifica'),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: () => _deleteSegnalazione(r),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Elimina'),
        ),
      ],
    ];
  }

  Widget _buildMonthFilters() {
    final scheme = Theme.of(context).colorScheme;
    final currentMonth = DateTime.now().month;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      bool isCurrent = false,
    }) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: scheme.primary,
        backgroundColor: isCurrent
            ? scheme.primary.withValues(alpha: 0.10)
            : null,
        side: isCurrent && !selected
            ? BorderSide(color: scheme.primary, width: 1.4)
            : null,
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimary : scheme.onSurface,
          fontWeight: selected || isCurrent ? FontWeight.w700 : FontWeight.w500,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(
              label: 'Tutti',
              selected: _meseFilter == null,
              onTap: () => setState(() => _meseFilter = null),
            ),
            const SizedBox(width: 6),
            for (var m = 1; m <= 12; m++) ...[
              chip(
                label: kMesiNomi[m - 1],
                selected: _meseFilter == m,
                isCurrent: m == currentMonth,
                onTap: () => setState(
                  () => _meseFilter = _meseFilter == m ? null : m,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final giorni = _giorni(r);
    final st = _s(r['workflow_status']);
    final rowId = _rowUuid(r);
    final canSelect = _showSelectionUi && _canCancelRow(r);
    final selected = rowId.isNotEmpty && _selectedUuids.contains(rowId);
    final inAtto = _isInAtto(r);
    final scaduta = !inAtto && _isScaduta(r);
    final compact = useMobileUi(context);
    final auditLine = _inserimentoAuditLine(r);
    final decisionLines = _workflowDecisionLines(r);
    final summary = _cardSummaryParts(r, giorni).join(' | ');
    final scheme = Theme.of(context).colorScheme;
    final cardColor = selected
        ? scheme.primaryContainer.withValues(alpha: 0.18)
        : inAtto
            ? scheme.error.withValues(alpha: 0.10)
            : scaduta
                ? scheme.tertiary.withValues(alpha: 0.10)
                : null;

    if (compact) {
      return Card(
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canSelect)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Checkbox(
                        value: selected,
                        onChanged: (v) => _toggleRowSelection(r, v == true),
                      ),
                    ),
                  _buildStatusBadge(r, st),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (auditLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildMetaLine(auditLine),
              ],
              for (final line in decisionLines) ...[
                const SizedBox(height: 4),
                _buildMetaLine(
                  line,
                  icon: line.startsWith('Autorizzata admin') ||
                          line.startsWith('Rifiutata da admin')
                      ? Icons.verified_user_outlined
                      : Icons.how_to_reg_outlined,
                ),
              ],
              if (_buildCardActions(r).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _buildCardActions(r),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canSelect)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => _toggleRowSelection(r, v == true),
                  ),
                ),
              _buildStatusBadge(r, st),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (auditLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildMetaLine(auditLine, bounded: false),
                  ],
                  for (final line in decisionLines) ...[
                    const SizedBox(height: 4),
                    _buildMetaLine(
                      line,
                      bounded: false,
                      icon: line.startsWith('Autorizzata admin') ||
                              line.startsWith('Rifiutata da admin')
                          ? Icons.verified_user_outlined
                          : Icons.how_to_reg_outlined,
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              ..._buildCardActions(r),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = useMobileUi(context);
    final items = _filteredRows;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _pageTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_showSelectionUi) ...[
            IconButton(
              tooltip: _selectableFilteredRows.isNotEmpty &&
                      _selectableFilteredRows.every((r) => _selectedUuids.contains(_rowUuid(r)))
                  ? 'Deseleziona tutto'
                  : 'Seleziona tutto',
              icon: Icon(
                _selectableFilteredRows.isNotEmpty &&
                        _selectableFilteredRows.every((r) => _selectedUuids.contains(_rowUuid(r)))
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              onPressed: _loading || _selectableFilteredRows.isEmpty ? null : _toggleSelectAll,
            ),
            IconButton(
              tooltip: 'Cancella selezionate',
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: _loading || _selectedUuids.isEmpty ? null : _bulkCancelSelected,
            ),
          ],
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: compact ? double.infinity : 300,
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      labelText: 'Cerca',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? double.infinity : 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _tipoFilter,
                    onChanged: (v) => setState(() => _tipoFilter = v),
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tutti')),
                      ..._tipiFiltroDropdown.map(
                        (t) => DropdownMenuItem<String?>(value: t, child: Text(labelTipoAssenza(t))),
                      ),
                    ],
                  ),
                ),
                if (_canExportExcelList)
                  TextButton.icon(
                    onPressed: _loading ? null : _exportExcel,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Export Excel'),
                  ),
                if (_showSelectionUi && _selectedUuids.isNotEmpty)
                  TextButton.icon(
                    onPressed: _loading ? null : _bulkCancelSelected,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: Text('Cancella (${_selectedUuids.length})'),
                  ),
              ],
            ),
          ),
          _buildMonthFilters(),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _isRegistroMode
                      ? 'Nessuna segnalazione nel registro.'
                      : 'Nessuna richiesta presente.',
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildCard(items[i]),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _canDtInsertRequest
          ? FloatingActionButton.extended(
              onPressed: _openDtInsertRequestDialog,
              icon: const Icon(Icons.add),
              label: const Text('Inserisci richiesta'),
            )
          : _canInsertSegnalazione
              ? FloatingActionButton.extended(
                  onPressed: _openAdminSegnalazioneDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Nuova segnalazione'),
                )
              : null,
    );
  }
}

class _DtInserisceRichiestaDialog extends StatefulWidget {
  final List<Map<String, String>> personaleOptions;
  final String dtUserUuid;
  final int? actorUserId;

  const _DtInserisceRichiestaDialog({
    required this.personaleOptions,
    required this.dtUserUuid,
    this.actorUserId,
  });

  @override
  State<_DtInserisceRichiestaDialog> createState() =>
      _DtInserisceRichiestaDialogState();
}

class _DtInserisceRichiestaDialogState extends State<_DtInserisceRichiestaDialog> {
  final _dalCtrl = TextEditingController();
  final _alCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _personaleUuid;
  String _tipo = kTipiRichiestaWorkflow.first;
  bool _saving = false;
  bool _permessoConOre = false;
  String? _oraInizioHhmm;
  String? _oraFineHhmm;

  bool get _isPermesso => _tipo == 'PERMESSO';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dalCtrl.text = formatDateDdMmYyyyFromDate(now);
    _alCtrl.text = formatDateDdMmYyyyFromDate(now);
  }

  @override
  void dispose() {
    _dalCtrl.dispose();
    _alCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? _dipendenteNome() {
    for (final e in widget.personaleOptions) {
      if (e['id'] == _personaleUuid) return e['name'];
    }
    return null;
  }

  int? _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  String? _timeToPg(String? hhmm) {
    final raw = (hhmm ?? '').trim();
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
  }

  double? _resolvedOrePermesso() {
    if (!_isPermesso || !_permessoConOre) return null;
    if ((_oraInizioHhmm ?? '').isNotEmpty && (_oraFineHhmm ?? '').isNotEmpty) {
      final a = _parseMinutes(_oraInizioHhmm!);
      final b = _parseMinutes(_oraFineHhmm!);
      if (a != null && b != null && b > a) {
        return (b - a) / 60.0;
      }
    }
    return null;
  }

  Future<void> _pickTime({required bool inizio}) async {
    TimeOfDay initial = TimeOfDay.now();
    final existing = inizio ? _oraInizioHhmm : _oraFineHhmm;
    if ((existing ?? '').contains(':')) {
      final p = existing!.split(':');
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (inizio) {
        _oraInizioHhmm = hhmm;
      } else {
        _oraFineHhmm = hhmm;
      }
    });
  }

  void _onTipoChanged(String? v) {
    if (v == null) return;
    setState(() {
      _tipo = v;
      if (v == 'FERIE') {
        _permessoConOre = false;
        _oraInizioHhmm = null;
        _oraFineHhmm = null;
      } else {
        final dal = parseFlexibleDateToDateTime(_dalCtrl.text) ?? DateTime.now();
        _dalCtrl.text = formatDateDdMmYyyyFromDate(dal);
        _alCtrl.clear();
      }
    });
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = parseFlexibleDateToDateTime(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('it', 'IT'),
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => ctrl.text = formatDateDdMmYyyyFromDate(picked));
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    if ((_personaleUuid ?? '').isEmpty) {
      ModifyFeedback.error(context, 'Seleziona il dipendente.');
      return;
    }
    final isoDal = parseFlexibleDateToIsoDate(_dalCtrl.text);
    if (isoDal == null) {
      ModifyFeedback.error(context, 'Data «dal» non valida.');
      return;
    }
    final isoAlRaw = parseFlexibleDateToIsoDate(_alCtrl.text.trim());
    final String isoAl;
    if (_isPermesso) {
      isoAl = isoAlRaw ?? isoDal;
    } else {
      if (isoAlRaw == null) {
        ModifyFeedback.error(context, 'Data «al» obbligatoria per le ferie.');
        return;
      }
      isoAl = isoAlRaw;
    }
    if (isoAl.compareTo(isoDal) < 0) {
      ModifyFeedback.error(context, 'La data «al» deve essere >= «dal».');
      return;
    }

    double? orePermesso;
    String? oraInizioPg;
    String? oraFinePg;
    if (_isPermesso && _permessoConOre) {
      oraInizioPg = _timeToPg(_oraInizioHhmm);
      oraFinePg = _timeToPg(_oraFineHhmm);
      if (oraInizioPg == null || oraFinePg == null) {
        ModifyFeedback.error(context, 'Indica la fascia oraria (dalle / alle).');
        return;
      }
      final inizioMin = _parseMinutes(_oraInizioHhmm!);
      final fineMin = _parseMinutes(_oraFineHhmm!);
      if (inizioMin == null ||
          fineMin == null ||
          fineMin <= inizioMin) {
        ModifyFeedback.error(context, 'L\'ora «alle» deve essere dopo «dalle».');
        return;
      }
      orePermesso = _resolvedOrePermesso();
    }

    setState(() => _saving = true);
    try {
      final requesterUuid = await userUuidForPersonale(
        Supabase.instance.client,
        _personaleUuid!,
      );
      if ((requesterUuid ?? '').isEmpty) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Dipendente senza account collegato: impossibile registrare la richiesta.',
          );
        }
        return;
      }
      final requesterUserId = await NotificationSender.resolveUserId(requesterUuid!);
      final nome = _s(_dipendenteNome());
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'personale_id_uuid': _personaleUuid,
        'dipendente_nome': nome.isEmpty ? null : nome,
        'tipo_assenza': _tipo,
        'data_dal': isoDal,
        'data_al': isoAl,
        'assigned_dt_user_uuid': widget.dtUserUuid,
        'requester_user_uuid': requesterUuid,
        'workflow_status': _stApprovataDt,
        'dt_decision_at': nowIso,
        'dt_decision_by_user_uuid': widget.dtUserUuid,
        'segnalazione_admin': false,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'active': true,
      };
      if (orePermesso != null) payload['ore_permesso'] = orePermesso;
      if (oraInizioPg != null) payload['ora_inizio'] = oraInizioPg;
      if (oraFinePg != null) payload['ora_fine'] = oraFinePg;

      final inserted = await Supabase.instance.client
          .from('dipendente_assenze')
          .insert(payload)
          .select('id_uuid')
          .single();
      final idUuid = _s(inserted['id_uuid']);
      final periodo = formatAssenzaPeriodoDetail({
        'data_dal': isoDal,
        'data_al': isoAl,
        'tipo_assenza': _tipo,
        'ore_permesso': ?orePermesso,
        'ora_inizio': ?oraInizioPg,
        'ora_fine': ?oraFinePg,
      });
      if (idUuid.isNotEmpty) {
        try {
          await NotificationSender.notifyAssenzaRegisteredByDtToEmployee(
            assenzaIdUuid: idUuid,
            requesterUserId: requesterUserId,
            tipoLabel: labelTipoAssenza(_tipo),
            periodoLabel: periodo,
          );
          await NotificationSender.notifyAssenzaDtApprovedToAdmin(
            assenzaIdUuid: idUuid,
            requesterUserId: requesterUserId,
            dipendenteNome: nome.isEmpty ? 'Dipendente' : nome,
            tipoLabel: labelTipoAssenza(_tipo),
            periodoLabel: periodo,
            actorUserId: widget.actorUserId,
          );
        } catch (notifyErr) {
          // ignore: avoid_print
          print('>>> Notifica assenza non inviata: $notifyErr');
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore registrazione: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inserisci richiesta ferie/permesso'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownSearch<String>(
                selectedItem: _personaleUuid,
                items: widget.personaleOptions.map((e) => e['id']!).toList(),
                compareFn: (a, b) => a == b,
                itemAsString: (id) {
                  for (final e in widget.personaleOptions) {
                    if (e['id'] == id) return e['name']!;
                  }
                  return id;
                },
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  constraints: BoxConstraints(maxHeight: kIsWeb ? 320 : 400),
                ),
                dropdownDecoratorProps: const DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: 'Dipendente *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                onChanged: (v) => setState(() => _personaleUuid = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                onChanged: _saving ? null : _onTipoChanged,
                decoration: const InputDecoration(
                  labelText: 'Tipo *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: kTipiRichiestaWorkflow
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(labelTipoAssenza(t)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dalCtrl,
                      readOnly: true,
                      onTap: _saving ? null : () => _pickDate(_dalCtrl),
                      decoration: InputDecoration(
                        labelText: 'Dal *',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _alCtrl,
                      readOnly: true,
                      onTap: _saving ? null : () => _pickDate(_alCtrl),
                      decoration: InputDecoration(
                        labelText: _isPermesso ? 'Al (opzionale)' : 'Al *',
                        hintText: _isPermesso ? 'Stesso giorno se vuoto' : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _isPermesso && _alCtrl.text.trim().isNotEmpty
                            ? IconButton(
                                tooltip: 'Rimuovi data «al»',
                                icon: const Icon(Icons.clear),
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _alCtrl.clear()),
                              )
                            : const Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isPermesso) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permesso a ore'),
                  subtitle: const Text(
                    'Es. 18/06 dalle 10:00 alle 12:00. Per più giorni, stessa fascia oraria.',
                  ),
                  value: _permessoConOre,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            _permessoConOre = v;
                            if (!v) {
                              _oraInizioHhmm = null;
                              _oraFineHhmm = null;
                            }
                          }),
                ),
                if (_permessoConOre) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _pickTime(inizio: true),
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            (_oraInizioHhmm ?? '').isEmpty
                                ? 'Dalle ore *'
                                : 'Dalle $_oraInizioHhmm',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _pickTime(inizio: false),
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            (_oraFineHhmm ?? '').isEmpty
                                ? 'Alle ore *'
                                : 'Alle $_oraFineHhmm',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La richiesta sarà visibile subito al dipendente e inviata all\'amministrazione per l\'approvazione.',
                style: Theme.of(context).textTheme.bodySmall,
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
              : const Text('Registra'),
        ),
      ],
    );
  }
}

class _AdminSegnalazioneDialog extends StatefulWidget {
  final List<Map<String, String>> personaleOptions;
  final Map<String, dynamic>? existing;
  final String? inserimentoInfo;

  const _AdminSegnalazioneDialog({
    required this.personaleOptions,
    this.existing,
    this.inserimentoInfo,
  });

  @override
  State<_AdminSegnalazioneDialog> createState() => _AdminSegnalazioneDialogState();
}

class _AdminSegnalazioneDialogState extends State<_AdminSegnalazioneDialog> {
  final _dalCtrl = TextEditingController();
  final _alCtrl = TextEditingController();
  final _prolungatoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _personaleUuid;
  String _tipo = 'MALATTIA';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _personaleUuid = _s(ex['personale_id_uuid']);
      _tipo = _s(ex['tipo_assenza']).isEmpty ? 'MALATTIA' : _s(ex['tipo_assenza']).toUpperCase();
      _dalCtrl.text = formatDateDdMmYyyy(ex['data_dal']);
      _alCtrl.text = formatDateDdMmYyyy(ex['data_al']);
      _prolungatoCtrl.text = formatDateDdMmYyyy(ex['prolungato_fino_al']);
      _noteCtrl.text = _s(ex['note']);
      if (_dalCtrl.text.isEmpty || _alCtrl.text.isEmpty) {
        final now = DateTime.now();
        if (_dalCtrl.text.isEmpty) _dalCtrl.text = formatDateDdMmYyyyFromDate(now);
        if (_alCtrl.text.isEmpty) _alCtrl.text = formatDateDdMmYyyyFromDate(now);
      }
    } else {
      final now = DateTime.now();
      _dalCtrl.text = formatDateDdMmYyyyFromDate(now);
      _alCtrl.text = formatDateDdMmYyyyFromDate(now);
    }
  }

  @override
  void dispose() {
    _dalCtrl.dispose();
    _alCtrl.dispose();
    _prolungatoCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = parseFlexibleDateToDateTime(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('it', 'IT'),
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => ctrl.text = formatDateDdMmYyyyFromDate(picked));
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    if ((_personaleUuid ?? '').isEmpty) {
      ModifyFeedback.error(context, 'Seleziona il dipendente.');
      return;
    }
    final isoDal = parseFlexibleDateToIsoDate(_dalCtrl.text);
    final isoAl = parseFlexibleDateToIsoDate(_alCtrl.text);
    if (isoDal == null || isoAl == null) {
      ModifyFeedback.error(context, 'Date non valide.');
      return;
    }
    if (isoAl.compareTo(isoDal) < 0) {
      ModifyFeedback.error(context, 'La data «al» deve essere >= «dal».');
      return;
    }
    final isoProl = parseFlexibleDateToIsoDate(_prolungatoCtrl.text);

    String? dipNome;
    for (final e in widget.personaleOptions) {
      if (e['id'] == _personaleUuid) {
        dipNome = e['name'];
        break;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'personale_id_uuid': _personaleUuid,
        'dipendente_nome': _s(dipNome),
        'tipo_assenza': _tipo,
        'data_dal': isoDal,
        'data_al': isoAl,
        'prolungato_fino_al': isoProl,
        'segnalazione_admin': true,
        'workflow_status': _stApprovataAdmin,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'active': true,
      };
      final ex = widget.existing;
      if (ex == null) {
        await Supabase.instance.client.from('dipendente_assenze').insert(payload);
      } else {
        await Supabase.instance.client
            .from('dipendente_assenze')
            .update(payload)
            .eq('id_uuid', ex['id_uuid']);
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
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modifica segnalazione assenza' : 'Nuova segnalazione assenza'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              if ((widget.inserimentoInfo ?? '').trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.inserimentoInfo!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownSearch<String>(
                selectedItem: _personaleUuid,
                items: widget.personaleOptions.map((e) => e['id']!).toList(),
                compareFn: (a, b) => a == b,
                itemAsString: (id) {
                  for (final e in widget.personaleOptions) {
                    if (e['id'] == id) return e['name']!;
                  }
                  return id;
                },
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  constraints: BoxConstraints(maxHeight: kIsWeb ? 320 : 400),
                ),
                dropdownDecoratorProps: const DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: 'Dipendente *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                onChanged: (v) => setState(() => _personaleUuid = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                decoration: const InputDecoration(
                  labelText: 'Tipo *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: kTipiSegnalazioneAdmin
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(labelTipoAssenza(t)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dalCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(_dalCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Dal *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _alCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(_alCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Al *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prolungatoCtrl,
                readOnly: true,
                onTap: () => _pickDate(_prolungatoCtrl),
                decoration: const InputDecoration(
                  labelText: 'Prolungato fino al (opzionale)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
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
