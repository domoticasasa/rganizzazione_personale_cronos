import 'dart:async';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/employee_programmazione_service.dart';
import '../services/programmazione_formazioni_pdf_export.dart';
import '../services/formazione_programmazione_config_service.dart';
import '../services/formazione_rfi_programmazione_service.dart';
import '../services/formazione_rfi_strutture_service.dart';
import '../services/notification_sender.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/formazione_programmazione_dates.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/users_directory.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/rfi_struttura_selector.dart';
import '../widgets/struttura_link_cell.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Corsi RFI con **data programmazione dal/al** impostata (admin/DT o dipendente).
class DtProgrammazioneFormazioniRfiPage extends StatefulWidget {
  final bool employeeOnly;
  final String? employeeFullName;

  const DtProgrammazioneFormazioniRfiPage({
    super.key,
    this.employeeOnly = false,
    this.employeeFullName,
  });

  @override
  State<DtProgrammazioneFormazioniRfiPage> createState() =>
      _DtProgrammazioneFormazioniRfiPageState();
}

class _DtProgrammazioneFormazioniRfiPageState
    extends State<DtProgrammazioneFormazioniRfiPage> {
  bool _loading = true;
  String _search = '';
  String? _ownPersonaleId;
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _personaleById =
      <String, Map<String, dynamic>>{};
  final Set<String> _expandedRowKeys = <String>{};
  List<Map<String, dynamic>> _rfiStrutture = <Map<String, dynamic>>[];
  bool _blinkOn = true;
  Timer? _blinkTimer;
  bool _autoPurgeEnabled = true;
  bool _savingAutoPurge = false;

  bool get _employeeOnly => widget.employeeOnly;
  bool get _canEdit => !_employeeOnly;

  /// Card espandibili su mobile e per la vista dipendente.
  bool _layoutCompact(BuildContext context) =>
      _employeeOnly || useMobileUi(context);

  @override
  void initState() {
    super.initState();
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

  Future<void> _setAutoPurgeEnabled(bool enabled) async {
    if (_savingAutoPurge) return;
    setState(() => _savingAutoPurge = true);
    try {
      await FormazioneProgrammazioneConfigService.setRfiAutoPurge(enabled);
      if (!mounted) return;
      setState(() => _autoPurgeEnabled = enabled);
      await _load(showSpinner: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Rimozione automatica attivata: il giorno dopo la fine corso la riga viene eliminata.'
                : 'Rimozione automatica disattivata: i corsi restano in elenco anche dopo la fine.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Impossibile salvare impostazione: $e');
      }
    } finally {
      if (mounted) setState(() => _savingAutoPurge = false);
    }
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
      final bytes = await buildProgrammazioneFormazioniRfiPdfBytes(
        rows: items,
        personaleById: _personaleById,
        employeeOnly: _employeeOnly,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Programmazione_Formazioni_RFI',
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
      final sheet = excel['Sheet1'];
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
          'DOIT / Struttura',
          'Indirizzo',
          'Link Maps',
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
          'DOIT / Struttura',
          'Indirizzo',
          'Link Maps',
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
            _s(r['struttura_nome']),
            _s(r['struttura_indirizzo']),
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
            _s(r['struttura_nome']),
            _s(r['struttura_indirizzo']),
            _s(r['struttura_link']),
            _s(r['note']),
          ]);
        }
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Programmazione_Formazioni_RFI',
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
      } else {
        ModifyFeedback.error(context, 'Export Excel non riuscito.');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Errore export Excel: $e');
    }
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      await FormazioneProgrammazioneConfigService.loadRfiAutoPurge();
      if (mounted) {
        setState(() {
          _autoPurgeEnabled =
              FormazioneProgrammazioneConfigService.rfiAutoPurgeAfterCourseEnd;
        });
      }

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
            .select('id, id_uuid, full_name, matricola, telefono, email, active')
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
              .select(
                'id, id_uuid, full_name, matricola, telefono, email, active',
              ) as List,
        );
        for (final m in personaleRes) {
          final id = _s(m['id_uuid']);
          if (id.isNotEmpty) _personaleById[id] = m;
        }
      }

      final loaded = await FormazioneRfiProgrammazioneService.loadProgrammazioneRows(
        onlyPersonaleUuid: _employeeOnly ? myPersonaleId : null,
        purgeExpired: _canEdit && _autoPurgeEnabled,
      );
      final strutture = await FormazioneRfiStruttureService.loadAll();
      _rows
        ..clear()
        ..addAll(loaded);
      _rfiStrutture = strutture;
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
        _s(r['struttura_nome']),
        _s(r['struttura_indirizzo']),
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
      if (modalita.toLowerCase() == 'online')
        _detailLinkRow(strutturaLabel, _s(r['struttura_link']),
            compact: _layoutCompact(context))
      else ...[
        _detailRow('DOIT / Struttura', _s(r['struttura_nome']),
            compact: _layoutCompact(context)),
        _detailRow('Indirizzo', _s(r['struttura_indirizzo']),
            compact: _layoutCompact(context)),
        _detailLinkRow('Posizione Maps', _s(r['struttura_link']),
            compact: _layoutCompact(context)),
      ],
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

  int? _personaleIdIntFromUuid(String uuid) {
    final m = _personaleById[uuid];
    if (m == null) return null;
    return int.tryParse(_s(m['id']));
  }

  Future<void> _openNewProgrammazione() async {
    if (!_canEdit) return;

    final personaleUuid = ValueNotifier<String>('');
    final corsoCtrl = TextEditingController();
    final corsoValue = ValueNotifier<String>('');
    final programmazioneDalCtrl = TextEditingController();
    final programmazioneAlCtrl = TextEditingController();
    final odaCtrl = TextEditingController();
    final orarioCtrl = TextEditingController();
    final modalitaValue = ValueNotifier<String>('In presenza');
    final strutturaIdNotifier = ValueNotifier<String?>(null);
    final strutturaLinkCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    List<String> trackOptions = <String>[];
    try {
      trackOptions = await FormazioneRfiProgrammazioneService.loadDistinctTracks();
    } catch (_) {
      trackOptions = _rows
          .map((r) => _s(r['corso']))
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    Future<void> pickDipendente() async {
      final all = _personaleById.entries
          .where((e) => e.value['active'] != false)
          .map((e) {
            final name = _s(e.value['full_name']);
            final mat = _s(e.value['matricola']);
            final label = mat.isEmpty ? name : '$name ($mat)';
            return MapEntry(e.key, label);
          })
          .where((e) => e.value.trim().isNotEmpty)
          .toList()
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
                  final filtered = all
                      .where((e) => e.value.toLowerCase().contains(qq))
                      .toList();
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
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      );
      if (chosen != null && chosen.isNotEmpty) {
        personaleUuid.value = chosen;
      }
    }

    Future<void> pickCorso() async {
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
                  final filtered = trackOptions
                      .where((c) => c.toLowerCase().contains(qq))
                      .toList();
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
                                title: const Text('Corso libero'),
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
                                    onPressed: () =>
                                        Navigator.pop(dctx, customCtrl.text.trim()),
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
                          label: const Text('Inserisci liberamente'),
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('Nessun corso in elenco: usa testo libero.'),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
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
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Chiudi'),
              ),
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
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Nuova programmazione RFI'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: personaleUuid,
                    builder: (_, pid, _) {
                      final p = _personaleById[pid];
                      final name = _s(p?['full_name']);
                      final mat = _s(p?['matricola']);
                      final label = name.isEmpty
                          ? 'Seleziona dipendente'
                          : (mat.isEmpty ? name : '$name ($mat)');
                      return InkWell(
                        onTap: pickDipendente,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Dipendente',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.search),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: name.isEmpty
                                  ? Theme.of(ctx).hintColor
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: corsoValue,
                    builder: (_, corso, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: pickCorso,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Corso (seleziona o libero)',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.list_alt),
                              ),
                              child: Text(
                                corso.isEmpty ? 'Seleziona o inserisci corso' : corso,
                                style: TextStyle(
                                  color: corso.isEmpty
                                      ? Theme.of(ctx).hintColor
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: corsoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Corso (testo libero)',
                              hintText: 'Puoi scrivere il nome corso qui',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => corsoValue.value = v.trim(),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Programmazione corso',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Un solo giorno: compila solo «dal». Più giorni: compila anche «al».',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: programmazioneDalCtrl,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: const [_ProgDateSlashFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Data dal (gg/mm/aaaa)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: programmazioneAlCtrl,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: const [_ProgDateSlashFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Data al (gg/mm/aaaa)',
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
                            hintText: 'es. 09:00-13:00',
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
                        builder: (_, selectedId, _) {
                          return RfiStrutturaSelector(
                            strutture: _rfiStrutture,
                            selectedId: selectedId,
                            onlineMode: isOnline,
                            onlineLinkController: strutturaLinkCtrl,
                            onOpenLinkFailed: _onLinkOpenFailed,
                            onChanged: (s) {
                              strutturaIdNotifier.value =
                                  s == null ? null : _s(s['id_uuid']);
                              if (s != null) {
                                strutturaLinkCtrl.text = _s(s['maps_link']);
                              } else if (!isOnline) {
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            AsyncFilledButton(
              onPressed: () async {
                final pidUuid = personaleUuid.value.trim();
                final track = corsoCtrl.text.trim().isNotEmpty
                    ? corsoCtrl.text.trim()
                    : corsoValue.value.trim();
                if (pidUuid.isEmpty) {
                  ModifyFeedback.error(ctx, 'Seleziona un dipendente.');
                  return;
                }
                if (track.isEmpty) {
                  ModifyFeedback.error(ctx, 'Seleziona o inserisci un corso.');
                  return;
                }
                final pidInt = _personaleIdIntFromUuid(pidUuid);
                if (pidInt == null) {
                  ModifyFeedback.error(
                    ctx,
                    'Dipendente non valido (id anagrafica mancante).',
                  );
                  return;
                }
                final norm = normalizeProgrammazioneIso(
                  dalText: programmazioneDalCtrl.text,
                  alText: programmazioneAlCtrl.text,
                );
                if (norm.error != null) {
                  ModifyFeedback.error(ctx, norm.error!);
                  return;
                }
                if ((norm.primaIso ?? '').isEmpty) {
                  ModifyFeedback.error(
                    ctx,
                    'Inserisci almeno la data programmazione «dal».',
                  );
                  return;
                }
                final isOnline =
                    modalitaValue.value.trim().toLowerCase() == 'online';
                final selected = FormazioneRfiStruttureService.findById(
                  _rfiStrutture,
                  strutturaIdNotifier.value,
                );
                await FormazioneRfiProgrammazioneService.saveProgrammazione(
                  personaleIdInt: pidInt,
                  track: track,
                  primaIso: norm.primaIso,
                  secondaIso: norm.secondaIso,
                  oda: odaCtrl.text.trim(),
                  orario: orarioCtrl.text.trim(),
                  modalita: modalitaValue.value.trim(),
                  strutturaRfiId: isOnline ? null : strutturaIdNotifier.value,
                  strutturaNome: isOnline ? null : _s(selected?['nome']),
                  strutturaIndirizzo:
                      isOnline ? null : _s(selected?['indirizzo']),
                  strutturaLink: isOnline
                      ? strutturaLinkCtrl.text.trim()
                      : _s(selected?['maps_link']).isNotEmpty
                          ? _s(selected?['maps_link'])
                          : strutturaLinkCtrl.text.trim(),
                  note: noteCtrl.text.trim(),
                );
                await NotificationSender.notifyEmployeeFormazioneChange(
                  personaleId: pidUuid,
                  formazioneId: pidInt,
                  action: 'create',
                  title: 'Nuova programmazione corso RFI',
                  message: 'Corso: $track',
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Salva'),
            ),
          ],
        );
      },
    );

    personaleUuid.dispose();
    corsoCtrl.dispose();
    corsoValue.dispose();
    programmazioneDalCtrl.dispose();
    programmazioneAlCtrl.dispose();
    odaCtrl.dispose();
    orarioCtrl.dispose();
    modalitaValue.dispose();
    strutturaIdNotifier.dispose();
    strutturaLinkCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      ModifyFeedback.success(context, 'Programmazione creata.');
      await _load();
    }
  }

  Future<void> _confirmClearProgrammazione(Map<String, dynamic> row) async {
    if (!_canEdit) return;
    final track = _s(row['corso']);
    final pidInt = row['personale_id_int'];
    if (pidInt is! int || track.isEmpty) {
      ModifyFeedback.error(context, 'Record corso RFI non valido.');
      return;
    }
    final pid = _s(row['personale_id']);
    final name = _s(_personaleById[pid]?['full_name']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina programmazione'),
        content: Text(
          name.isEmpty
              ? 'Rimuovere la programmazione di «$track»?\n'
                  'Restano invariati attestato e scadenze del corso.'
              : 'Rimuovere la programmazione di «$track» per $name?\n'
                  'Restano invariati attestato e scadenze del corso.',
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
    if (ok != true || !mounted) return;
    try {
      await FormazioneRfiProgrammazioneService.clearProgrammazione(
        personaleIdInt: pidInt,
        track: track,
      );
      final personaleUuid = _s(row['personale_id']);
      if (personaleUuid.isNotEmpty) {
        await NotificationSender.notifyEmployeeFormazioneChange(
          personaleId: personaleUuid,
          formazioneId: pidInt,
          action: 'update',
          title: 'Programmazione corso RFI rimossa',
          message: 'Corso: $track',
        );
      }
      if (!mounted) return;
      ModifyFeedback.success(context, 'Programmazione eliminata.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Eliminazione non riuscita: $e');
    }
  }

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
      _s(row['struttura_rfi_id']).isEmpty ? null : _s(row['struttura_rfi_id']),
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
                        builder: (_, selectedId, _) {
                          return RfiStrutturaSelector(
                            strutture: _rfiStrutture,
                            selectedId: selectedId,
                            onlineMode: isOnline,
                            onlineLinkController: strutturaLinkCtrl,
                            readOnly: !editable,
                            onOpenLinkFailed: _onLinkOpenFailed,
                            onChanged: editable
                                ? (s) {
                                    strutturaIdNotifier.value = s == null
                                        ? null
                                        : _s(s['id_uuid']);
                                    if (s != null) {
                                      strutturaLinkCtrl.text =
                                          _s(s['maps_link']);
                                    } else if (!isOnline) {
                                      strutturaLinkCtrl.clear();
                                    }
                                  }
                                : null,
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
            if (editable)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx, false);
                  await _confirmClearProgrammazione(row);
                },
                child: Text(
                  'Elimina',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
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
                  final pidInt = row['personale_id_int'];
                  final track = _s(row['corso']);
                  if (pidInt is! int || track.isEmpty) {
                    ModifyFeedback.error(ctx, 'Record corso RFI non valido.');
                    return;
                  }
                  final isOnline =
                      modalitaValue.value.trim().toLowerCase() == 'online';
                  final selected = FormazioneRfiStruttureService.findById(
                    _rfiStrutture,
                    strutturaIdNotifier.value,
                  );
                  try {
                    await FormazioneRfiProgrammazioneService.saveProgrammazione(
                      personaleIdInt: pidInt,
                      track: track,
                      primaIso: norm.primaIso,
                      secondaIso: norm.secondaIso,
                      oda: odaCtrl.text.trim(),
                      orario: orarioCtrl.text.trim(),
                      modalita: modalitaValue.value.trim(),
                      strutturaRfiId:
                          isOnline ? null : strutturaIdNotifier.value,
                      strutturaNome: isOnline ? null : _s(selected?['nome']),
                      strutturaIndirizzo:
                          isOnline ? null : _s(selected?['indirizzo']),
                      strutturaLink: isOnline
                          ? strutturaLinkCtrl.text.trim()
                          : _s(selected?['maps_link']).isNotEmpty
                              ? _s(selected?['maps_link'])
                              : strutturaLinkCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                    );
                  } catch (e) {
                    if (ctx.mounted) {
                      ModifyFeedback.error(ctx, 'Salvataggio non riuscito: $e');
                    }
                    return;
                  }
                  final personaleUuid = _s(row['personale_id']);
                  if (personaleUuid.isNotEmpty) {
                    await NotificationSender.notifyEmployeeFormazioneChange(
                      personaleId: personaleUuid,
                      formazioneId: pidInt,
                      action: 'update',
                      title: 'Programmazione corso RFI aggiornata',
                      message: 'Corso: $track',
                    );
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

  Widget _rowActions(Map<String, dynamic> r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Modifica',
          icon: const Icon(Icons.edit_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: _loading ? null : () => _openCourseDetail(r),
        ),
        IconButton(
          tooltip: 'Elimina programmazione',
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
          visualDensity: VisualDensity.compact,
          onPressed: _loading ? null : () => _confirmClearProgrammazione(r),
        ),
      ],
    );
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
                  if (_canEdit) _rowActions(r),
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
                  if (_canEdit) _rowActions(r),
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
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
        headingRowColor: WidgetStateProperty.all(Colors.green.shade50),
        columns: [
          if (_canEdit) const DataColumn(label: Text('Azioni')),
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
          const DataColumn(label: Text('DOIT / Struttura')),
          const DataColumn(label: Text('Note')),
        ],
        rows: items.map((r) {
          final pid = _s(r['personale_id']);
          final p = _personaleById[pid];
          return DataRow(
            color: WidgetStateProperty.resolveWith(
              (_) => _dataRowFillColor(r),
            ),
            cells: [
              if (_canEdit) DataCell(_rowActions(r)),
              DataCell(
                _progDateTableCell(r),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_fmtDate(r['scadenza_attestato'])),
                onTap: () => _openCourseDetail(r),
              ),
              if (!_employeeOnly)
                DataCell(
                  Text(_s(p?['full_name'])),
                  onTap: () => _openCourseDetail(r),
                ),
              if (!_employeeOnly)
                DataCell(
                  Text(_s(p?['matricola'])),
                  onTap: () => _openCourseDetail(r),
                ),
              DataCell(
                Text(_s(r['corso'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_s(r['ente'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_fmtDate(r['data_attestato'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_s(r['oda'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_s(r['orario'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Text(_s(r['modalita'])),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 220,
                    child: RfiStrutturaTableCell(
                      row: r,
                      compact: true,
                      onOpenLinkFailed: _onLinkOpenFailed,
                    ),
                  ),
                ),
                onTap: () => _openCourseDetail(r),
              ),
              DataCell(
                SizedBox(
                  width: 160,
                  child: NotePreviewText(
                    note: _s(r['note']),
                    maxChars: 24,
                  ),
                ),
                onTap: () => _openCourseDetail(r),
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
          title: 'Programmazioni corsi RFI',
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
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _openNewProgrammazione,
              icon: const Icon(Icons.add),
              label: const Text('Nuova programmazione'),
            )
          : null,
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
                      ? 'I tuoi corsi RFI con data programmazione (dal/al) impostata dall’amministrazione.'
                      : 'Corsi RFI con data programmazione (dal/al). '
                          'Usa matita/cestino oppure clicca la riga per modificare.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (!_employeeOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    _autoPurgeEnabled
                        ? 'Ordinati per inizio programmazione (dal) più vicino in alto. '
                            'Data prog. rossa entro 2 giorni; lampeggiante se il corso è oggi o in corso. '
                            'Intervallo su più giorni evidenziato in verde. '
                            'Il giorno dopo la fine del corso la riga si rimuove automaticamente.'
                        : 'Ordinati per inizio programmazione (dal) più vicino in alto. '
                            'Data prog. rossa entro 2 giorni; lampeggiante se il corso è oggi o in corso. '
                            'Intervallo su più giorni evidenziato in verde. '
                            'Rimozione automatica dopo la fine corso disattivata.',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_canEdit)
                  Align(
                    alignment: Alignment.center,
                    child: FilterChip(
                      avatar: _savingAutoPurge
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _autoPurgeEnabled
                                  ? Icons.auto_delete
                                  : Icons.auto_delete_outlined,
                              size: 18,
                            ),
                      label: Text(
                        _autoPurgeEnabled
                            ? 'Auto-rimozione: attiva'
                            : 'Auto-rimozione: disattiva',
                      ),
                      selected: _autoPurgeEnabled,
                      showCheckmark: false,
                      onSelected: _savingAutoPurge
                          ? null
                          : (selected) => _setAutoPurgeEnabled(selected),
                    ),
                  ),
                if (_canEdit) const SizedBox(height: 8),
                TextField(
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
              ],
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
                        padding: EdgeInsets.fromLTRB(0, 4, 0, _canEdit ? 88 : 20),
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
                        padding: EdgeInsets.fromLTRB(16, 0, 16, _canEdit ? 96 : 24),
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
