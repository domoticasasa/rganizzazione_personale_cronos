import 'dart:async';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/confirm_sound_service.dart';
import '../services/formazione_dlgs_strutture_service.dart';
import '../services/notification_sender.dart';
import '../services/supabase_service.dart';
import '../widgets/dlgs_struttura_selector.dart';
import 'admin_formazione_dlgs_strutture_page.dart';
import '../utils/date_formatters.dart';
import '../utils/dt_view_role.dart';
import '../utils/roles.dart' show canManageFormazioneDlgs81Griglia, hasDtWorkflowRole;
import '../utils/users_directory.dart';
import '../utils/field_timestamps.dart';
import '../utils/formazione_programmazione_dates.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/linked_scrollbar.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../Mobile/admin_gestione_dipendenti_mobile.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../utils/responsive.dart';
import 'admin_gestione_dipendenti_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminFormazionePage extends StatefulWidget {
  final bool readOnly;
  final String? role;
  final String tableName;
  final String pageTitle;
  final bool excelLikeRfiHeaders;
  const AdminFormazionePage({
    super.key,
    this.readOnly = false,
    this.role,
    this.tableName = 'formazione_corsi',
    this.pageTitle = 'Admin - Formazione D.Lgs. 81/08',
    this.excelLikeRfiHeaders = false,
  });

  @override
  State<AdminFormazionePage> createState() => _AdminFormazionePageState();
}

class _AdminFormazionePageState extends State<AdminFormazionePage> {
  bool get _isRfiExcelLike => widget.excelLikeRfiHeaders;
  String? _resolvedRole;

  bool get _effectiveReadOnly {
    if (widget.readOnly) return true;
    if (widget.tableName != 'formazione_corsi') return false;
    final role = DtViewRoleScope.resolveForPage(
      context,
      (widget.role ?? _resolvedRole ?? '').trim().isEmpty
          ? null
          : widget.role ?? _resolvedRole,
    );
    if (role.isEmpty) return true;
    return !canManageFormazioneDlgs81Griglia(role);
  }

  String get _effectiveRoleForUi => DtViewRoleScope.resolveForPage(
        context,
        (widget.role ?? _resolvedRole ?? '').trim().isEmpty
            ? null
            : widget.role ?? _resolvedRole,
      );

  bool _loading = true;
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dlgsStrutture = <Map<String, dynamic>>[];
  final Map<String, String> _personaleNameById = <String, String>{};
  final Map<String, String> _auditUserNamesByUuid = <String, String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _leftVerticalCtrl = ScrollController();
  final ScrollController _rightVerticalCtrl = ScrollController();
  final ScrollController _headerHorizontalCtrl = ScrollController();
  final ScrollController _bodyHorizontalCtrl = ScrollController();
  bool _syncingVertical = false;
  bool _syncingHorizontal = false;
  Timer? _blinkTimer;
  bool _blinkOn = false;
  String? _focusCourseGroup;
  String? _focusPersonaleId;
  String? _focusRowId;
  String? _newCourseBadgeGroup;
  Timer? _newCourseBadgeTimer;
  int _draftCourseSeq = 0;
  final List<String> _draftCourseGroups = <String>[];
  final Set<String> _localEmptyCourseGroups = <String>{};
  bool _autoCleanupRunning = false;
  String _expiryFilter = 'all'; // all | expired | 60 | 45 | 30
  static const List<String> _courseGroupOrder = <String>[
    'ASR ART.37 RISCHIO ALTO',
    'ANTINCENDIO',
    'ATTESTATO VVF',
    'PREPOSTO',
    'PRIMO SOCCORSO',
    'PES PAV PEI',
    'DPI III',
    'PLE',
    'O.M.S. TERNE ESCAVATORI',
    'SEGNALETICA STRADALE',
    'GRU SU AUTOCARRO',
    'CARRELLI SEMOVENTI',
    'BOBCAT',
    'CARRELLI ELEVATORI',
    'RLS',
    'FIBRA',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.role == null && widget.tableName == 'formazione_corsi') {
      _resolveCurrentUserRole();
    }
    _leftVerticalCtrl.addListener(_syncVerticalFromLeft);
    _rightVerticalCtrl.addListener(_syncVerticalFromRight);
    _headerHorizontalCtrl.addListener(_syncHorizontalFromHeader);
    _bodyHorizontalCtrl.addListener(_syncHorizontalFromBody);
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _load();
  }

  void _syncVerticalFromLeft() {
    if (_syncingVertical || !_rightVerticalCtrl.hasClients || !_leftVerticalCtrl.hasClients) return;
    _syncingVertical = true;
    _rightVerticalCtrl.jumpTo(
      _leftVerticalCtrl.offset.clamp(
        _rightVerticalCtrl.position.minScrollExtent,
        _rightVerticalCtrl.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  void _syncVerticalFromRight() {
    if (_syncingVertical || !_leftVerticalCtrl.hasClients || !_rightVerticalCtrl.hasClients) return;
    _syncingVertical = true;
    _leftVerticalCtrl.jumpTo(
      _rightVerticalCtrl.offset.clamp(
        _leftVerticalCtrl.position.minScrollExtent,
        _leftVerticalCtrl.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  void _syncHorizontalFromHeader() {
    if (_syncingHorizontal || !_bodyHorizontalCtrl.hasClients || !_headerHorizontalCtrl.hasClients) {
      return;
    }
    _syncingHorizontal = true;
    _bodyHorizontalCtrl.jumpTo(
      _headerHorizontalCtrl.offset.clamp(
        _bodyHorizontalCtrl.position.minScrollExtent,
        _bodyHorizontalCtrl.position.maxScrollExtent,
      ),
    );
    _syncingHorizontal = false;
  }

  void _syncHorizontalFromBody() {
    if (_syncingHorizontal || !_headerHorizontalCtrl.hasClients || !_bodyHorizontalCtrl.hasClients) {
      return;
    }
    _syncingHorizontal = true;
    _headerHorizontalCtrl.jumpTo(
      _bodyHorizontalCtrl.offset.clamp(
        _headerHorizontalCtrl.position.minScrollExtent,
        _headerHorizontalCtrl.position.maxScrollExtent,
      ),
    );
    _syncingHorizontal = false;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _leftVerticalCtrl
      ..removeListener(_syncVerticalFromLeft)
      ..dispose();
    _rightVerticalCtrl
      ..removeListener(_syncVerticalFromRight)
      ..dispose();
    _headerHorizontalCtrl
      ..removeListener(_syncHorizontalFromHeader)
      ..dispose();
    _bodyHorizontalCtrl
      ..removeListener(_syncHorizontalFromBody)
      ..dispose();
    _blinkTimer?.cancel();
    _newCourseBadgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportExcel() async {
    try {
      final q = _searchCtrl.text.trim().toLowerCase();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final courseHit = _courseGroupsMatchingQuery(q);
      final filtered = _visibleRows(q, today, courseGroupsHit: courseHit);
      if (filtered.isEmpty) {
        _snack('Nessun dato da esportare', error: true);
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Formazione_DLGS_81_08'];
      sheet.appendRow([
        'Dipendente',
        'Corso',
        'Data attestato',
        'Scadenza attestato',
        'Data programmazione',
        'Orario',
        'Modalita',
        'Struttura/Link',
      ]);
      for (final r in filtered) {
        final pid = (r['personale_id'] ?? '').toString();
        sheet.appendRow([
          _personaleNameById[pid] ?? pid,
          (r['corso'] ?? '').toString(),
          _fmtDateOnly(r['data_attestato']),
          _fmtDateOnly(r['scadenza_attestato']),
          _fmtDateOnly(r['prima_data']),
          (r['orario'] ?? '').toString(),
          (r['modalita'] ?? '').toString(),
          (r['struttura_link'] ?? '').toString(),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: widget.pageTitle,
        bytes: bytes,
      );
      if (!saved) return;
      _snack('Export Excel completato: ${ExcelExportHelper.lastSavedPath ?? ''}');
    } catch (e) {
      _snack('Errore export Excel: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
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
      final personaleRes = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name')
          .order('full_name');
      final personaleRows =
          await UsersDirectory.visiblePersonale(personaleRes as List);
      _personaleNameById
        ..clear()
        ..addEntries(personaleRows.map((r) {
          return MapEntry(
            (r['id_uuid'] ?? '').toString(),
            (r['full_name'] ?? '').toString(),
          );
        }));

      // In vista DT read-only, prova ad allargare i nominativi con fallback da users
      // per garantire la visibilita di tutti i dipendenti anche senza righe formazione.
      if (widget.readOnly) {
        try {
          final usersRes = await SupabaseService.client
              .from('users')
              .select('id_uuid, full_name, username, role')
              .inFilter('role', ['dipendente', 'user', 'caposquadra']);
          for (final e in (usersRes as List)) {
            final r = Map<String, dynamic>.from(e as Map);
            final id = (r['id_uuid'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            final fullName = (r['full_name'] ?? '').toString().trim();
            final username = (r['username'] ?? '').toString().trim();
            final label = fullName.isNotEmpty ? fullName : username;
            if (label.isEmpty) continue;
            if (UsersDirectory.isHiddenServicePersonaleName(label)) continue;
            _personaleNameById.putIfAbsent(id, () => label);
          }
        } catch (_) {
          // Fallback non bloccante.
        }
      }

      if (widget.tableName == 'formazione_corsi') {
        _dlgsStrutture = await FormazioneDlgsStruttureService.loadAll();
      }

      final corsiRes = await SupabaseService.client
          .from(widget.tableName)
          .select()
          .order('scadenza_attestato', ascending: true);
      final loadedRows =
          (corsiRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final dedupedRows = await _cleanupDuplicateRows(loadedRows);

      _rows
        ..clear()
        ..addAll(dedupedRows);
      final auditIds = <String>{};
      for (final r in _rows) {
        mergeFieldTimestampActorUuids(r, auditIds);
      }
      _auditUserNamesByUuid
        ..clear()
        ..addAll(await loadUserNamesByUuid(auditIds));
    } catch (e) {
      _snack('Errore caricamento formazione: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dedupeKeyForRow(Map<String, dynamic> row) {
    final pid = (row['personale_id'] ?? '').toString().trim();
    final corso = (row['corso'] ?? '')
        .toString()
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '$pid|$corso';
  }

  Future<List<Map<String, dynamic>>> _cleanupDuplicateRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (_autoCleanupRunning || rows.isEmpty) return rows;
    _autoCleanupRunning = true;
    try {
      final Map<String, Map<String, dynamic>> keptByKey = <String, Map<String, dynamic>>{};
      final List<dynamic> idsToDelete = <dynamic>[];

      for (final row in rows) {
        final rowId = row['id'];
        final key = _dedupeKeyForRow(row);
        final hasKey = key.split('|').every((p) => p.trim().isNotEmpty);
        if (!hasKey || rowId == null) {
          // Se mancano chiavi tecniche non deduplichiamo per evitare eliminazioni errate.
          continue;
        }
        final existing = keptByKey[key];
        if (existing == null) {
          keptByKey[key] = row;
          continue;
        }
        if (_preferRow(row, existing)) {
          final existingId = existing['id'];
          if (existingId != null) idsToDelete.add(existingId);
          keptByKey[key] = row;
        } else {
          idsToDelete.add(rowId);
        }
      }

      if (idsToDelete.isEmpty) return rows;

      const chunkSize = 200;
      for (int i = 0; i < idsToDelete.length; i += chunkSize) {
        final end = (i + chunkSize < idsToDelete.length) ? i + chunkSize : idsToDelete.length;
        final chunk = idsToDelete.sublist(i, end);
        await SupabaseService.client.from(widget.tableName).delete().inFilter('id', chunk);
      }

      final deleteSet = idsToDelete.map((e) => e.toString()).toSet();
      final cleaned = rows.where((r) => !deleteSet.contains((r['id'] ?? '').toString())).toList();
      return cleaned;
    } catch (_) {
      // Non bloccare l'uso pagina se la pulizia non riesce.
      return rows;
    } finally {
      _autoCleanupRunning = false;
    }
  }

  DateTime? _parseDate(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final p = t.split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final y = int.tryParse(p[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  String _toIso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    // Evita conversioni timezone (toIso8601String) che possono spostare il giorno.
    return '$y-$m-$day';
  }

  /// Converte testo gg/mm/aaaa (o ISO) in `YYYY-MM-DD` per Supabase; vuoto → `null`.
  String? _dateFieldToIso(String text) {
    final fromSlash = _parseDate(text);
    if (fromSlash != null) return _toIso(fromSlash);
    return parseFlexibleDateToIsoDate(text);
  }

  static const _formazioneSaveSelect =
      'id, personale_id, corso, ente, primo_rilascio_aggiornamento, '
      'data_attestato, scadenza_attestato, prima_data, seconda_data, '
      'oda, orario, modalita, struttura_dlgs_id, struttura_nome, '
      'struttura_indirizzo, struttura_email, struttura_link, note, updated_at';

  Map<String, dynamic> _strutturaPayloadFromSelection({
    required bool isOnline,
    required Map<String, dynamic>? selected,
    required String onlineLink,
  }) {
    if (isOnline) {
      return <String, dynamic>{
        ...FormazioneDlgsStruttureService.clearCorsoStrutturaPayload(),
        'struttura_link':
            onlineLink.trim().isEmpty ? null : onlineLink.trim(),
      };
    }
    if (selected != null) {
      final m = FormazioneDlgsStruttureService.fieldsFromStruttura(selected);
      return <String, dynamic>{
        'struttura_dlgs_id': m['struttura_dlgs_id']!.isEmpty
            ? null
            : m['struttura_dlgs_id'],
        'struttura_nome':
            m['struttura_nome']!.isEmpty ? null : m['struttura_nome'],
        'struttura_indirizzo': m['struttura_indirizzo']!.isEmpty
            ? null
            : m['struttura_indirizzo'],
        'struttura_email':
            m['struttura_email']!.isEmpty ? null : m['struttura_email'],
        'struttura_link':
            m['struttura_link']!.isEmpty ? null : m['struttura_link'],
      };
    }
    return FormazioneDlgsStruttureService.clearCorsoStrutturaPayload();
  }

  void _patchLocalRowFromPayload(int rowId, Map<String, dynamic> payload) {
    final idx = _rows.indexWhere((r) => (r['id'] ?? '').toString() == rowId.toString());
    if (idx < 0) return;
    final merged = Map<String, dynamic>.from(_rows[idx]);
    for (final e in payload.entries) {
      if (e.key == 'updated_at') continue;
      merged[e.key] = e.value;
    }
    merged['updated_at'] = payload['updated_at'] ?? supabaseNowIsoUtc();
    _rows[idx] = merged;
  }

  String _fmtDateOnly(dynamic value) => formatDateDdMmYyyy(value);

  Future<void> _openEditor({
    Map<String, dynamic>? current,
    String? initialPersonaleId,
    String? initialCorso,
  }) async {
    if (_effectiveReadOnly) return;
    final personaleId = ValueNotifier<String>((current?['personale_id'] ?? '').toString());
    if (personaleId.value.isEmpty && (initialPersonaleId ?? '').isNotEmpty) {
      personaleId.value = initialPersonaleId!;
    }
    final corsoCtrl = TextEditingController(
      text: (current?['corso'] ?? initialCorso ?? '').toString(),
    );
    final corsoValue = ValueNotifier<String>(corsoCtrl.text.trim());
    final enteCtrl = TextEditingController(text: (current?['ente'] ?? '').toString());
    final tipoValue = ValueNotifier<String>(
      (current?['primo_rilascio_aggiornamento'] ?? '').toString().trim(),
    );
    final odaCtrl = TextEditingController(text: (current?['oda'] ?? '').toString());
    final orarioCtrl = TextEditingController(text: (current?['orario'] ?? '').toString());
    final modalitaValue = ValueNotifier<String>((current?['modalita'] ?? '').toString().trim());
    final strutturaIdNotifier = ValueNotifier<String?>(
      (current?['struttura_dlgs_id'] ?? '').toString().trim().isEmpty
          ? null
          : (current?['struttura_dlgs_id'] ?? '').toString().trim(),
    );
    final strutturaLinkCtrl = TextEditingController(
      text: (current?['struttura_link'] ?? '').toString(),
    );
    final noteCtrl = TextEditingController(text: (current?['note'] ?? '').toString());
    final dataAttCtrl =
        TextEditingController(text: formatDateDdMmYyyy(current?['data_attestato']));
    final scadenzaCtrl =
        TextEditingController(text: formatDateDdMmYyyy(current?['scadenza_attestato']));
    final programmazioneDalCtrl = TextEditingController(
      text: formatDateDdMmYyyy(current?['prima_data']),
    );
    final programmazioneAlCtrl = TextEditingController(
      text: formatDateDdMmYyyy(current?['seconda_data']),
    );

    Future<void> pickDipendente() async {
      final all = _personaleNameById.entries.toList()
        ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
      final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final q = ValueNotifier<String>('');
          return AlertDialog(
            title: const Text('Seleziona dipendente'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: ValueListenableBuilder<String>(
                valueListenable: q,
                builder: (_, query, _) {
                  final qq = query.trim().toLowerCase();
                  final filtered = all.where((e) => e.value.toLowerCase().contains(qq)).toList();
                  return Column(
                    children: [
                      TextField(
                        autofocus: true,
                        onChanged: (v) => q.value = v,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cerca dipendente',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return ListTile(
                              dense: true,
                              title: Text(e.value),
                              onTap: () => Navigator.of(ctx).pop(e.key),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
            ],
          );
        },
      );
      if (chosen != null && chosen.isNotEmpty) {
        personaleId.value = chosen;
      }
    }

    Future<void> pickCorso() async {
      final allCourses = _rows
          .map((r) => (r['corso'] ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final q = ValueNotifier<String>('');
          return AlertDialog(
            title: const Text('Seleziona corso'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: ValueListenableBuilder<String>(
                valueListenable: q,
                builder: (_, query, _) {
                  final qq = query.trim().toLowerCase();
                  final filtered = allCourses.where((c) => c.toLowerCase().contains(qq)).toList();
                  return Column(
                    children: [
                      TextField(
                        autofocus: true,
                        onChanged: (v) => q.value = v,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cerca corso',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final customCtrl = TextEditingController();
                            final custom = await showDialog<String>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Nuovo corso'),
                                content: TextField(
                                  controller: customCtrl,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Nome corso',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx),
                                    child: const Text('Annulla'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dctx, customCtrl.text.trim()),
                                    child: const Text('Usa'),
                                  ),
                                ],
                              ),
                            );
                            if (custom != null && custom.trim().isNotEmpty) {
                              Navigator.of(ctx).pop(custom.trim());
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Nuovo corso'),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return ListTile(
                              dense: true,
                              title: Text(c),
                              onTap: () => Navigator.of(ctx).pop(c),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
            ],
          );
        },
      );
      if (chosen != null && chosen.trim().isNotEmpty) {
        final v = chosen.trim();
        corsoCtrl.text = v;
        corsoValue.value = v;
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current == null ? 'Nuovo corso formazione' : 'Modifica corso formazione'),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: personaleId,
                  builder: (_, pid, _) {
                    final selectedName = _personaleNameById[pid] ?? '';
                    return InkWell(
                      onTap: pickDipendente,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        isEmpty: selectedName.isEmpty,
                        decoration: const InputDecoration(
                          labelText: 'Dipendente',
                          hintText: 'Seleziona dipendente',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: corsoValue,
                  builder: (_, selectedCourse, _) {
                    return InkWell(
                      onTap: pickCorso,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        isEmpty: selectedCourse.isEmpty,
                        decoration: const InputDecoration(
                          labelText: 'Corso',
                          hintText: 'Seleziona corso',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedCourse,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: enteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ente',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: tipoValue,
                  builder: (_, value, _) {
                    final selected = (value == 'PRIMO RILASCIO' || value == 'AGGIORNAMENTO')
                        ? value
                        : null;
                    return DropdownButtonFormField<String>(
                      initialValue: selected,
                      decoration: const InputDecoration(
                        labelText: 'Primo rilascio / Aggiornamento',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'PRIMO RILASCIO', child: Text('Primo rilascio')),
                        DropdownMenuItem(value: 'AGGIORNAMENTO', child: Text('Aggiornamento')),
                      ],
                      onChanged: (v) => tipoValue.value = (v ?? '').trim(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dataAttCtrl,
                        keyboardType: TextInputType.datetime,
                        inputFormatters: const [_DateSlashFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Data attestato (gg/mm/aaaa)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: scadenzaCtrl,
                        keyboardType: TextInputType.datetime,
                        inputFormatters: const [_DateSlashFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Scadenza attestato (gg/mm/aaaa)',
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
                        controller: programmazioneDalCtrl,
                        keyboardType: TextInputType.datetime,
                        inputFormatters: const [_DateSlashFormatter()],
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
                        keyboardType: TextInputType.datetime,
                        inputFormatters: const [_DateSlashFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Data programmazione al (gg/mm/aaaa)',
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
                    final selected = (value.toLowerCase() == 'online' ||
                            value.toLowerCase() == 'in presenza')
                        ? value
                        : null;
                    return DropdownButtonFormField<String>(
                      initialValue: selected,
                      decoration: const InputDecoration(
                        labelText: 'Modalita',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Online', child: Text('Online')),
                        DropdownMenuItem(value: 'In presenza', child: Text('In presenza')),
                      ],
                      onChanged: (v) => modalitaValue.value = (v ?? '').trim(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: modalitaValue,
                  builder: (_, value, _) {
                    final isOnline = value.toLowerCase() == 'online';
                    if (widget.tableName != 'formazione_corsi') {
                      return TextField(
                        controller: strutturaLinkCtrl,
                        decoration: InputDecoration(
                          labelText: isOnline
                              ? 'Link corso (online)'
                              : 'Struttura (in presenza)',
                          border: const OutlineInputBorder(),
                        ),
                      );
                    }
                    return ValueListenableBuilder<String?>(
                      valueListenable: strutturaIdNotifier,
                      builder: (_, _, _) {
                        return DlgsStrutturaSelector(
                          strutture: _dlgsStrutture,
                          selectedId: strutturaIdNotifier.value,
                          onlineMode: isOnline,
                          onlineLinkController: strutturaLinkCtrl,
                          onChanged: isOnline
                              ? null
                              : (s) {
                                  strutturaIdNotifier.value =
                                      s == null ? null : (s['id_uuid'] ?? '').toString();
                                  if (s != null) {
                                    strutturaLinkCtrl.text =
                                        (s['maps_link'] ?? '').toString();
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
          if (current != null)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (dctx) => AlertDialog(
                    title: const Text('Conferma eliminazione'),
                    content: const Text('Vuoi eliminare questo corso formazione?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, false),
                        child: const Text('Annulla'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        child: const Text('Elimina'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  final deleteId = int.tryParse((current['id'] ?? '').toString());
                  final deletePid = (current['personale_id'] ?? '').toString().trim();
                  final deleteCorso = (current['corso'] ?? '').toString().trim();
                  await SupabaseService.client
                      .from(widget.tableName)
                      .delete()
                      .eq('id', current['id']);
                  if (deleteId != null && deletePid.isNotEmpty) {
                    await _notifyEmployeeFormazioneChange(
                      personaleId: deletePid,
                      formazioneId: deleteId,
                      action: 'delete',
                      corso: deleteCorso.isEmpty ? 'Corso formazione' : deleteCorso,
                    );
                  }
                  if (!mounted) return;
                  Navigator.pop(ctx, false);
                  _snack('Corso formazione eliminato');
                  await _load();
                } catch (e) {
                  _snack('Errore eliminazione corso: $e', error: true);
                }
              },
              child: const Text('Elimina'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );

    if (saved != true) return;
    final pid = personaleId.value.trim();
    if (pid.isEmpty || corsoCtrl.text.trim().isEmpty) {
      _snack('Dipendente e corso sono obbligatori', error: true);
      return;
    }
    final norm = normalizeProgrammazioneIso(
      dalText: programmazioneDalCtrl.text,
      alText: programmazioneAlCtrl.text,
    );
    if (norm.error != null) {
      _snack(norm.error!, error: true);
      return;
    }
    final payload = <String, dynamic>{
      'personale_id': pid,
      'corso': corsoCtrl.text.trim(),
      'ente': enteCtrl.text.trim(),
      'primo_rilascio_aggiornamento': tipoValue.value.trim(),
      'data_attestato': _dateFieldToIso(dataAttCtrl.text),
      'scadenza_attestato': _dateFieldToIso(scadenzaCtrl.text),
      'prima_data': norm.primaIso,
      'seconda_data': norm.secondaIso,
      'oda': odaCtrl.text.trim(),
      'orario': orarioCtrl.text.trim(),
      'modalita': modalitaValue.value.trim(),
      ..._strutturaPayloadFromSelection(
        isOnline: modalitaValue.value.trim().toLowerCase() == 'online',
        selected: FormazioneDlgsStruttureService.findById(
          _dlgsStrutture,
          strutturaIdNotifier.value,
        ),
        onlineLink: strutturaLinkCtrl.text,
      ),
      'note': noteCtrl.text.trim(),
      'updated_at': supabaseNowIsoUtc(),
    };
    finalizeFormazioneCorsiPayload(payload);
    try {
      final saveStartedAt = supabaseNowIsoUtc();
      final justSavedGroup = _normalizeCourseGroup(corsoCtrl.text.trim());
      Map<String, dynamic>? savedRow;
      if (current == null) {
        // Evita la proliferazione di righe duplicate per stesso dipendente+corso:
        // se esiste già una riga, aggiorna quella più recente.
        final existing = await SupabaseService.client
            .from(widget.tableName)
            .select('id')
            .eq('personale_id', pid)
            .eq('corso', corsoCtrl.text.trim())
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (existing != null && existing['id'] != null) {
          final updateRes = await SupabaseService.client
              .from(widget.tableName)
              .update(payload)
              .eq('id', existing['id'])
              .select(_formazioneSaveSelect);
          if (updateRes.isNotEmpty) {
            savedRow = Map<String, dynamic>.from(updateRes.first as Map);
          }
        } else {
          final insertRes = await SupabaseService.client
              .from(widget.tableName)
              .insert(payload)
              .select(_formazioneSaveSelect);
          if (insertRes.isNotEmpty) {
            savedRow = Map<String, dynamic>.from(insertRes.first as Map);
          }
        }
      } else {
        final updateRes = await SupabaseService.client
            .from(widget.tableName)
            .update(payload)
            .eq('id', current['id'])
            .select(_formazioneSaveSelect);
        if (updateRes.isNotEmpty) {
          savedRow = Map<String, dynamic>.from(updateRes.first as Map);
        }
      }
      // Verifica immediata dal DB (nella stessa sessione utente) che il record sia presente.
      savedRow ??= await SupabaseService.client
          .from(widget.tableName)
          .select(_formazioneSaveSelect)
          .eq('personale_id', pid)
          .eq('corso', corsoCtrl.text.trim())
          .gte('updated_at', saveStartedAt)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (savedRow == null) {
        _snack(
          'Salvataggio non confermato su Supabase (nessun aggiornamento recente trovato).',
          error: true,
        );
        return;
      }
      final confirmedRow = savedRow;
      final savedId = int.tryParse((confirmedRow['id'] ?? '').toString());
      if (savedId != null) {
        _patchLocalRowFromPayload(savedId, payload);
      }
      if (mounted) {
        setState(() {
          _expiryFilter = 'all';
          _focusPersonaleId = pid;
          _focusRowId = (confirmedRow['id'] ?? '').toString();
          _focusCourseGroup = justSavedGroup;
          _newCourseBadgeGroup = justSavedGroup;
          _localEmptyCourseGroups.removeWhere(
            (g) => g.trim().toLowerCase() == justSavedGroup.trim().toLowerCase(),
          );
        });
      }
      await _load();
      _snack(current == null ? 'Corso formazione creato' : 'Corso formazione aggiornato');
      if (savedId != null) {
        await _notifyEmployeeFormazioneChange(
          personaleId: pid,
          formazioneId: savedId,
          action: current == null ? 'create' : 'update',
          corso: corsoCtrl.text.trim(),
        );
      }
      _newCourseBadgeTimer?.cancel();
      _newCourseBadgeTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _newCourseBadgeGroup = null);
      });
    } catch (e) {
      _snack('Errore salvataggio formazione: $e', error: true);
    }
  }

  String _normalizeCourseGroup(String corso) {
    final raw = corso.trim();
    if (_isRfiExcelLike || widget.tableName != 'formazione_corsi') return raw;
    if (raw.isEmpty) return 'ALTRO';
    final c = raw.toUpperCase();
    // Mapping solo su corrispondenze esplicite, così i corsi custom restano visibili.
    if (c == 'ASR ART.37 RISCHIO ALTO') return 'ASR ART.37 RISCHIO ALTO';
    if (c == 'ANTINCENDIO') return 'ANTINCENDIO';
    if (c == 'ATTESTATO VVF' || c == 'VVF') return 'ATTESTATO VVF';
    if (c == 'PREPOSTO') return 'PREPOSTO';
    if (c == 'PRIMO SOCCORSO') return 'PRIMO SOCCORSO';
    if (c == 'PES PAV PEI' || c == 'PES/PAV/PEI') return 'PES PAV PEI';
    if (c == 'DPI III') return 'DPI III';
    if (c == 'PLE') return 'PLE';
    if (c == 'O.M.S. TERNE ESCAVATORI') return 'O.M.S. TERNE ESCAVATORI';
    if (c == 'SEGNALETICA STRADALE') return 'SEGNALETICA STRADALE';
    if (c == 'GRU SU AUTOCARRO') return 'GRU SU AUTOCARRO';
    if (c == 'CARRELLI SEMOVENTI') return 'CARRELLI SEMOVENTI';
    if (c == 'BOBCAT') return 'BOBCAT';
    if (c == 'CARRELLI ELEVATORI') return 'CARRELLI ELEVATORI';
    if (c == 'RLS') return 'RLS';
    if (c == 'FIBRA') return 'FIBRA';
    return raw;
  }

  /// Tutti i gruppi corso presenti in tabella (ordine canonico + custom).
  List<String> _allCourseGroups() {
    final discovered = <String>{};
    for (final r in _rows) {
      final g = _normalizeCourseGroup((r['corso'] ?? '').toString());
      if (g.isNotEmpty) discovered.add(g);
    }
    if (_isRfiExcelLike || widget.tableName != 'formazione_corsi') {
      return discovered.toList()..sort();
    }
    return <String>[
      ..._courseGroupOrder.where(discovered.contains),
      ...discovered.where((g) => !_courseGroupOrder.contains(g)).toList()..sort(),
    ];
  }

  /// Gruppi corso il cui nome contiene [q] (es. «dpi» → «DPI III»).
  List<String> _courseGroupsMatchingQuery(String q) {
    final ql = q.trim().toLowerCase();
    if (ql.isEmpty) return const [];
    return _allCourseGroups()
        .where((g) => g.toLowerCase().contains(ql))
        .toList(growable: false);
  }

  bool _rowMatchesSearch(Map<String, dynamic> r, String q) {
    if (q.isEmpty) return true;
    final pid = (r['personale_id'] ?? '').toString();
    final personale = _personaleNameById[pid]?.toLowerCase() ?? '';
    final group = _normalizeCourseGroup((r['corso'] ?? '').toString()).toLowerCase();
    final corso = (r['corso'] ?? '').toString().toLowerCase();
    return personale.contains(q) || group.contains(q) || corso.contains(q);
  }

  /// True se il dipendente ha già il corso (attestato o scadenza), non solo la prenotazione.
  bool _rowHasAttestato(Map<String, dynamic> r) {
    final att = (r['data_attestato'] ?? '').toString().trim();
    final scad = (r['scadenza_attestato'] ?? '').toString().trim();
    return DateTime.tryParse(att) != null || DateTime.tryParse(scad) != null;
  }

  /// Dipendenti da mostrare in base alla ricerca.
  Set<String> _personIdsMatchingSearch(
    String q, {
    List<String> courseGroupsHit = const [],
  }) {
    if (q.isEmpty) return {};
    final ids = <String>{};

    // Filtro per tipo corso: solo chi ha già l'attestato, non chi è solo prenotato.
    if (courseGroupsHit.isNotEmpty) {
      final targets = courseGroupsHit.map((g) => g.toLowerCase()).toSet();
      for (final r in _rows) {
        final group =
            _normalizeCourseGroup((r['corso'] ?? '').toString()).toLowerCase();
        if (!targets.contains(group)) continue;
        if (!_rowHasAttestato(r)) continue;
        final pid = (r['personale_id'] ?? '').toString();
        if (pid.isNotEmpty) ids.add(pid);
      }
      return ids;
    }

    for (final r in _rows) {
      if (!_rowMatchesSearch(r, q)) continue;
      final pid = (r['personale_id'] ?? '').toString();
      if (pid.isNotEmpty) ids.add(pid);
    }
    return ids;
  }

  bool _rowMatchesExpiryFilter(Map<String, dynamic> r, DateTime today) {
    if (_expiryFilter == 'all') return true;
    final dt = DateTime.tryParse((r['scadenza_attestato'] ?? '').toString());
    if (dt == null) return false;
    final expiry = DateTime(dt.year, dt.month, dt.day);
    if (_expiryFilter == 'expired') return expiry.isBefore(today);
    final maxDays = int.tryParse(_expiryFilter) ?? 60;
    final limit = today.add(Duration(days: maxDays));
    return !expiry.isBefore(today) && !expiry.isAfter(limit);
  }

  /// Righe visibili: per tipo corso mantiene tutti i corsi del dipendente selezionato.
  List<Map<String, dynamic>> _visibleRows(
    String q,
    DateTime today, {
    List<String> courseGroupsHit = const [],
  }) {
    final matchingPids = _personIdsMatchingSearch(
      q,
      courseGroupsHit: courseGroupsHit,
    );
    final courseTargets = courseGroupsHit.map((g) => g.toLowerCase()).toSet();
    return _rows.where((r) {
      final pid = (r['personale_id'] ?? '').toString();
      if (q.isNotEmpty && !matchingPids.contains(pid)) return false;
      if (courseTargets.isNotEmpty) {
        final group =
            _normalizeCourseGroup((r['corso'] ?? '').toString()).toLowerCase();
        if (!courseTargets.contains(group)) return false;
        if (!_rowHasAttestato(r)) return false;
      }
      return _rowMatchesExpiryFilter(r, today);
    }).toList(growable: false);
  }

  bool _isDraftGroup(String group) => group.startsWith('__DRAFT__');

  String _groupHeaderTitle(String group) => _isDraftGroup(group) ? '' : group;

  String _newDraftGroupName() {
    _draftCourseSeq++;
    return '__DRAFT__$_draftCourseSeq';
  }

  void _addDraftColumn() {
    final draft = _newDraftGroupName();
    setState(() {
      _draftCourseGroups.insert(0, draft);
      _focusCourseGroup = draft;
      _newCourseBadgeGroup = draft;
    });
    _newCourseBadgeTimer?.cancel();
    _newCourseBadgeTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _newCourseBadgeGroup = null);
    });
  }

  List<int> _idsForCourseGroup(String group) {
    final target = group.trim().toLowerCase();
    return _rows
        .where((r) {
          final g = _normalizeCourseGroup((r['corso'] ?? '').toString());
          return g.trim().toLowerCase() == target;
        })
        .map((r) => r['id'])
        .whereType<int>()
        .toList(growable: false);
  }

  Future<void> _renameCourseGroup(String group) async {
    final ids = _idsForCourseGroup(group);
    final ctrl = TextEditingController(text: _isDraftGroup(group) ? '' : group);
    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina colonna corso'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nuovo nome corso',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    final newName = (nextName ?? '').trim();
    if (newName.isEmpty || newName == group) return;
    if (ids.isEmpty && _isDraftGroup(group)) {
      setState(() {
        final idx = _draftCourseGroups.indexOf(group);
        if (idx >= 0) _draftCourseGroups.removeAt(idx);
        _localEmptyCourseGroups.add(newName);
        _focusCourseGroup = newName;
        _newCourseBadgeGroup = newName;
      });
      _newCourseBadgeTimer?.cancel();
      _newCourseBadgeTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _newCourseBadgeGroup = null);
      });
      _snack('Colonna rinominata');
      return;
    }
    if (ids.isEmpty) {
      _snack('Nessun record trovato per il corso selezionato', error: true);
      return;
    }
    try {
      await SupabaseService.client
          .from(widget.tableName)
          .update({'corso': newName, 'updated_at': supabaseNowIsoUtc()})
          .inFilter('id', ids);
      _snack('Colonna "$group" rinominata in "$newName"');
      await _load();
    } catch (e) {
      _snack('Errore rinomina colonna: $e', error: true);
    }
  }

  Future<void> _deleteCourseGroup(String group) async {
    final ids = _idsForCourseGroup(group);
    if (ids.isEmpty && _isDraftGroup(group)) {
      setState(() => _draftCourseGroups.remove(group));
      _snack('Colonna eliminata');
      return;
    }
    if (ids.isEmpty && _localEmptyCourseGroups.contains(group)) {
      setState(() => _localEmptyCourseGroups.remove(group));
      _snack('Colonna eliminata');
      return;
    }
    if (ids.isEmpty) {
      _snack('Nessun record trovato per il corso selezionato', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina colonna corso'),
        content: Text(
          'Vuoi eliminare il corso "$group" per tutti i dipendenti?\n'
          'Record da eliminare: ${ids.length}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from(widget.tableName).delete().inFilter('id', ids);
      _snack('Colonna "$group" eliminata');
      await _load();
    } catch (e) {
      _snack('Errore eliminazione colonna: $e', error: true);
    }
  }

  Future<void> _openCourseColumnActions(String group) async {
    if (_effectiveReadOnly) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rinomina colonna corso'),
              subtitle: Text(group),
              onTap: () {
                Navigator.pop(ctx);
                _renameCourseGroup(group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Elimina colonna corso'),
              subtitle: Text(group),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCourseGroup(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  DateTime _sortDateForRow(Map<String, dynamic> row) {
    final scad = DateTime.tryParse((row['scadenza_attestato'] ?? '').toString());
    if (scad != null) return scad;
    final att = DateTime.tryParse((row['data_attestato'] ?? '').toString());
    if (att != null) return att;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _updatedAtForRow(Map<String, dynamic> row) {
    final updated = DateTime.tryParse((row['updated_at'] ?? '').toString());
    if (updated != null) return updated;
    final created = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (created != null) return created;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _rowCompletenessScore(Map<String, dynamic> row) {
    int score = 0;
    final dataAtt = (row['data_attestato'] ?? '').toString().trim();
    final scad = (row['scadenza_attestato'] ?? '').toString().trim();
    final ente = (row['ente'] ?? '').toString().trim();
    final primo = (row['primo_rilascio_aggiornamento'] ?? '').toString().trim();
    final note = (row['note'] ?? '').toString().trim();
    final progDal = (row['prima_data'] ?? '').toString().trim();
    final progAl = (row['seconda_data'] ?? '').toString().trim();

    if (dataAtt.isNotEmpty) score += 3;
    if (scad.isNotEmpty) score += 4;
    if (ente.isNotEmpty) score += 1;
    if (primo.isNotEmpty) score += 1;
    if (note.isNotEmpty) score += 1;
    if (progDal.isNotEmpty) score += 2;
    if (progAl.isNotEmpty) score += 1;
    return score;
  }

  bool _preferRow(Map<String, dynamic> incoming, Map<String, dynamic> existing) {
    final incomingScore = _rowCompletenessScore(incoming);
    final existingScore = _rowCompletenessScore(existing);
    if (incomingScore > existingScore) return true;
    if (incomingScore < existingScore) return false;

    final incomingUpdated = _updatedAtForRow(incoming);
    final existingUpdated = _updatedAtForRow(existing);
    if (incomingUpdated.isAfter(existingUpdated)) return true;
    if (incomingUpdated.isBefore(existingUpdated)) return false;
    return _sortDateForRow(incoming).isAfter(_sortDateForRow(existing));
  }

  Widget _wrapFieldAudit({
    required Widget child,
    required Map<String, dynamic>? row,
    required String fieldKey,
  }) {
    if (row == null) return child;
    return wrapWithAuditHover(
      child,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _auditUserNamesByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }

  String _attCell(Map<String, dynamic>? row) {
    if (row == null) return '';
    final dataAtt = (row['data_attestato'] ?? '').toString().trim();
    if (dataAtt.isNotEmpty) return _fmtDateOnly(dataAtt);
    final dataCorso = (row['data'] ?? '').toString().trim();
    if (dataCorso.isNotEmpty) return _fmtDateOnly(dataCorso);
    return '';
  }

  int? _daysToExpiry(String scad) {
    final dt = DateTime.tryParse(scad);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day).difference(DateTime.now()).inDays;
  }

  Color _scadBg(String scad) {
    final days = _daysToExpiry(scad);
    if (days == null) return Colors.transparent;
    if (days < 0) {
      return _blinkOn ? Colors.red.shade700.withValues(alpha: 0.42) : Colors.red.shade400.withValues(alpha: 0.28);
    }
    if (days <= 30) return Colors.red.shade300.withValues(alpha: 0.28);
    if (days <= 45) return Colors.orange.shade300.withValues(alpha: 0.30);
    if (days <= 60) return Colors.yellow.shade300.withValues(alpha: 0.32);
    return Colors.green.shade200.withValues(alpha: 0.30);
  }

  TextStyle _scadTextStyle(String scad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = _daysToExpiry(scad);
    if (days == null) {
      return TextStyle(
        fontSize: 12,
        color: isDark ? Colors.white : Colors.black87,
      );
    }
    if (isDark) {
      return TextStyle(
        fontSize: 12,
        fontWeight: days < 0 ? FontWeight.w800 : FontWeight.w700,
        color: Colors.white,
      );
    }
    if (days < 0) {
      return TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: _blinkOn ? Colors.white : Colors.red.shade900,
      );
    }
    if (days <= 30) {
      return TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red.shade900);
    }
    if (days <= 45) {
      return TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade900);
    }
    if (days <= 60) {
      return TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.brown.shade800);
    }
    return TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green.shade900);
  }

  TextStyle _attTextStyle(Map<String, dynamic>? row) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white : Colors.black87,
    );
  }

  Future<void> _notifyEmployeeFormazioneChange({
    required String personaleId,
    required int formazioneId,
    required String action,
    required String corso,
  }) async {
    if (widget.tableName != 'formazione_corsi') return;
    try {
      final act = action.toLowerCase().trim();
      final title =
          act == 'delete' ? 'Corso formazione eliminato' : 'Aggiornamento formazione';
      final message = act == 'delete'
          ? 'Un corso e stato eliminato: $corso'
          : 'Aggiornamento sul corso: $corso';
      await NotificationSender.notifyEmployeeFormazioneChange(
        personaleId: personaleId,
        formazioneId: formazioneId,
        action: act,
        title: title,
        message: message,
      );
    } catch (_) {
      // Non bloccare il flusso principale se la notifica fallisce.
    }
  }

  Future<void> _deleteFormazioneRow(Map<String, dynamic> row) async {
    final deleteId = int.tryParse((row['id'] ?? '').toString());
    final deletePid = (row['personale_id'] ?? '').toString().trim();
    final deleteCorso = (row['corso'] ?? '').toString().trim();
    if (deleteId == null) {
      _snack('Record non valido: id mancante', error: true);
      return;
    }
    try {
      await SupabaseService.client.from(widget.tableName).delete().eq('id', deleteId);
      if (deletePid.isNotEmpty) {
        await _notifyEmployeeFormazioneChange(
          personaleId: deletePid,
          formazioneId: deleteId,
          action: 'delete',
          corso: deleteCorso.isEmpty ? 'Corso formazione' : deleteCorso,
        );
      }
      await _load();
      _snack('Corso formazione eliminato');
    } catch (e) {
      _snack('Errore eliminazione corso: $e', error: true);
    }
  }

  Future<void> _openPersonSummary(String pid, String name) async {
    final byGroup = <String, Map<String, dynamic>>{};
    for (final r in _rows) {
      if ((r['personale_id'] ?? '').toString() != pid) continue;
      final group = _normalizeCourseGroup((r['corso'] ?? '').toString());
      final existing = byGroup[group];
      if (existing == null || _preferRow(r, existing)) {
        byGroup[group] = r;
      }
    }
    final items = byGroup.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.78;
        final maxW = MediaQuery.of(ctx).size.width * 0.88;
        return AlertDialog(
          title: Text('Riepilogo corsi - $name'),
          content: SizedBox(
            width: maxW.clamp(420.0, 980.0),
            height: maxH.clamp(260.0, 700.0),
            child: items.isEmpty
                ? const Center(child: Text('Nessun corso disponibile per questo dipendente'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final corso = items[i].key;
                      final row = items[i].value;
                      final scadRaw = (row['scadenza_attestato'] ?? '').toString();
                      final modalita = (row['modalita'] ?? '').toString().trim();
                      final strutturaLabel =
                          modalita.toLowerCase() == 'online' ? 'Link' : 'Struttura';
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.28)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              corso,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                Text('ATT: ${_attCell(row)}'),
                                Text('SCAD: ${_fmtDateOnly(scadRaw)}', style: _scadTextStyle(scadRaw)),
                                Text(
                                  'Ente: ${(row['ente'] ?? '').toString().trim().isEmpty ? '-' : row['ente']}',
                                ),
                                Text(
                                  'Tipo: ${(row['primo_rilascio_aggiornamento'] ?? '').toString().trim().isEmpty ? '-' : row['primo_rilascio_aggiornamento']}',
                                ),
                                Text(
                                  'Data programmazione: ${formatProgrammazioneDalAl(row['prima_data'], row['seconda_data']).isEmpty ? '-' : formatProgrammazioneDalAl(row['prima_data'], row['seconda_data'])}',
                                ),
                                Text(
                                  'ODA: ${(row['oda'] ?? '').toString().trim().isEmpty ? '-' : row['oda']}',
                                ),
                                Text(
                                  'Orario: ${(row['orario'] ?? '').toString().trim().isEmpty ? '-' : row['orario']}',
                                ),
                                Text(
                                  'Modalita: ${modalita.isEmpty ? '-' : modalita}',
                                ),
                                Text(
                                  '$strutturaLabel: ${() {
                                    final nome =
                                        (row['struttura_nome'] ?? '').toString().trim();
                                    if (nome.isNotEmpty) return nome;
                                    final link =
                                        (row['struttura_link'] ?? '').toString().trim();
                                    return link.isEmpty ? '-' : link;
                                  }()}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            (row['note'] ?? '').toString().trim().isEmpty
                                ? const Text(
                                    'Note: -',
                                    style: TextStyle(fontSize: 12, color: Colors.black87),
                                  )
                                : NotePreviewText(
                                    note: (row['note'] ?? '').toString(),
                                    prefix: 'Note: ',
                                    maxChars: 10,
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                            if (!_effectiveReadOnly) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      await _openEditor(
                                        current: row,
                                        initialPersonaleId: pid,
                                        initialCorso: corso,
                                      );
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifica'),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: ctx,
                                        builder: (dctx) => AlertDialog(
                                          title: const Text('Conferma eliminazione'),
                                          content: Text(
                                            'Vuoi eliminare il corso "$corso" per questo dipendente?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(dctx, false),
                                              child: const Text('Annulla'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(dctx, true),
                                              child: const Text('Elimina'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                      Navigator.of(ctx).pop();
                                      await _deleteFormazioneRow(row);
                                    },
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    label: const Text(
                                      'Elimina',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi')),
          ],
        );
      },
    );
  }

  Widget _buildMobileFormazionePeopleList(List<Map<String, dynamic>> people) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = people[i];
        final name = (p['name'] ?? '').toString();
        final pid = (p['pid'] ?? '').toString();
        final groups = p['groups'] as Map<String, Map<String, dynamic>>?;
        final courseCount = groups?.length ?? 0;
        final dimessi = (p['dimessi'] ?? '').toString().trim();
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.22)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: CircleAvatar(
              radius: 18,
              child: Text(
                '${i + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              dimessi.isNotEmpty
                  ? 'Dimessi: $dimessi · $courseCount corsi'
                  : '$courseCount corsi registrati',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPersonSummary(pid, name),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = useCompactPageLayout(context) || useMobileUi(context);
    final q = _searchCtrl.text.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final courseGroupsHit = _courseGroupsMatchingQuery(q);
    final filtered = _visibleRows(q, today, courseGroupsHit: courseGroupsHit);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(title: widget.pageTitle),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          if (widget.tableName == 'formazione_corsi' &&
              canManageFormazioneDlgs81Griglia(_effectiveRoleForUi))
            IconButton(
              tooltip: 'Strutture Formazioni 81',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => useMobileUi(context)
                      ? const AdminFormazioneDlgsStruttureMobilePage()
                      : const AdminFormazioneDlgsStrutturePage(),
                ),
              ),
              icon: const Icon(Icons.apartment_outlined),
            ),
          if (!_effectiveReadOnly)
            IconButton(
              tooltip: 'Gestione personale',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => useMobileUi(context)
                      ? const AdminGestioneDipendentiMobilePage()
                      : const AdminGestioneDipendentiPage(),
                ),
              ),
              icon: const Icon(Icons.badge_outlined),
            ),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          if (!_effectiveReadOnly)
            IconButton(onPressed: _loading ? null : () => _openEditor(), icon: const Icon(Icons.add)),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PageWithTopLogo(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(isCompact ? 8 : 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: isCompact ? cronosFullFieldWidth(context, horizontalMargin: 40) : 420,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Cerca dipendente o tipo corso (es. dpi, preposto)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        FilterChip(
                          label: Text(isCompact ? 'Scad.' : 'Scaduti'),
                          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                          selected: _expiryFilter == 'expired',
                          onSelected: (_) => setState(
                            () => _expiryFilter = _expiryFilter == 'expired' ? 'all' : 'expired',
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(isCompact ? '60g' : 'Allerta 60'),
                          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                          selected: _expiryFilter == '60',
                          onSelected: (_) => setState(
                            () => _expiryFilter = _expiryFilter == '60' ? 'all' : '60',
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(isCompact ? '45g' : 'Allerta 45'),
                          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                          selected: _expiryFilter == '45',
                          onSelected: (_) => setState(
                            () => _expiryFilter = _expiryFilter == '45' ? 'all' : '45',
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(isCompact ? '30g' : 'Allerta 30'),
                          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                          selected: _expiryFilter == '30',
                          onSelected: (_) => setState(
                            () => _expiryFilter = _expiryFilter == '30' ? 'all' : '30',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: isCompact ? 8 : 12, right: isCompact ? 8 : 12, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: isCompact ? cronosFullFieldWidth(context, horizontalMargin: 40) : 520,
                          child: Text(
                              q.isNotEmpty && courseGroupsHit.isNotEmpty
                                  ? 'Dipendenti con corso: ${courseGroupsHit.join(', ')}'
                                  : q.isNotEmpty
                                      ? 'Ricerca: «$q» (nome o corso)'
                                      : _expiryFilter == 'all'
                                          ? 'Visualizzazione completa'
                                          : _expiryFilter == 'expired'
                                              ? 'Visualizzati solo corsi scaduti'
                                              : 'Visualizzati corsi in scadenza entro $_expiryFilter giorni'),
                        ),
                        if (!_effectiveReadOnly)
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _addDraftColumn,
                            icon: const Icon(Icons.view_column_outlined),
                            label: const Text('Nuova colonna'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
                    child: _effectiveReadOnly
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Suggerimento: usa "Nuova colonna" per aggiungere il blocco ATT/SCAD e rinominalo dai 3 puntini.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.black54,
                                  ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final byPerson = <String, Map<String, dynamic>>{};
                        String personKeyFor(String pid, String name) {
                          if (!_effectiveReadOnly) return pid;
                          final n = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
                          return n.isEmpty ? pid : n;
                        }
                        // Elenco completo solo senza ricerca né filtro scadenze.
                        final showAllPeople = q.isEmpty && _expiryFilter == 'all';
                        if (showAllPeople) {
                          for (final e in _personaleNameById.entries) {
                            final key = personKeyFor(e.key, e.value);
                            byPerson.putIfAbsent(key, () => <String, dynamic>{
                              'pid': e.key,
                              'name': e.value,
                              'dimessi': '',
                              'groups': <String, Map<String, dynamic>>{},
                            });
                          }
                        }
                        for (final r in filtered) {
                          final pid = (r['personale_id'] ?? '').toString();
                          if (pid.isEmpty) continue;
                          final group = _normalizeCourseGroup((r['corso'] ?? '').toString());
                          final personName = _personaleNameById[pid] ?? pid;
                          final key = personKeyFor(pid, personName);
                          final person = byPerson.putIfAbsent(key, () {
                            return <String, dynamic>{
                              'pid': pid,
                              'name': personName,
                              'dimessi': '',
                              'groups': <String, Map<String, dynamic>>{},
                            };
                          });
                          final dim = (r['dimessi'] ?? '').toString().trim();
                          if (dim.isNotEmpty) person['dimessi'] = dim;
                          final groups = person['groups'] as Map<String, Map<String, dynamic>>;
                          final existing = groups[group];
                          final focusId = (_focusRowId ?? '').trim();
                          final incomingId = (r['id'] ?? '').toString().trim();
                          final existingId = (existing?['id'] ?? '').toString().trim();
                          if (focusId.isNotEmpty && incomingId == focusId) {
                            groups[group] = r;
                          } else if (existing == null || _preferRow(r, existing)) {
                            groups[group] = r;
                          } else if (focusId.isNotEmpty && existingId == focusId) {
                            groups[group] = existing;
                          }
                        }

                        var people = byPerson.values.toList();
                        if (courseGroupsHit.isNotEmpty) {
                          final targets =
                              courseGroupsHit.map((g) => g.toLowerCase()).toSet();
                          people = people.where((p) {
                            final groups =
                                p['groups'] as Map<String, Map<String, dynamic>>;
                            return groups.entries.any((e) =>
                                targets.contains(e.key.toLowerCase()) &&
                                _rowHasAttestato(e.value));
                          }).toList();
                        }
                        people.sort((a, b) => (a['name'] as String)
                            .toLowerCase()
                            .compareTo((b['name'] as String).toLowerCase()));
                        if (_focusPersonaleId != null) {
                          final idx = people.indexWhere((p) => (p['pid'] as String) == _focusPersonaleId);
                          if (idx >= 0) {
                            final focused = people.removeAt(idx);
                            people.insert(0, focused);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _focusPersonaleId = null;
                                _focusRowId = null;
                              });
                            });
                          }
                        }

                        final List<String> groups;
                        if (courseGroupsHit.isNotEmpty) {
                          // Ricerca per tipo corso: solo colonne del corso cercato.
                          groups = List<String>.from(courseGroupsHit);
                          if (!_isRfiExcelLike &&
                              widget.tableName == 'formazione_corsi') {
                            groups.sort((a, b) {
                              final ia = _courseGroupOrder.indexOf(a);
                              final ib = _courseGroupOrder.indexOf(b);
                              if (ia < 0 && ib < 0) return a.compareTo(b);
                              if (ia < 0) return 1;
                              if (ib < 0) return -1;
                              return ia.compareTo(ib);
                            });
                          }
                        } else {
                          final discovered = <String>{};
                          for (final r in _rows) {
                            final pid = (r['personale_id'] ?? '').toString();
                            if (pid.isEmpty) continue;
                            discovered.add(_normalizeCourseGroup(
                                (r['corso'] ?? '').toString()));
                          }
                          groups = (_isRfiExcelLike ||
                                  widget.tableName != 'formazione_corsi')
                              ? (discovered.toList()..sort())
                              : <String>[
                                  ..._courseGroupOrder.where(discovered.contains),
                                  ...discovered
                                      .where((g) => !_courseGroupOrder.contains(g))
                                      .toList()
                                    ..sort(),
                                ];
                          for (final draft in _draftCourseGroups) {
                            if (!groups.contains(draft)) groups.insert(0, draft);
                          }
                          final existingLower =
                              groups.map((g) => g.toLowerCase()).toSet();
                          for (final g in _localEmptyCourseGroups) {
                            if (!existingLower.contains(g.toLowerCase())) {
                              groups.insert(0, g);
                              existingLower.add(g.toLowerCase());
                            }
                          }
                        }
                        if (_focusCourseGroup != null) {
                          final idx = groups.indexWhere(
                            (g) => g.toLowerCase() == _focusCourseGroup!.toLowerCase(),
                          );
                          if (idx >= 0) {
                            final focused = groups.removeAt(idx);
                            groups.insert(0, focused);
                          } else {
                            // Mostra comunque la nuova colonna appena creata anche se
                            // la ricarica DB arriva in ritardo.
                            groups.insert(0, _focusCourseGroup!);
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            if (_headerHorizontalCtrl.hasClients) {
                              _headerHorizontalCtrl.jumpTo(0);
                            }
                            if (_bodyHorizontalCtrl.hasClients) {
                              _bodyHorizontalCtrl.jumpTo(0);
                            }
                            if (_focusCourseGroup != null) {
                              setState(() => _focusCourseGroup = null);
                            }
                          });
                        }

                        if (people.isEmpty) {
                          return const Center(child: Text('Nessun dato formazione da mostrare'));
                        }

                        if (useMobileUi(context)) {
                          return _buildMobileFormazionePeopleList(people);
                        }

                        final isRfiView = _isRfiExcelLike;
                        final leftNumberWidth = isCompact ? 44.0 : 50.0;
                        final leftNameWidth = isCompact ? 170.0 : 210.0;
                        final rightCellWidth = isRfiView
                            ? (isCompact ? 140.0 : 170.0)
                            : (isCompact ? 98.0 : 108.0);
                        final headerHeight = isRfiView ? 96.0 : 72.0;
                        const rowHeight = 44.0;
                        final gridColor = Colors.blueGrey.withValues(alpha: 0.22);
                        final blockDividerColor = Colors.blueGrey.withValues(alpha: 0.40);

                        Widget rightHeader() {
                          return Row(
                            children: groups.asMap().entries.expand((entry) {
                              final g = entry.value;
                              return [
                                SizedBox(
                                  width: rightCellWidth,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: gridColor, width: 0.8),
                                        bottom: BorderSide(color: gridColor, width: 1.0),
                                      ),
                                    ),
                                    child: InkWell(
                                      onTap: _effectiveReadOnly ? null : () => _openCourseColumnActions(g),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  if (_newCourseBadgeGroup != null &&
                                                      g.toLowerCase() ==
                                                          _newCourseBadgeGroup!.toLowerCase())
                                                    Container(
                                                      margin: const EdgeInsets.only(bottom: 2),
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.shade700,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: const Text(
                                                        'NUOVO',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.w700,
                                                          height: 1,
                                                        ),
                                                      ),
                                                    ),
                                                  Text(
                                                    _groupHeaderTitle(g),
                                                    maxLines: isRfiView ? 6 : 3,
                                                    overflow: isRfiView
                                                        ? TextOverflow.visible
                                                        : TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      height: 1.2,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.more_vert,
                                              size: 14,
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: rightCellWidth,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: blockDividerColor, width: 1.2),
                                        bottom: BorderSide(color: gridColor, width: 1.0),
                                      ),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        'SCAD',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ];
                            }).toList(growable: false),
                          );
                        }

                        Widget leftHeader() {
                          return Row(
                            children: [
                              SizedBox(
                                width: leftNumberWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: gridColor, width: 0.8),
                                      bottom: BorderSide(color: gridColor, width: 1.0),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('#', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: leftNameWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: blockDividerColor, width: 1.2),
                                      bottom: BorderSide(color: gridColor, width: 1.0),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      'Nominativi',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Container(
                              height: headerHeight,
                              color: Theme.of(context).colorScheme.surface,
                              child: Row(
                                children: [
                                  leftHeader(),
                                  Expanded(
                                    child: LinkedScrollbar(
                                      controller: _headerHorizontalCtrl,
                                      axis: Axis.horizontal,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _headerHorizontalCtrl,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: groups.length * 2 * rightCellWidth,
                                          child: rightHeader(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: leftNumberWidth + leftNameWidth,
                                    child: LinkedScrollbar(
                                      controller: _leftVerticalCtrl,
                                      thumbVisibility: true,
                                      child: ListView.builder(
                                        controller: _leftVerticalCtrl,
                                        itemCount: people.length,
                                        itemExtent: rowHeight,
                                        itemBuilder: (context, i) {
                                          final name = people[i]['name'] as String;
                                          final rowBg = i.isEven
                                              ? Colors.transparent
                                              : Colors.blueGrey.withValues(alpha: 0.03);
                                          return Row(
                                            children: [
                                              SizedBox(
                                                width: leftNumberWidth,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: rowBg,
                                                    border: Border(
                                                      right: BorderSide(color: gridColor, width: 0.8),
                                                      bottom: BorderSide(color: gridColor, width: 0.8),
                                                    ),
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Text('${i + 1}'),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: leftNameWidth,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: rowBg,
                                                    border: Border(
                                                      right: BorderSide(
                                                        color: blockDividerColor,
                                                        width: 1.2,
                                                      ),
                                                      bottom: BorderSide(color: gridColor, width: 0.8),
                                                    ),
                                                  ),
                                                  child: InkWell(
                                                    onTap: () => _openPersonSummary(
                                                      (people[i]['pid'] ?? '').toString(),
                                                      name,
                                                    ),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                                      child: Text(
                                                        name,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          decoration: TextDecoration.underline,
                                                          decorationThickness: 0.8,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: LinkedScrollbar(
                                      controller: _bodyHorizontalCtrl,
                                      axis: Axis.horizontal,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _bodyHorizontalCtrl,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: groups.length * 2 * rightCellWidth,
                                          child: LinkedScrollbar(
                                            controller: _rightVerticalCtrl,
                                            thumbVisibility: true,
                                            child: ListView.builder(
                                              controller: _rightVerticalCtrl,
                                              itemCount: people.length,
                                              itemExtent: rowHeight,
                                              itemBuilder: (context, i) {
                                                final p = people[i];
                                                final pid = p['pid'] as String;
                                                final rowBg = i.isEven
                                                    ? Colors.transparent
                                                    : Colors.blueGrey.withValues(alpha: 0.03);
                                                final gmap =
                                                    p['groups'] as Map<String, Map<String, dynamic>>;
                                                return Row(
                                                  children: groups.asMap().entries.expand((entry) {
                                                    final g = entry.value;
                                                    final row = gmap[g];
                                                    final scadRaw =
                                                        (row?['scadenza_attestato'] ?? '').toString();
                                                    return [
                                                      SizedBox(
                                                        width: rightCellWidth,
                                                        child: InkWell(
                                                          onTap: _effectiveReadOnly
                                                              ? null
                                                              : () => _openEditor(
                                                                    current: row,
                                                                    initialPersonaleId: pid,
                                                                    initialCorso: _isDraftGroup(g) ? '' : g,
                                                                  ),
                                                          child: _wrapFieldAudit(
                                                            row: row,
                                                            fieldKey: 'data_attestato',
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                color: rowBg,
                                                                border: Border(
                                                                  right: BorderSide(
                                                                    color: gridColor,
                                                                    width: 0.8,
                                                                  ),
                                                                  bottom: BorderSide(
                                                                    color: gridColor,
                                                                    width: 0.8,
                                                                  ),
                                                                ),
                                                              ),
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                              ),
                                                              child: Text(
                                                                _attCell(row),
                                                                style: _attTextStyle(row),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: rightCellWidth,
                                                        child: InkWell(
                                                          onTap: _effectiveReadOnly
                                                              ? null
                                                              : () => _openEditor(
                                                                    current: row,
                                                                    initialPersonaleId: pid,
                                                                    initialCorso: _isDraftGroup(g) ? '' : g,
                                                                  ),
                                                          child: _wrapFieldAudit(
                                                            row: row,
                                                            fieldKey: 'scadenza_attestato',
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                color: _scadBg(scadRaw) == Colors.transparent
                                                                    ? rowBg
                                                                    : _scadBg(scadRaw),
                                                                border: Border(
                                                                  right: BorderSide(
                                                                    color: blockDividerColor,
                                                                    width: 1.2,
                                                                  ),
                                                                  bottom: BorderSide(
                                                                    color: gridColor,
                                                                    width: 0.8,
                                                                  ),
                                                                ),
                                                              ),
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              child: Text(
                                                                _fmtDateOnly(scadRaw),
                                                                style: _scadTextStyle(scadRaw),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ];
                                                  }).toList(growable: false),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _effectiveReadOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo corso'),
            ),
    );
  }
}

class _DateSlashFormatter extends TextInputFormatter {
  const _DateSlashFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final max = digits.length > 8 ? digits.substring(0, 8) : digits;
    final b = StringBuffer();
    for (int i = 0; i < max.length; i++) {
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

