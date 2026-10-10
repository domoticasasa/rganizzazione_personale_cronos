import 'dart:async';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/employee_programmazione_service.dart';
import '../services/supabase_service.dart';
import '../services/visite_mediche_pdf_export.dart';
import '../services/visite_mediche_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_web_safe.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/users_directory.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Programmazione visite mediche (stesso schema UI/logica di [DtProgrammazioneFormazioniPage]).
/// Con [rfiMode] usa la tabella RFI e consente upload/download del PDF struttura.
class VisiteMedichePage extends StatefulWidget {
  final bool adminMode;
  final bool employeeOnly;
  final String? employeeFullName;
  final bool rfiMode;

  const VisiteMedichePage({
    super.key,
    this.adminMode = false,
    this.employeeOnly = false,
    this.employeeFullName,
    this.rfiMode = false,
  });

  @override
  State<VisiteMedichePage> createState() => _VisiteMedichePageState();
}

class _VisiteMedichePageState extends State<VisiteMedichePage> {
  bool _loading = true;
  String _search = '';
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _personaleById =
      <String, Map<String, dynamic>>{};
  final List<Map<String, String>> _personaleOptions = <Map<String, String>>[];
  final Set<String> _expandedRowKeys = <String>{};
  String? _ownPersonaleUuid;
  bool _blinkOn = true;
  Timer? _blinkTimer;

  bool get _employeeOnly => widget.employeeOnly;
  bool get _canEdit => widget.adminMode;
  bool get _rfi => widget.rfiMode;
  String get _table => VisiteMedicheService.tableName(rfi: _rfi);
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

  String _fmtDateTime(dynamic v) {
    final s = formatDateTimeItFromSupabase(v);
    return s.isEmpty ? '—' : s;
  }

  String _dipendenteLabel(Map<String, dynamic> r) {
    final nome = _s(r['dipendente_nome']);
    if (nome.isNotEmpty) return nome;
    final pid = _s(r['personale_id_uuid']);
    return _s(_personaleById[pid]?['full_name']);
  }

  Future<void> _exportPdf() async {
    final items = _filteredRows;
    if (items.isEmpty) {
      if (!mounted) return;
      ModifyFeedback.hint(context, 'Nessun dato da esportare');
      return;
    }
    try {
      final bytes = await buildVisiteMedichePdfBytes(
        rows: items,
        personaleById: _personaleById,
        employeeOnly: _employeeOnly,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Visite_Mediche',
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
      sheet.appendRow(<String>[
        'Data e ora',
        'Dipendente',
        'Matricola',
        'Luogo / struttura',
        'Link',
        'Note',
      ]);
      for (final r in items) {
        final pid = _s(r['personale_id_uuid']);
        sheet.appendRow(<String>[
          _fmtDateTime(r['data_visita']),
          _dipendenteLabel(r),
          _s(_personaleById[pid]?['matricola']),
          _s(r['luogo_struttura']),
          _s(r['link']),
          _s(r['note']),
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Visite_Mediche',
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

  Widget _exportButtonsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
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

  int? _daysUntilVisit(dynamic dataVisita) {
    final raw = parseSupabaseTimestampToItaly(dataVisita);
    if (raw == null) return null;
    final visit = DateTime(raw.year, raw.month, raw.day);
    final now = italyNow();
    final today = DateTime(now.year, now.month, now.day);
    return visit.difference(today).inDays;
  }

  bool _visitHighlighted(Map<String, dynamic> r) {
    final days = _daysUntilVisit(r['data_visita']);
    if (days == null) return false;
    if (days == 0) return true;
    return days > 0 && days <= 2;
  }

  bool _visitBlinkToday(Map<String, dynamic> r) =>
      _daysUntilVisit(r['data_visita']) == 0;

  String _rowKey(Map<String, dynamic> r, int index) {
    final id = _s(r['id_uuid']);
    if (id.isNotEmpty) return 'vm_$id';
    return 'vm_${_s(r['personale_id_uuid'])}_${_s(r['data_visita'])}_$index';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      String? myPersonaleId;
      if (_employeeOnly) {
        myPersonaleId = await EmployeeProgrammazioneService.resolveOwnPersonaleUuid(
          employeeFullName: widget.employeeFullName,
        );
        _ownPersonaleUuid = myPersonaleId;
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
      _personaleOptions.clear();
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
              .eq('active', true)
              .order('full_name', ascending: true) as List,
        );
        for (final m in personaleRes) {
          final id = _s(m['id_uuid']);
          if (id.isEmpty) continue;
          _personaleById[id] = m;
          final name = _s(m['full_name']);
          if (name.isNotEmpty) {
            _personaleOptions.add(<String, String>{'id': id, 'name': name});
          }
        }
      }

      final list = await VisiteMedicheService.loadRows(
        onlyPersonaleUuid: _employeeOnly ? myPersonaleId : null,
        rfi: _rfi,
      );
      _rows
        ..clear()
        ..addAll(list);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore caricamento: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, dynamic>>.from(_rows);
    return _rows.where((r) {
      final pid = _s(r['personale_id_uuid']);
      final p = _personaleById[pid];
      final tokens = <String>[
        _s(r['dipendente_nome']),
        _s(p?['full_name']),
        _s(p?['matricola']),
        _s(p?['telefono']),
        _s(p?['email']),
        _s(r['luogo_struttura']),
        _s(r['link']),
        _s(r['note']),
        _fmtDateTime(r['data_visita']),
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  TextStyle? get _metaStyle =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );

  Future<void> _openLink(String url) async {
    final t = url.trim();
    if (t.isEmpty) return;
    final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ModifyFeedback.error(context, 'Impossibile aprire il link.');
      }
    }
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    if (!_canEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _VisitaMedicaDialog(
        supa: Supabase.instance.client,
        row: row,
        personaleOptions: _personaleOptions,
        rfiMode: _rfi,
      ),
    );
    if (ok == true && mounted) {
      ModifyFeedback.success(
        context,
        _rfi ? 'Visita medica RFI salvata.' : 'Visita medica salvata.',
      );
      await _load();
    }
  }

  Future<void> _openRfiPage() {
    return FuturisticNavigation.pushPage(
      context,
      page: VisiteMedichePage(
        adminMode: widget.adminMode,
        employeeOnly: widget.employeeOnly,
        employeeFullName: widget.employeeFullName,
        rfiMode: true,
      ),
      title: widget.employeeOnly
          ? 'Le mie visite mediche RFI'
          : 'Visite mediche RFI',
      activeSubKey: 'visite_mediche_rfi',
    );
  }

  Future<void> _downloadVisitPdf(Map<String, dynamic> row) async {
    if (!VisiteMedicheService.hasPdf(row)) {
      ModifyFeedback.hint(context, 'Nessun PDF allegato a questa visita.');
      return;
    }
    try {
      final bytes = await VisiteMedicheService.downloadPdfBytes(row);
      final original = _s(row['pdf_file_name']);
      var base = original;
      var ext = 'pdf';
      final dot = original.lastIndexOf('.');
      if (dot > 0 && dot < original.length - 1) {
        base = original.substring(0, dot);
        ext = original.substring(dot + 1);
      }
      if (base.isEmpty) base = 'visita_medica_rfi';
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: base,
        bytes: bytes,
        extension: ext,
      );
      if (!mounted) return;
      if (saved) {
        ModifyFeedback.success(
          context,
          kIsWeb
              ? 'Download PDF avviato (controlla i download del browser).'
              : 'PDF scaricato.',
        );
      } else {
        ModifyFeedback.hint(context, 'Download annullato.');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Download PDF: $e');
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    if (!await ensureCanPersist(context)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina programmazione'),
        content: Text(
          _rfi
              ? 'Confermi eliminazione della visita medica RFI? '
                  'Verrà cancellato anche l’eventuale PDF allegato.'
              : 'Confermi eliminazione della visita medica?',
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
      await Supabase.instance.client
          .from(_table)
          .delete()
          .eq('id_uuid', row['id_uuid']);
      await _load();
      if (mounted) ModifyFeedback.success(context, 'Visita eliminata.');
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  Future<void> _openVisitDetail(Map<String, dynamic> row) async {
    final pid = _s(row['personale_id_uuid']);
    final link = _s(row['link']);
    final hasPdf = _rfi && VisiteMedicheService.hasPdf(row);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _canEdit
                ? (_rfi
                    ? 'Dettaglio visita medica RFI'
                    : 'Dettaglio visita medica')
                : (_rfi ? 'Visita medica RFI' : 'Visita medica'),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _visitDetailBlocks(row, pid),
              ),
            ),
          ),
          actions: [
            if (hasPdf)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadVisitPdf(row);
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('Scarica PDF'),
              ),
            if (link.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openLink(link);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Apri link'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_canEdit ? 'Chiudi' : 'OK'),
            ),
            if (_canEdit) ...[
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteRow(row);
                },
                child: const Text(
                  'Elimina',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openForm(row: row);
                },
                child: const Text('Modifica'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _visitDateChip(Map<String, dynamic> r, {bool compact = false}) {
    final hi = _visitHighlighted(r);
    final blinkToday = _visitBlinkToday(r);
    Color bg;
    Color fg;
    if (blinkToday) {
      bg = _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.18);
      fg = _blinkOn ? Colors.white : Colors.red.shade900;
    } else if (hi) {
      bg = Colors.red.withValues(alpha: 0.12);
      fg = Colors.red.shade900;
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
        _fmtDateTime(r['data_visita']),
        style: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _personBlock(String personaleUuid, {String fallbackName = ''}) {
    final p = _personaleById[personaleUuid];
    final name = _s(p?['full_name']).isEmpty ? fallbackName : _s(p?['full_name']);
    final matr = _s(p?['matricola']);
    final tel = _s(p?['telefono']);
    final email = _s(p?['email']);
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
      ],
    );
  }

  List<Widget> _visitDetailBlocks(Map<String, dynamic> r, String personaleUuid) {
    final link = _s(r['link']);
    final compact = _layoutCompact(context);
    final hasPdf = _rfi && VisiteMedicheService.hasPdf(r);
    return [
      if (!_employeeOnly) ...[
        _personBlock(personaleUuid, fallbackName: _s(r['dipendente_nome'])),
        const Divider(height: 16),
      ],
      _detailRow('Data e ora', _fmtDateTime(r['data_visita']), compact: compact),
      _detailRow('Luogo / struttura', _s(r['luogo_struttura']), compact: compact),
      _detailRow('Link', link.isEmpty ? '—' : link, compact: compact),
      if (_rfi)
        _detailRow(
          'PDF struttura',
          hasPdf ? _s(r['pdf_file_name']) : 'Non caricato',
          compact: compact,
        ),
      if (_s(r['note']).isNotEmpty) ...[
        const SizedBox(height: 4),
        NotePreviewText(
          note: _s(r['note']),
          prefix: 'Note: ',
          maxChars: compact ? 200 : 120,
          maxLines: compact ? 6 : 3,
        ),
      ],
      if (hasPdf) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => _downloadVisitPdf(r),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Scarica PDF'),
          ),
        ),
      ],
    ];
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
            width: 140,
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

  Widget _compactVisitCard(Map<String, dynamic> r, int index) {
    final pid = _s(r['personale_id_uuid']);
    final dipendente = _s(r['dipendente_nome']).isEmpty
        ? _s(_personaleById[pid]?['full_name'])
        : _s(r['dipendente_nome']);
    final rowKey = _rowKey(r, index);
    final expanded = _expandedRowKeys.contains(rowKey);
    final luogo = _s(r['luogo_struttura']);
    final link = _s(r['link']);
    final blinkToday = _visitBlinkToday(r);

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
        onTap: () => _openVisitDetail(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _visitDateChip(r, compact: true),
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
                          luogo.isEmpty ? 'Visita medica' : luogo,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (link.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              link,
                              style: _metaStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (_rfi && VisiteMedicheService.hasPdf(r))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'PDF: ${_s(r['pdf_file_name'])}',
                              style: _metaStyle?.copyWith(
                                color: const Color(0xFFC62828),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_rfi && VisiteMedicheService.hasPdf(r))
                    IconButton(
                      tooltip: 'Scarica PDF',
                      icon: const Icon(Icons.download_outlined, size: 20),
                      onPressed: () => _downloadVisitPdf(r),
                    ),
                  if (link.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => _openLink(link),
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
              if (expanded) ..._visitDetailBlocks(r, pid),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visitCard(Map<String, dynamic> r, int index) =>
      _compactVisitCard(r, index);

  Widget _visitDateTableCell(Map<String, dynamic> r) {
    final hi = _visitHighlighted(r);
    final blinkToday = _visitBlinkToday(r);
    Color bg;
    Color fg;
    if (blinkToday) {
      bg = _blinkOn ? Colors.red : Colors.red.withValues(alpha: 0.14);
      fg = _blinkOn ? Colors.white : Colors.red.shade900;
    } else if (hi) {
      bg = Colors.red.withValues(alpha: 0.1);
      fg = Colors.red.shade900;
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
        _fmtDateTime(r['data_visita']),
        style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 13),
      ),
    );
  }

  Color? _dataRowFillColor(Map<String, dynamic> r) {
    if (_visitBlinkToday(r)) {
      return _blinkOn
          ? Colors.red.withValues(alpha: 0.22)
          : Colors.red.withValues(alpha: 0.06);
    }
    return null;
  }

  Widget _desktopTable(List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 10,
        headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
        columns: [
          const DataColumn(label: Text('Data e ora')),
          const DataColumn(label: Text('Dipendente')),
          const DataColumn(label: Text('Luogo / struttura')),
          const DataColumn(label: Text('Link')),
          if (_rfi) const DataColumn(label: Text('PDF')),
          const DataColumn(label: Text('Note')),
          if (widget.adminMode) const DataColumn(label: Text('Azioni')),
        ],
        rows: items.map((r) {
          final link = _s(r['link']);
          final hasPdf = _rfi && VisiteMedicheService.hasPdf(r);
          final nome = _s(r['dipendente_nome']).isEmpty
              ? _s(_personaleById[_s(r['personale_id_uuid'])]?['full_name'])
              : _s(r['dipendente_nome']);
          final cells = <DataCell>[
            DataCell(_visitDateTableCell(r)),
            DataCell(Text(nome)),
            DataCell(
              Text(
                _s(r['luogo_struttura']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(
              link.isEmpty
                  ? const Text('—')
                  : TextButton(
                      onPressed: () => _openLink(link),
                      child: const Text('Apri'),
                    ),
            ),
            if (_rfi)
              DataCell(
                hasPdf
                    ? TextButton.icon(
                        onPressed: () => _downloadVisitPdf(r),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Scarica'),
                      )
                    : const Text('—'),
              ),
            DataCell(
              Text(
                _s(r['note']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ];
          if (widget.adminMode) {
            cells.add(
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
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
            );
          }
          return DataRow(
            color: WidgetStateProperty.all(_dataRowFillColor(r)),
            onSelectChanged: (_) => _openVisitDetail(r),
            cells: cells,
          );
        }).toList(),
      ),
    );
  }

  String _title() {
    if (_rfi) {
      if (widget.employeeOnly) return 'Le mie visite mediche RFI';
      if (widget.adminMode) return 'Visite mediche RFI';
      return 'Riepilogo visite mediche RFI';
    }
    if (widget.employeeOnly) return 'La mia visita medica';
    if (widget.adminMode) return 'Programmazione visite mediche';
    return 'Riepilogo visite mediche';
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredRows;
    final compact = _layoutCompact(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(title: _title()),
        actions: [
          if (!_rfi && !_employeeOnly)
            IconButton(
              tooltip: 'Visite mediche RFI',
              onPressed: _openRfiPage,
              icon: const Icon(Icons.medical_information_outlined),
            ),
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
                      ? (_rfi
                          ? 'Le tue visite mediche RFI. Puoi scaricare il PDF '
                              'rilasciato dalla struttura.'
                          : 'Le tue visite mediche programmate dall’amministrazione.')
                      : widget.adminMode
                          ? (_rfi
                              ? 'Inserisci le visite mediche RFI e allega il PDF '
                                  'della struttura da trasmettere al dipendente.'
                              : 'Inserisci e gestisci le visite mediche dei dipendenti.')
                          : (_rfi
                              ? 'Riepilogo di tutte le visite mediche RFI programmate.'
                              : 'Riepilogo di tutte le visite mediche programmate.'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (!_rfi && !_employeeOnly) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: FilledButton.tonalIcon(
                      onPressed: _openRfiPage,
                      icon: const Icon(Icons.medical_information_outlined),
                      label: const Text('Apri visite mediche RFI'),
                    ),
                  ),
                ],
                if (!_employeeOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ordinate per data visita. Evidenziazione rossa entro 2 giorni; '
                    'lampeggiante se la visita è oggi.',
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
                    ? 'Cerca luogo, data, link…'
                    : 'Cerca dipendente, luogo, link…',
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
                          (_ownPersonaleUuid == null ||
                              _ownPersonaleUuid!.isEmpty)
                      ? 'Anagrafica non collegata: impossibile mostrare le visite.'
                      : _rows.isEmpty
                          ? (_employeeOnly
                              ? 'Nessuna visita medica programmata a tuo nome.'
                              : 'Nessuna visita programmata.')
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
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
                        itemCount: items.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${items.length} visite programmate',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  _exportButtonsRow(),
                                ],
                              ),
                            );
                          }
                          return _visitCard(items[i - 1], i - 1);
                        },
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '${items.length} visite programmate',
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
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
      floatingActionButton: widget.adminMode
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text(_rfi ? 'Nuova visita RFI' : 'Nuova visita'),
            )
          : null,
    );
  }
}

class _VisitaMedicaDialog extends StatefulWidget {
  final SupabaseClient supa;
  final Map<String, dynamic>? row;
  final List<Map<String, String>> personaleOptions;
  final bool rfiMode;

  const _VisitaMedicaDialog({
    required this.supa,
    required this.personaleOptions,
    this.row,
    this.rfiMode = false,
  });

  @override
  State<_VisitaMedicaDialog> createState() => _VisitaMedicaDialogState();
}

class _VisitaMedicaDialogState extends State<_VisitaMedicaDialog> {
  final _dataCtrl = TextEditingController();
  final _oraCtrl = TextEditingController();
  final _luogoCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selPersonaleUuid;
  bool _saving = false;
  DateTime? _visitDate;
  String? _existingPdfName;
  String? _existingPdfPath;
  String? _pickedPdfName;
  Uint8List? _pickedPdfBytes;
  bool _removeExistingPdf = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.row;
    if (ex != null) {
      _selPersonaleUuid = (ex['personale_id_uuid'] ?? '').toString().trim();
      final dt = parseSupabaseTimestampToItaly(ex['data_visita']);
      if (dt != null) {
        _visitDate = DateTime(dt.year, dt.month, dt.day);
        _dataCtrl.text = formatDateDdMmYyyyFromDate(dt);
        _oraCtrl.text = formatTimeHhMmFromIso(dt);
      }
      _luogoCtrl.text = (ex['luogo_struttura'] ?? '').toString();
      _linkCtrl.text = (ex['link'] ?? '').toString();
      _noteCtrl.text = (ex['note'] ?? '').toString();
      _existingPdfName = (ex['pdf_file_name'] ?? '').toString().trim();
      _existingPdfPath = (ex['pdf_file_path'] ?? '').toString().trim();
      if ((_existingPdfName ?? '').isEmpty) _existingPdfName = null;
      if ((_existingPdfPath ?? '').isEmpty) _existingPdfPath = null;
    } else {
      final now = DateTime.now();
      _visitDate = DateTime(now.year, now.month, now.day);
      _dataCtrl.text = formatDateDdMmYyyyFromDate(now);
      _oraCtrl.text = '09:00';
    }
  }

  TimeOfDay get _initialTimeOfDay {
    final parts = _oraCtrl.text.trim().split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 9;
      final m = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _pickDataVisita() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('it', 'IT'),
      initialDate: _visitDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _visitDate = picked;
      _dataCtrl.text = formatDateDdMmYyyyFromDate(picked);
    });
  }

  Future<void> _pickOraVisita() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _initialTimeOfDay,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('it', 'IT'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _oraCtrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  void dispose() {
    _dataCtrl.dispose();
    _oraCtrl.dispose();
    _luogoCtrl.dispose();
    _linkCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? _nomeForUuid(String? uuid) {
    if ((uuid ?? '').isEmpty) return null;
    for (final o in widget.personaleOptions) {
      if (o['id'] == uuid) return o['name'];
    }
    return null;
  }

  Future<void> _pickPdf() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (!VisiteMedicheService.isAllowedPdfName(file.name)) {
      ModifyFeedback.error(context, 'Seleziona un file PDF.');
      return;
    }
    setState(() {
      _pickedPdfName = file.name;
      _pickedPdfBytes = bytes;
      _removeExistingPdf = false;
    });
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final pid = (_selPersonaleUuid ?? '').trim();
    final luogo = _luogoCtrl.text.trim();
    if (pid.isEmpty) {
      ModifyFeedback.error(context, 'Seleziona un dipendente.');
      return;
    }
    if (luogo.isEmpty) {
      ModifyFeedback.error(context, 'Inserisci luogo o struttura.');
      return;
    }
    final iso = parseDateAndTimeToIso(_dataCtrl.text, _oraCtrl.text);
    if (iso == null) {
      ModifyFeedback.error(
        context,
        'Data (gg/mm/aaaa) e ora (HH:mm) non valide.',
      );
      return;
    }
    final nome = _nomeForUuid(pid) ?? '';
    final table = VisiteMedicheService.tableName(rfi: widget.rfiMode);
    final payload = <String, dynamic>{
      'personale_id_uuid': pid,
      'dipendente_nome': nome.isEmpty ? null : nome,
      'data_visita': iso,
      'luogo_struttura': luogo,
      'link': _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'active': true,
    };
    setState(() => _saving = true);
    try {
      String visitId;
      if (widget.row == null) {
        final inserted = await widget.supa
            .from(table)
            .insert(payload)
            .select('id_uuid')
            .single();
        visitId = (inserted['id_uuid'] ?? '').toString();
      } else {
        visitId = (widget.row!['id_uuid'] ?? '').toString();
        await widget.supa.from(table).update(payload).eq('id_uuid', visitId);
      }

      if (widget.rfiMode && visitId.isNotEmpty) {
        if (_pickedPdfBytes != null && (_pickedPdfName ?? '').isNotEmpty) {
          await VisiteMedicheService.uploadPdf(
            visitId: visitId,
            originalFileName: _pickedPdfName!,
            bytes: _pickedPdfBytes!,
            previousFilePath: _existingPdfPath,
          );
        } else if (_removeExistingPdf && (_existingPdfPath ?? '').isNotEmpty) {
          await VisiteMedicheService.clearPdf(
            visitId: visitId,
            filePath: _existingPdfPath,
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pdfPickerSection() {
    final currentName = _pickedPdfName ??
        (!_removeExistingPdf ? _existingPdfName : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'PDF struttura',
            border: OutlineInputBorder(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentName == null
                    ? 'Nessun PDF selezionato'
                    : 'File: $currentName',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickPdf,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      currentName == null ? 'Carica PDF' : 'Sostituisci PDF',
                    ),
                  ),
                  if (currentName != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _pickedPdfName = null;
                                _pickedPdfBytes = null;
                                if (_existingPdfPath != null) {
                                  _removeExistingPdf = true;
                                }
                              }),
                      child: const Text('Rimuovi'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'PDF rilasciato dalla struttura da trasmettere al dipendente.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.personaleOptions;
    final isRfi = widget.rfiMode;
    return AlertDialog(
      title: Text(
        widget.row == null
            ? (isRfi ? 'Nuova visita medica RFI' : 'Nuova visita medica')
            : (isRfi ? 'Modifica visita medica RFI' : 'Modifica visita medica'),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownSearch<String>(
                selectedItem: _selPersonaleUuid,
                items: items.map((e) => e['id']!).toList(),
                itemAsString: (id) {
                  for (final o in items) {
                    if (o['id'] == id) return o['name']!;
                  }
                  return id;
                },
                compareFn: (a, b) => a == b,
                dropdownDecoratorProps: const DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: 'Dipendente *',
                    border: OutlineInputBorder(),
                  ),
                ),
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  constraints: BoxConstraints(
                    maxHeight: kIsWeb ? 320 : 400,
                  ),
                ),
                onChanged: (v) => setState(() => _selPersonaleUuid = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dataCtrl,
                readOnly: true,
                onTap: _pickDataVisita,
                decoration: const InputDecoration(
                  labelText: 'Data visita *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _oraCtrl,
                readOnly: true,
                onTap: _pickOraVisita,
                decoration: const InputDecoration(
                  labelText: 'Ora *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.schedule_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _luogoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Luogo / struttura *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link (maps, portale, ecc.)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isRfi) _pdfPickerSection(),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
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
