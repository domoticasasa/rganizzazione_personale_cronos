import 'dart:async';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/employee_programmazione_service.dart';
import '../services/formazione_dlgs_strutture_service.dart';
import '../services/formazione_programmazione_service.dart';
import '../services/programmazione_formazioni_pdf_export.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_web_safe.dart';
import '../utils/formazione_programmazione_dates.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/users_directory.dart';
import '../utils/dt_view_role.dart';
import '../utils/roles.dart' show canManageFormazioneDlgs81Griglia, hasDtWorkflowRole;
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/dlgs_struttura_selector.dart';
import '../widgets/struttura_link_cell.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Corsi D.Lgs. 81/08 con **data programmazione** impostata (admin/DT o dipendente).
class DtProgrammazioneFormazioniPage extends StatefulWidget {
  final bool employeeOnly;
  final String? employeeFullName;
  final String? role;

  const DtProgrammazioneFormazioniPage({
    super.key,
    this.employeeOnly = false,
    this.employeeFullName,
    this.role,
  });

  @override
  State<DtProgrammazioneFormazioniPage> createState() =>
      _DtProgrammazioneFormazioniPageState();
}

class _DtProgrammazioneFormazioniPageState
    extends State<DtProgrammazioneFormazioniPage> {
  bool _loading = true;
  String _search = '';
  String? _ownPersonaleId;
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dlgsStrutture = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _personaleById =
      <String, Map<String, dynamic>>{};
  final Set<String> _expandedRowKeys = <String>{};
  bool _blinkOn = true;
  Timer? _blinkTimer;
  String? _resolvedRole;

  bool get _employeeOnly => widget.employeeOnly;
  bool get _canEdit {
    if (_employeeOnly) return false;
    final role = DtViewRoleScope.resolveForPage(
      context,
      (widget.role ?? _resolvedRole ?? '').trim().isEmpty
          ? null
          : widget.role ?? _resolvedRole,
    );
    if (role.isEmpty) return false;
    return canManageFormazioneDlgs81Griglia(role);
  }

  /// Card espandibili su mobile e per la vista dipendente.
  bool _layoutCompact(BuildContext context) =>
      _employeeOnly || useMobileUi(context);

  @override
  void initState() {
    super.initState();
    if (!widget.employeeOnly && widget.role == null) {
      _resolveCurrentUserRole();
    }
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _load();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  String _fmtProgDalAl(Map<String, dynamic> r) =>
      formatProgrammazioneDalAl(r['prima_data'], r['seconda_data']);

  bool _rowVisibleOnProgrammazioneScreen(Map<String, dynamic> r) {
    final prima =
        FormazioneProgrammazioneService.parseDateOnly(r['prima_data']);
    if (prima == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !FormazioneProgrammazioneService.shouldClearAfterProgrammazione(
      r,
      today,
    );
  }

  bool _progDateHighlighted(Map<String, dynamic> r) {
    if (isProgrammazioneTodayOrInCorso(r['prima_data'], r['seconda_data'])) {
      return true;
    }
    final days = daysUntilProgrammazioneStart(r['prima_data']);
    if (days == null) return false;
    return days >= 0 && days <= 2;
  }

  bool _progDateBlinkToday(Map<String, dynamic> r) =>
      isProgrammazioneTodayOrInCorso(r['prima_data'], r['seconda_data']);

  bool _progHasDateRange(Map<String, dynamic> r) {
    final label = _fmtProgDalAl(r);
    return label.contains('–');
  }

  Future<void> _exportPdf() async {
    final items = _filteredRows;
    if (items.isEmpty) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final bytes = await buildProgrammazioneFormazioniPdfBytes(
        rows: items,
        personaleById: _personaleById,
        employeeOnly: _employeeOnly,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Programmazione_Formazioni',
        bytes: bytes,
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ModifyFeedback.success(
          context,
          kIsWeb
              ? 'Export PDF avviato (controlla i download del browser).'
              : 'Export PDF completato.',
        );
      } else {
        ModifyFeedback.error(context, 'Export PDF non riuscito.');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export PDF: $e');
    }
  }

  Future<void> _exportExcel() async {
    final items = _filteredRows;
    if (items.isEmpty) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excelUseDefaultSheet(excel);
      if (_employeeOnly) {
        sheet.appendRow(<String>[
          'Data prog.',
          'Corso',
          'Ente',
          'Attestato',
          'Scadenza',
          'ODA',
          'Orario',
          'Modalità',
          'Struttura / Link',
          'Note',
        ]);
      } else {
        sheet.appendRow(<String>[
          'Data prog.',
          'Scadenza',
          'Dipendente',
          'Matricola',
          'Corso',
          'Ente',
          'Attestato',
          'ODA',
          'Orario',
          'Modalità',
          'Struttura / Link',
          'Note',
        ]);
      }
      for (final r in items) {
        final pid = _s(r['personale_id']);
        final p = _personaleById[pid];
        final prog = _fmtProgDalAl(r);
        if (_employeeOnly) {
          sheet.appendRow(<String>[
            prog.isEmpty ? _fmtDate(r['prima_data']) : prog,
            _s(r['corso']),
            _s(r['ente']),
            _fmtDate(r['data_attestato']),
            _fmtDate(r['scadenza_attestato']),
            _s(r['oda']),
            _s(r['orario']),
            _s(r['modalita']),
            _s(r['struttura_link']),
            _s(r['note']),
          ]);
        } else {
          sheet.appendRow(<String>[
            prog.isEmpty ? _fmtDate(r['prima_data']) : prog,
            _fmtDate(r['scadenza_attestato']),
            _s(p?['full_name']),
            _s(p?['matricola']),
            _s(r['corso']),
            _s(r['ente']),
            _fmtDate(r['data_attestato']),
            _s(r['oda']),
            _s(r['orario']),
            _s(r['modalita']),
            _s(r['struttura_link']),
            _s(r['note']),
          ]);
        }
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Programmazione_Formazioni',
        bytes: bytes,
      );
      if (!mounted) return;
      if (saved) {
        ModifyFeedback.success(
          context,
          kIsWeb
              ? 'Export Excel avviato (controlla i download del browser).'
              : 'Export Excel: ${ExcelExportHelper.lastSavedPath ?? 'completato'}',
        );
      } else if (mounted) {
        ModifyFeedback.error(context, 'Export Excel non riuscito.');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    }
  }

  Future<void> _resolveCurrentUserRole() async {
    try {
      final scope = DtViewRoleScope.maybeOf(context);
      if (scope != null) {
        if (!mounted) return;
        setState(() => _resolvedRole = scope.effectiveRole);
        return;
      }
      final uid = SupabaseService.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await SupabaseService.client
          .from('users')
          .select('role, secondary_role')
          .eq('auth_id', uid)
          .maybeSingle();
      if (!mounted) return;
      final primary = (row?['role'] ?? '').toString();
      final secondary = (row?['secondary_role'] ?? '').toString();
      setState(
        () => _resolvedRole = hasDtWorkflowRole(primary, secondary)
            ? dtPreviewEffectiveRole(
                sessionPrimaryRole: primary,
                sessionSecondaryRole: secondary,
              )
            : primary,
      );
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      String? myPersonaleId;
      if (_employeeOnly) {
        myPersonaleId = await EmployeeProgrammazioneService.resolveOwnPersonaleUuid(
          employeeFullName: widget.employeeFullName,
        );
        _ownPersonaleId = myPersonaleId;
        if (myPersonaleId == null || myPersonaleId.isEmpty) {
          _personaleById.clear();
          _rows.clear();
          if (mounted) {
            ModifyFeedback.error(
              context,
              'Impossibile collegare la tua anagrafica.',
            );
          }
          return;
        }
      }

      _personaleById.clear();
      if (_employeeOnly && myPersonaleId != null) {
        final p = await SupabaseService.client
            .from('personale')
            .select('id_uuid, full_name, matricola, telefono, email, active')
            .eq('id_uuid', myPersonaleId)
            .maybeSingle();
        if (p != null) {
          final m = Map<String, dynamic>.from(p as Map);
          final id = _s(m['id_uuid']);
          if (id.isNotEmpty) _personaleById[id] = m;
        }
      } else {
        final personaleRes = await UsersDirectory.visiblePersonale(
          await SupabaseService.client
              .from('personale')
              .select('id_uuid, full_name, matricola, telefono, email, active')
              as List,
        );
        for (final m in personaleRes) {
          final id = _s(m['id_uuid']);
          if (id.isNotEmpty) _personaleById[id] = m;
        }
      }

      if (_canEdit) {
        _dlgsStrutture = await FormazioneDlgsStruttureService.loadAll();
      } else {
        _dlgsStrutture = await FormazioneDlgsStruttureService.loadActive();
      }

      var corsiQuery = SupabaseService.client
          .from('formazione_corsi')
          .select()
          .not('prima_data', 'is', null);
      if (_employeeOnly && myPersonaleId != null) {
        corsiQuery = corsiQuery.eq('personale_id', myPersonaleId);
      }
      List<Map<String, dynamic>> loaded;
      try {
        final rpcRes = await SupabaseService.client.rpc(
          'formazione_corsi_programmazione_rows',
          params: <String, dynamic>{
            'p_only_personale_uuid':
                _employeeOnly ? myPersonaleId : null,
          },
        );
        loaded = (rpcRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        final corsiRes = await corsiQuery.order('prima_data', ascending: true);
        loaded = (corsiRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (_canEdit) {
        await FormazioneProgrammazioneService.purgeExpiredFromRows(loaded);
      }
      _rows
        ..clear()
        ..addAll(loaded)
        ..removeWhere((r) => !_rowVisibleOnProgrammazioneScreen(r));
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore caricamento: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, dynamic>>.from(_rows);
    return _rows.where((r) {
      final pid = _s(r['personale_id']);
      final p = _personaleById[pid];
      final tokens = <String>[
        _s(p?['full_name']),
        _s(p?['matricola']),
        _s(p?['telefono']),
        _s(p?['email']),
        _s(r['corso']),
        _s(r['ente']),
        _s(r['primo_rilascio_aggiornamento']),
        _s(r['modalita']),
        _s(r['struttura_link']),
        _s(r['orario']),
        _s(r['oda']),
        _s(r['note']),
        _fmtProgDalAl(r),
        _fmtDate(r['data_attestato']),
        _fmtDate(r['scadenza_attestato']),
        _fmtDate(r['prima_data']),
        _fmtDate(r['seconda_data']),
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  TextStyle? get _metaStyle =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );

  String _rowKey(Map<String, dynamic> r, int index) {
    final id = _s(r['id']);
    if (id.isNotEmpty) return 'fc_$id';
    return 'fc_${_s(r['personale_id'])}_${_s(r['corso'])}_${_s(r['prima_data'])}_$index';
  }

  Widget _progDateChip(Map<String, dynamic> r, {bool compact = false}) {
    final hi = _progDateHighlighted(r);
    final blinkToday = _progDateBlinkToday(r);
    final hasRange = _progHasDateRange(r);

    Color bg;
    Color fg;
    if (blinkToday) {
      bg = _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.18);
      fg = _blinkOn ? Colors.white : Colors.red.shade900;
    } else if (hi) {
      bg = Colors.red.withValues(alpha: 0.12);
      fg = Colors.red.shade900;
    } else if (hasRange) {
      bg = Colors.green.withValues(alpha: 0.14);
      fg = Colors.green.shade900;
    } else {
      bg = Theme.of(context).colorScheme.primaryContainer;
      fg = Theme.of(context).colorScheme.onPrimaryContainer;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: hi ? Border.all(color: Colors.red.shade700, width: 0.8) : null,
      ),
      child: Text(
        _fmtProgDalAl(r).isEmpty ? _fmtDate(r['prima_data']) : _fmtProgDalAl(r),
        style: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _progDateTableCell(Map<String, dynamic> r) {
    final label = _fmtProgDalAl(r).isEmpty
        ? _fmtDate(r['prima_data'])
        : _fmtProgDalAl(r);
    final hi = _progDateHighlighted(r);
    final blinkToday = _progDateBlinkToday(r);
    final hasRange = _progHasDateRange(r);

    Color bg;
    Color fg;
    if (blinkToday) {
      bg = _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.14);
      fg = _blinkOn ? Colors.white : Colors.red.shade900;
    } else if (hi) {
      bg = Colors.red.withValues(alpha: 0.1);
      fg = Colors.red.shade900;
    } else if (hasRange) {
      bg = Colors.green.withValues(alpha: 0.12);
      fg = Colors.green.shade800;
    } else {
      bg = Theme.of(context).colorScheme.primaryContainer;
      fg = Theme.of(context).colorScheme.onPrimaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: blinkToday
            ? Border.all(color: Colors.red.shade700, width: 0.8)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: fg,
          fontSize: 13,
        ),
      ),
    );
  }

  Color? _dataRowFillColor(Map<String, dynamic> r) {
    if (_progDateBlinkToday(r)) {
      return _blinkOn
          ? Colors.red.withValues(alpha: 0.22)
          : Colors.red.withValues(alpha: 0.06);
    }
    if (_progHasDateRange(r)) {
      return Colors.green.withValues(alpha: 0.1);
    }
    return null;
  }

  Widget _tableColumnLabel(String text, {bool highlight = false}) {
    if (!highlight) return Text(text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.green.shade900,
        ),
      ),
    );
  }

  Widget _personBlock(String personaleId) {
    final p = _personaleById[personaleId];
    final name = _s(p?['full_name']);
    final matr = _s(p?['matricola']);
    final tel = _s(p?['telefono']);
    final email = _s(p?['email']);
    final active = p?['active'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? 'Dipendente' : name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (matr.isNotEmpty) Text('Matr. $matr', style: _metaStyle),
        if (tel.isNotEmpty) Text('Tel. $tel', style: _metaStyle),
        if (email.isNotEmpty) Text(email, style: _metaStyle),
        if (!active && p != null)
          Text(
            'Personale non attivo',
            style: _metaStyle?.copyWith(color: Colors.orange.shade800),
          ),
      ],
    );
  }

  List<Widget> _courseDetailBlocks(Map<String, dynamic> r, String personaleId) {
    final modalita = _s(r['modalita']);
    final strutturaLabel =
        modalita.toLowerCase() == 'online' ? 'Link' : 'Struttura (in presenza)';
    return [
      if (!_employeeOnly) ...[
        _personBlock(personaleId),
        const Divider(height: 16),
      ],
      _detailRow('Ente', _s(r['ente']), compact: _layoutCompact(context)),
      _detailRow(
        'Tipo rilascio',
        _s(r['primo_rilascio_aggiornamento']),
        compact: _layoutCompact(context),
      ),
      _detailRow('Data attestato', _fmtDate(r['data_attestato']),
          compact: _layoutCompact(context)),
      _detailRow('Scadenza attestato', _fmtDate(r['scadenza_attestato']),
          compact: _layoutCompact(context)),
      _detailRow('ODA', _s(r['oda']), compact: _layoutCompact(context)),
      _detailRow('Orario', _s(r['orario']), compact: _layoutCompact(context)),
      _detailRow('Modalità', modalita, compact: _layoutCompact(context)),
      if (_s(r['struttura_nome']).isNotEmpty) ...[
        _detailRow('Struttura', _s(r['struttura_nome']),
            compact: _layoutCompact(context)),
        _detailRow('Indirizzo', _s(r['struttura_indirizzo']),
            compact: _layoutCompact(context)),
        if (_s(r['struttura_email']).isNotEmpty)
          _detailRow('Email struttura', _s(r['struttura_email']),
              compact: _layoutCompact(context)),
        _detailLinkRow('Link Maps', _s(r['struttura_link']),
            compact: _layoutCompact(context)),
      ] else
        _detailLinkRow(strutturaLabel, _s(r['struttura_link']),
            compact: _layoutCompact(context)),
      if (_s(r['note']).isNotEmpty) ...[
        const SizedBox(height: 4),
        NotePreviewText(
          note: _s(r['note']),
          prefix: 'Note: ',
          maxChars: _layoutCompact(context) ? 120 : 80,
        ),
      ],
    ];
  }

  static const List<String> _modalitaOptions = <String>['Online', 'In presenza'];

  Future<void> _openCourseDetail(Map<String, dynamic> row) async {
    final pid = _s(row['personale_id']);
    var progAl = _fmtDate(row['seconda_data']);
    final progDal = _fmtDate(row['prima_data']);
    if (progAl == progDal) progAl = '';
    final programmazioneDalCtrl = TextEditingController(text: progDal);
    final programmazioneAlCtrl = TextEditingController(text: progAl);
    final odaCtrl = TextEditingController(text: _s(row['oda']));
    final orarioCtrl = TextEditingController(text: _s(row['orario']));
    final modalitaValue = ValueNotifier<String>(_s(row['modalita']));
    final strutturaIdNotifier = ValueNotifier<String?>(
      _s(row['struttura_dlgs_id']).isEmpty ? null : _s(row['struttura_dlgs_id']),
    );
    final strutturaLinkCtrl =
        TextEditingController(text: _s(row['struttura_link']));
    final noteCtrl = TextEditingController(text: _s(row['note']));
    final editable = _canEdit;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            editable ? 'Modifica programmazione' : 'Dettaglio programmazione',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._courseDetailBlocks(row, pid),
                  const Divider(height: 24),
                  Text(
                    'Programmazione corso',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: programmazioneDalCtrl,
                          readOnly: !editable,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: editable
                              ? const [_ProgDateSlashFormatter()]
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Data programmazione dal (gg/mm/aaaa)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: programmazioneAlCtrl,
                          readOnly: !editable,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: editable
                              ? const [_ProgDateSlashFormatter()]
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Data programmazione al (gg/mm/aaaa)',
                            hintText: 'Vuoto = un solo giorno',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: odaCtrl,
                          readOnly: !editable,
                          decoration: const InputDecoration(
                            labelText: 'ODA',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: orarioCtrl,
                          readOnly: !editable,
                          decoration: const InputDecoration(
                            labelText: 'Orario',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: modalitaValue,
                    builder: (_, value, _) {
                      String? selected;
                      final v = value.trim().toLowerCase();
                      if (v == 'online') {
                        selected = 'Online';
                      } else if (v == 'in presenza') {
                        selected = 'In presenza';
                      }
                      if (!editable) {
                        return InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Modalità',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(value.isEmpty ? '—' : value),
                        );
                      }
                      return DropdownButtonFormField<String>(
                        initialValue: selected,
                        decoration: const InputDecoration(
                          labelText: 'Modalità',
                          border: OutlineInputBorder(),
                        ),
                        items: _modalitaOptions
                            .map(
                              (o) => DropdownMenuItem(
                                value: o,
                                child: Text(o),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) =>
                            modalitaValue.value = (v ?? '').trim(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: modalitaValue,
                    builder: (_, value, _) {
                      final isOnline = value.toLowerCase() == 'online';
                      return ValueListenableBuilder<String?>(
                        valueListenable: strutturaIdNotifier,
                        builder: (_, _, _) {
                          return DlgsStrutturaSelector(
                            strutture: _dlgsStrutture,
                            selectedId: strutturaIdNotifier.value,
                            onlineMode: isOnline,
                            onlineLinkController: strutturaLinkCtrl,
                            readOnly: !editable,
                            onOpenLinkFailed: _onLinkOpenFailed,
                            onChanged: !editable || isOnline
                                ? null
                                : (s) {
                                    strutturaIdNotifier.value = s == null
                                        ? null
                                        : _s(s['id_uuid']);
                                    if (s != null) {
                                      strutturaLinkCtrl.text =
                                          _s(s['maps_link']);
                                    } else {
                                      strutturaLinkCtrl.clear();
                                    }
                                  },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    readOnly: !editable,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(editable ? 'Annulla' : 'Chiudi'),
            ),
            if (editable)
              AsyncFilledButton(
                onPressed: () async {
                  final norm = normalizeProgrammazioneIso(
                    dalText: programmazioneDalCtrl.text,
                    alText: programmazioneAlCtrl.text,
                  );
                  if (norm.error != null) {
                    ModifyFeedback.error(ctx, norm.error!);
                    return;
                  }
                  final id = row['id'];
                  if (id == null) {
                    ModifyFeedback.error(ctx, 'Record corso non valido.');
                    return;
                  }
                  final isOnline =
                      modalitaValue.value.trim().toLowerCase() == 'online';
                  final selected = FormazioneDlgsStruttureService.findById(
                    _dlgsStrutture,
                    strutturaIdNotifier.value,
                  );
                  final strutturaFields = isOnline
                      ? <String, dynamic>{
                          ...FormazioneDlgsStruttureService
                              .clearCorsoStrutturaPayload(),
                          'struttura_link':
                              strutturaLinkCtrl.text.trim().isEmpty
                                  ? null
                                  : strutturaLinkCtrl.text.trim(),
                        }
                      : selected != null
                          ? () {
                              final m =
                                  FormazioneDlgsStruttureService.fieldsFromStruttura(
                                selected,
                              );
                              return <String, dynamic>{
                                'struttura_dlgs_id':
                                    m['struttura_dlgs_id']!.isEmpty
                                        ? null
                                        : m['struttura_dlgs_id'],
                                'struttura_nome': m['struttura_nome'],
                                'struttura_indirizzo': m['struttura_indirizzo'],
                                'struttura_email': m['struttura_email'],
                                'struttura_link': m['struttura_link'],
                              };
                            }()
                          : FormazioneDlgsStruttureService
                              .clearCorsoStrutturaPayload();
                  final payload = <String, dynamic>{
                    'prima_data': norm.primaIso,
                    'seconda_data': norm.secondaIso,
                    'oda': odaCtrl.text.trim().isEmpty
                        ? null
                        : odaCtrl.text.trim(),
                    'orario': orarioCtrl.text.trim().isEmpty
                        ? null
                        : orarioCtrl.text.trim(),
                    'modalita': modalitaValue.value.trim().isEmpty
                        ? null
                        : modalitaValue.value.trim(),
                    ...strutturaFields,
                    'note': noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                    'updated_at': supabaseNowIsoUtc(),
                  };
                  try {
                    await SupabaseService.client
                        .from('formazione_corsi')
                        .update(payload)
                        .eq('id', id);
                  } catch (e) {
                    payload.remove('seconda_data');
                    await SupabaseService.client
                        .from('formazione_corsi')
                        .update(payload)
                        .eq('id', id);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Salva'),
              ),
          ],
        );
      },
    );

    programmazioneDalCtrl.dispose();
    programmazioneAlCtrl.dispose();
    odaCtrl.dispose();
    orarioCtrl.dispose();
    modalitaValue.dispose();
    strutturaIdNotifier.dispose();
    strutturaLinkCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      ModifyFeedback.success(context, 'Programmazione aggiornata.');
      await _load();
    }
  }

  void _onLinkOpenFailed() {
    if (mounted) {
      ModifyFeedback.error(context, 'Impossibile aprire il link.');
    }
  }

  Widget _detailLinkRow(String label, String link, {bool compact = false}) {
    final t = link.trim();
    if (t.isEmpty) {
      return _detailRow(label, '', compact: compact);
    }
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: ',
              style: _metaStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: StrutturaLinkCell(
                link: t,
                compact: true,
                onOpenFailed: _onLinkOpenFailed,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: _metaStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: StrutturaLinkCell(
              link: t,
              onOpenFailed: _onLinkOpenFailed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool compact = false}) {
    final v = value.isEmpty ? '—' : value;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodySmall,
            children: [
              TextSpan(
                text: '$label: ',
                style: _metaStyle?.copyWith(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: v, style: _metaStyle),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: _metaStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _compactCourseCard(Map<String, dynamic> r, int index) {
    final pid = _s(r['personale_id']);
    final p = _personaleById[pid];
    final dipendente = _s(p?['full_name']);
    final rowKey = _rowKey(r, index);
    final expanded = _expandedRowKeys.contains(rowKey);
    final corso = _s(r['corso']).isEmpty ? 'Corso' : _s(r['corso']);
    final ente = _s(r['ente']);
    final orario = _s(r['orario']);
    final scad = _fmtDate(r['scadenza_attestato']);

    final blinkToday = _progDateBlinkToday(r);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      elevation: 0,
      color: blinkToday
          ? (_blinkOn
              ? Colors.red.withValues(alpha: 0.14)
              : Colors.red.withValues(alpha: 0.04))
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: blinkToday
              ? Colors.red.shade700
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.6),
          width: blinkToday ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCourseDetail(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _progDateChip(r, compact: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_employeeOnly && dipendente.isNotEmpty)
                          Text(
                            dipendente,
                            style: _metaStyle?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          corso,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (scad.isNotEmpty ||
                            ente.isNotEmpty ||
                            orario.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(
                                style: _metaStyle,
                                children: [
                                  if (scad.isNotEmpty)
                                    TextSpan(text: 'Scad. $scad'),
                                  if (scad.isNotEmpty &&
                                      (ente.isNotEmpty || orario.isNotEmpty))
                                    const TextSpan(text: ' · '),
                                  if (ente.isNotEmpty)
                                    TextSpan(
                                      text: ente +
                                          (orario.isNotEmpty ? ' · ' : ''),
                                    ),
                                  if (orario.isNotEmpty) TextSpan(text: orario),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expandedRowKeys.remove(rowKey);
                      } else {
                        _expandedRowKeys.add(rowKey);
                      }
                    });
                  },
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                  ),
                  label: Text(
                    expanded ? 'Nascondi dettagli' : 'Mostra dettagli',
                  ),
                ),
              ),
              if (expanded) ..._courseDetailBlocks(r, pid),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fullCourseCard(Map<String, dynamic> r, int index) {
    final pid = _s(r['personale_id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openCourseDetail(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _progDateChip(r),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _s(r['corso']).isEmpty ? 'Corso' : _s(r['corso']),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._courseDetailBlocks(r, pid),
            ],
          ),
        ),
      ),
    );
  }

  Widget _courseCard(Map<String, dynamic> r, int index) {
    if (_layoutCompact(context)) return _compactCourseCard(r, index);
    return _fullCourseCard(r, index);
  }

  Widget _desktopTable(List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 14,
        horizontalMargin: 10,
        headingRowColor: WidgetStateProperty.all(Colors.green.shade50),
        columns: [
          DataColumn(
            label: _tableColumnLabel('Data prog.', highlight: true),
          ),
          const DataColumn(label: Text('Scadenza')),
          if (!_employeeOnly) const DataColumn(label: Text('Dipendente')),
          if (!_employeeOnly) const DataColumn(label: Text('Matricola')),
          const DataColumn(label: Text('Corso')),
          const DataColumn(label: Text('Ente')),
          const DataColumn(label: Text('Attestato')),
          const DataColumn(label: Text('ODA')),
          const DataColumn(label: Text('Orario')),
          const DataColumn(label: Text('Modalità')),
          const DataColumn(label: Text('Struttura / Link')),
          const DataColumn(label: Text('Note')),
        ],
        rows: items.map((r) {
          final pid = _s(r['personale_id']);
          final p = _personaleById[pid];
          return DataRow(
            color: WidgetStateProperty.resolveWith(
              (_) => _dataRowFillColor(r),
            ),
            onSelectChanged: (_) => _openCourseDetail(r),
            cells: [
              DataCell(_progDateTableCell(r)),
              DataCell(Text(_fmtDate(r['scadenza_attestato']))),
              if (!_employeeOnly) DataCell(Text(_s(p?['full_name']))),
              if (!_employeeOnly) DataCell(Text(_s(p?['matricola']))),
              DataCell(Text(_s(r['corso']))),
              DataCell(Text(_s(r['ente']))),
              DataCell(Text(_fmtDate(r['data_attestato']))),
              DataCell(Text(_s(r['oda']))),
              DataCell(Text(_s(r['orario']))),
              DataCell(Text(_s(r['modalita']))),
              DataCell(
                SizedBox(
                  width: 120,
                  child: DlgsStrutturaTableCell(
                    row: r,
                    compact: true,
                    onOpenLinkFailed: _onLinkOpenFailed,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 160,
                  child: NotePreviewText(
                    note: _s(r['note']),
                    maxChars: 24,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _exportButtonsRow() {
    return Row(
      children: [
        if (!_employeeOnly) ...[
          TextButton.icon(
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          const SizedBox(width: 8),
        ],
        TextButton.icon(
          onPressed: _loading ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredRows;
    final compact = _layoutCompact(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Programmazione Formazioni',
        ),
        actions: [
          if (!_employeeOnly) ...[
            IconButton(
              tooltip: 'Export Excel',
              onPressed: _loading ? null : _exportExcel,
              icon: const Icon(Icons.table_chart_outlined),
            ),
            IconButton(
              tooltip: 'Export PDF',
              onPressed: _loading ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ] else
            IconButton(
              tooltip: 'Export PDF',
              onPressed: _loading ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
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
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 8 : 12,
              compact ? 12 : 16,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _employeeOnly
                      ? 'I tuoi corsi D.Lgs. 81/08 con data programmazione impostata dall’amministrazione.'
                      : 'Corsi D.Lgs. 81/08 con data programmazione impostata dall’amministrazione.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (!_employeeOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ordinati per inizio programmazione (dal) più vicino in alto. '
                    'Data prog. rossa entro 2 giorni; lampeggiante se il corso è oggi o in corso. '
                    'Intervallo su più giorni evidenziato in verde. '
                    'Dopo 2 giorni dalla fine del corso la riga si rimuove automaticamente.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              8,
              compact ? 12 : 16,
              4,
            ),
            child: TextField(
              decoration: InputDecoration(
                isDense: compact,
                prefixIcon: const Icon(Icons.search),
                hintText: _employeeOnly
                    ? 'Cerca corso, ente, modalità…'
                    : 'Cerca dipendente, corso, ente, modalità…',
                border: const OutlineInputBorder(),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _search = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _employeeOnly &&
                          (_ownPersonaleId == null || _ownPersonaleId!.isEmpty)
                      ? 'Anagrafica non collegata: impossibile mostrare le programmazioni.'
                      : _rows.isEmpty
                          ? (_employeeOnly
                              ? 'Nessun corso programmato a tuo nome.\n'
                                  'In «Vista dipendente» vedi solo i corsi della tua anagrafica; '
                                  'usa «Torna ad Admin» per la griglia completa.'
                              : 'Nessun corso con data programmazione.')
                          : 'Nessun risultato per la ricerca.',
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: compact
                    ? ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                        itemCount: items.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${items.length} corsi programmati',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (!_employeeOnly) _exportButtonsRow(),
                                ],
                              ),
                            );
                          }
                          return _courseCard(items[i - 1], i - 1);
                        },
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '${items.length} corsi programmati',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              _exportButtonsRow(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _desktopTable(items),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgDateSlashFormatter extends TextInputFormatter {
  const _ProgDateSlashFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final max = digits.length > 8 ? digits.substring(0, 8) : digits;
    final b = StringBuffer();
    for (var i = 0; i < max.length; i++) {
      b.write(max[i]);
      if (i == 1 || i == 3) {
        if (i != max.length - 1) b.write('/');
      }
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
