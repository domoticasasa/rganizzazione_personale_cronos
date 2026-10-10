import 'dart:async';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/formazione_rfi_strutture_service.dart';
import '../services/notification_sender.dart';
import '../services/supabase_service.dart';
import '../widgets/rfi_struttura_selector.dart';
import 'admin_formazione_rfi_strutture_page.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/field_timestamps.dart';
import '../utils/users_directory.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../Mobile/admin_gestione_dipendenti_mobile.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../utils/mobile_navigation.dart';
import '../utils/responsive.dart';
import 'admin_gestione_dipendenti_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

class _DateSlashInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      buffer.write(digits[i]);
      if ((i == 1 || i == 3) && i != 7) {
        buffer.write('/');
      }
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AdminFormazioneRfiPage extends StatefulWidget {
  final bool readOnly;
  const AdminFormazioneRfiPage({super.key, this.readOnly = false});

  @override
  State<AdminFormazioneRfiPage> createState() => _AdminFormazioneRfiPageState();
}

class _AdminFormazioneRfiPageState extends State<AdminFormazioneRfiPage> {
  static const String _filter60 = '60';
  static const String _filter45 = '45';
  static const String _filterExpired = 'expired';
  static const List<String> _firstReleaseOptions = <String>[
    'Primo rilascio',
    'Aggiornamento',
  ];

  static const List<String> _modalitaOptions = <String>[
    'Online',
    'In presenza',
  ];

  static const List<String> _trackOrderHints = <String>[
    'profili rfi mi mepc',
    'profili rfi agenti ia pl',
    'profili rfi mdo ditte',
    'profili rfi qp mett',
    'profili rfi te ditte 3kv',
    'profili rfi te ditte 3 e 25kv',
    'profili rfi is0',
    'mi tes ma es s ben',
    'mepc ia fnm',
    'mi ia mo fnm',
    'conversione abilitazione fse',
    'conversione abilitazione eav',
  ];

  static const List<String> _fieldOrderHints = <String>[
    'data attestato',
    'definizione',
    'data consegna',
    'mantenimento 1',
    'rinnovo',
    'prossima scadenza',
    'scadenza',
    'note',
  ];
  /// Campi programmazione: solo in «Modifica formazione», non in plancia.
  static const Set<String> _programmazioneFieldKeys = <String>{
    'data_programmazione_dal',
    'data_programmazione_al',
    'data_programmazione_corso',
    'oda',
    'orario',
    'modalita',
    ...FormazioneRfiStruttureService.recordFieldKeys,
  };

  static const Set<String> _strutturaMetaFieldKeys = <String>{
    'struttura_rfi_id',
    'struttura_nome',
    'struttura_indirizzo',
  };

  /// Aggiunti al form di modifica se mancano nel corso.
  static const List<String> _editFormExtraFields = <String>[
    'data_programmazione_dal',
    'data_programmazione_al',
    'oda',
    'orario',
    'modalita',
    ...FormazioneRfiStruttureService.recordFieldKeys,
  ];

  static const List<String> _programmazioneResetFields = <String>[
    'data_programmazione_dal',
    'data_programmazione_al',
    'oda',
    'orario',
    'modalita',
    ...FormazioneRfiStruttureService.recordFieldKeys,
    'note',
  ];

  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _syncingH = false;
  bool _syncingV = false;
  bool _loading = true;
  bool _blinkOn = false;
  Timer? _blinkTimer;
  String? _expiryFilter;
  /// Track/formazione selezionata (null = tutte).
  String? _trackFilter;

  final Map<int, String> _personaleNameById = <int, String>{};
  final Map<int, String> _personaleUuidById = <int, String>{};
  final List<String> _tracks = <String>[];
  final Map<String, List<String>> _fieldsByTrack = <String, List<String>>{};
  final Map<String, String> _cellByCompositeKey = <String, String>{};
  final Map<String, Map<String, dynamic>> _cellRowByCompositeKey =
      <String, Map<String, dynamic>>{};
  final Map<String, String> _auditUserNamesByUuid = <String, String>{};

  List<Map<String, dynamic>> _people = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rfiStrutture = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _bindScroll();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _load();
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    _leftV.dispose();
    _rightV.dispose();
    _searchCtrl.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportExcel() async {
    try {
      final q = _searchCtrl.text.trim().toLowerCase();
      final visiblePeople = _people.where((p) {
        final nameOk = q.isEmpty || (p['name'] as String).toLowerCase().contains(q);
        if (!nameOk) return false;
        final uuid = (p['uuid'] ?? '').toString();
        return _personMatchesExpiryFilter(uuid);
      }).toList();
      if (visiblePeople.isEmpty) {
        _snack('Nessun dato da esportare', error: true);
        return;
      }
      final excel = Excel.createExcel();
      final sheet = excel['Formazione_RFI'];
      final header = <String>['Dipendente'];
      for (final t in _visibleTracks) {
        final fields = _visibleFieldsForTrack(t);
        if (fields.isEmpty) continue;
        for (final f in fields) {
          header.add('$t - $f');
        }
      }
      sheet.appendRow(header);
      for (final p in visiblePeople) {
        final uuid = (p['uuid'] ?? '').toString();
        final row = <dynamic>[(p['name'] ?? '').toString()];
        for (final t in _visibleTracks) {
          final fields = _visibleFieldsForTrack(t);
          if (fields.isEmpty) continue;
          for (final f in fields) {
            row.add(_cellByCompositeKey[_cellKey(uuid, t, f)] ?? '');
          }
        }
        sheet.appendRow(row);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Formazione_RFI',
        bytes: bytes,
      );
      if (!saved) return;
      _snack('Export Excel completato: ${ExcelExportHelper.lastSavedPath ?? ''}');
    } catch (e) {
      _snack('Errore export Excel: $e', error: true);
    }
  }

  void _bindScroll() {
    _headerH.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_bodyH.hasClients) _bodyH.jumpTo(_headerH.offset);
      _syncingH = false;
    });
    _bodyH.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_headerH.hasClients) _headerH.jumpTo(_bodyH.offset);
      _syncingH = false;
    });
    _leftV.addListener(() {
      if (_syncingV) return;
      _syncingV = true;
      if (_rightV.hasClients) _rightV.jumpTo(_leftV.offset);
      _syncingV = false;
    });
    _rightV.addListener(() {
      if (_syncingV) return;
      _syncingV = true;
      if (_leftV.hasClients) _leftV.jumpTo(_rightV.offset);
      _syncingV = false;
    });
    _searchCtrl.addListener(() => setState(() {}));
  }

  String _labelFromField(String field) {
    final f = field.trim();
    if (f.isEmpty) return '';
    final n = _normalizeForSort(f);
    if (n == 'prossima scadenza' ||
        (n.contains('prossima') &&
            n.contains('scadenza') &&
            !n.contains('mantenimento') &&
            !n.startsWith('rinnovo'))) {
      return 'PROSSIMA SCADENZA MANTENIMENTO';
    }
    if (n.startsWith('rinnovo')) {
      return 'PROSSIMA SCADENZA RINNUOVI';
    }
    return f.replaceAll('_', ' ').toUpperCase();
  }

  /// Mantenimento 2/3 non più usati (rimossi da plancia e modifica).
  bool _isRetiredFieldKey(String field) {
    final n = _normalizeForSort(field);
    return n.contains('mantenimento 2') || n.contains('mantenimento 3');
  }

  String _normalizeForSort(String value) {
    final lower = value.toLowerCase().replaceAll('_', ' ');
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _priorityFromHints(String value, List<String> hints) {
    final normalized = _normalizeForSort(value);
    for (var i = 0; i < hints.length; i++) {
      if (normalized.contains(hints[i])) return i;
    }
    return hints.length + 1;
  }

  int _trackPriority(String track) => _priorityFromHints(track, _trackOrderHints);

  int _fieldPriority(String field) => _priorityFromHints(field, _fieldOrderHints);

  bool _isProgrammazioneFieldKey(String field) {
    final key = field.trim();
    if (_programmazioneFieldKeys.contains(key)) return true;
    final n = _normalizeForSort(key);
    return n.contains('data programmazione') ||
        n == 'orario' ||
        n.contains('modalita') ||
        n.contains('struttura link') ||
        n == 'oda';
  }

  /// Colonne visibili in plancia (esclude programmazione).
  List<String> _visibleFieldsForTrack(String track) {
    final fields = _fieldsByTrack[track] ?? const <String>[];
    return fields
        .where((f) => !_isProgrammazioneFieldKey(f) && !_isRetiredFieldKey(f))
        .toList(growable: false);
  }

  String _formatExcelLikeCellValue(dynamic valueDate, String valueText) {
    if (valueDate != null && valueDate.toString().trim().isNotEmpty) {
      return formatDateDdMmYyyy(valueDate);
    }
    final raw = valueText.trim();
    if (raw.isEmpty) return '';

    final plainDate = DateTime.tryParse(raw);
    if (plainDate != null) return formatDateDdMmYyyy(plainDate);

    final dateOnlyMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (dateOnlyMatch != null) {
      final parsed = DateTime.tryParse(
        '${dateOnlyMatch.group(1)}-${dateOnlyMatch.group(2)}-${dateOnlyMatch.group(3)}',
      );
      if (parsed != null) return formatDateDdMmYyyy(parsed);
    }
    final itDateMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(raw);
    if (itDateMatch != null) {
      return '${itDateMatch.group(1)}/${itDateMatch.group(2)}/${itDateMatch.group(3)}';
    }
    return raw;
  }

  DateTime? _tryParseDateLike(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final iso = parseFlexibleDateToIsoDate(value);
    if (iso != null) return DateTime.tryParse(iso);
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(value);
    if (m == null) return null;
    final d = int.tryParse(m.group(1)!);
    final mon = int.tryParse(m.group(2)!);
    final y = int.tryParse(m.group(3)!);
    if (d == null || mon == null || y == null) return null;
    return DateTime(y, mon, d);
  }

  Color? _dateBgForScadenza(String field, String value, Color oddRowBg) {
    final normalized = _normalizeForSort(field);
    if (!normalized.contains('scadenza')) return null;
    final dt = _tryParseDateLike(value);
    if (dt == null) return null;
    final today = DateTime.now();
    final ref = DateTime(today.year, today.month, today.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final days = target.difference(ref).inDays;
    if (days < 0) return _blinkOn ? Colors.red.shade700 : Colors.red.shade300;
    if (days <= 45) return Colors.red.shade200;
    if (days <= 60) return Colors.yellow.shade200;
    if (days > 180) return Colors.green.shade200;
    return oddRowBg == Colors.transparent ? null : oddRowBg;
  }

  bool _personMatchesExpiryFilter(String personaleUuid) {
    if (_expiryFilter == null) return true;
    final tracks = _visibleTracks;
    for (final track in tracks) {
      final fields = _fieldsByTrack[track] ?? const <String>[];
      for (final field in fields) {
        final normalized = _normalizeForSort(field);
        if (!normalized.contains('scadenza')) continue;
        final value = _cellByCompositeKey[_cellKey(personaleUuid, track, field)] ?? '';
        final dt = _tryParseDateLike(value);
        if (dt == null) continue;
        final today = DateTime.now();
        final ref = DateTime(today.year, today.month, today.day);
        final target = DateTime(dt.year, dt.month, dt.day);
        final days = target.difference(ref).inDays;
        if (_expiryFilter == _filterExpired && days < 0) return true;
        if (_expiryFilter == _filter45 && days >= 0 && days <= 45) return true;
        if (_expiryFilter == _filter60 && days >= 0 && days <= 60) return true;
      }
    }
    return false;
  }

  List<String> get _visibleTracks {
    final selected = (_trackFilter ?? '').trim();
    if (selected.isEmpty) return List<String>.from(_tracks);
    if (_tracks.contains(selected)) return <String>[selected];
    return List<String>.from(_tracks);
  }

  String _cellKey(String personaleUuid, String track, String field) {
    return '$personaleUuid|$track|$field';
  }

  DateTime? _rowDateValue(Map<String, dynamic> row) {
    final dateRaw = (row['value_date'] ?? '').toString().trim();
    if (dateRaw.isNotEmpty) {
      final dt = DateTime.tryParse(dateRaw);
      if (dt != null) return DateTime(dt.year, dt.month, dt.day);
    }
    final textRaw = (row['value_text'] ?? '').toString().trim();
    if (textRaw.isEmpty) return null;
    final parsed = _tryParseDateLike(textRaw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Future<bool> _cleanupExpiredProgrammazioneRows(List<Map<String, dynamic>> records) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final pid = (r['personale_id'] ?? '').toString().trim();
      final track = (r['track_key'] ?? '').toString().trim();
      if (pid.isEmpty || track.isEmpty) continue;
      byKey.putIfAbsent('$pid|$track', () => <Map<String, dynamic>>[]).add(r);
    }

    var changed = false;
    for (final rows in byKey.values) {
      final dalRow = rows.cast<Map<String, dynamic>>().firstWhere(
        (r) => (r['field_key'] ?? '').toString().trim() == 'data_programmazione_dal',
        orElse: () => <String, dynamic>{},
      );
      final alRow = rows.cast<Map<String, dynamic>>().firstWhere(
        (r) => (r['field_key'] ?? '').toString().trim() == 'data_programmazione_al',
        orElse: () => <String, dynamic>{},
      );
      final legacyRow = rows.cast<Map<String, dynamic>>().firstWhere(
        (r) =>
            (r['field_key'] ?? '').toString().trim() ==
            'data_programmazione_corso',
        orElse: () => <String, dynamic>{},
      );
      final dalDate = dalRow.isNotEmpty ? _rowDateValue(dalRow) : null;
      final alDate = alRow.isNotEmpty ? _rowDateValue(alRow) : null;
      final legacyDate =
          legacyRow.isNotEmpty ? _rowDateValue(legacyRow) : null;
      final scheduleEnd = alDate ?? dalDate ?? legacyDate;
      if (scheduleEnd == null) continue;
      final resetFrom = scheduleEnd.add(const Duration(days: 1));
      if (today.isBefore(resetFrom)) continue;

      final pid = (dalRow.isNotEmpty
              ? dalRow['personale_id']
              : alRow.isNotEmpty
                  ? alRow['personale_id']
                  : legacyRow['personale_id'])
          .toString()
          .trim();
      final track = (dalRow.isNotEmpty
              ? dalRow['track_key']
              : alRow.isNotEmpty
                  ? alRow['track_key']
                  : legacyRow['track_key'])
          .toString()
          .trim();
      if (pid.isEmpty || track.isEmpty) continue;

      for (final field in _programmazioneResetFields) {
        await SupabaseService.client
            .from('formazione_rfi_records')
            .delete()
            .eq('personale_id', pid)
            .eq('track_key', track)
            .eq('field_key', field);
      }
      changed = true;
    }
    return changed;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _notifyEmployeeRfiChange({
    required int personaleId,
    required String action,
    required String track,
  }) async {
    final personaleUuid = _personaleUuidById[personaleId];
    if (personaleUuid == null || personaleUuid.trim().isEmpty) return;
    await NotificationSender.notifyEmployeeFormazioneChange(
      personaleId: personaleUuid,
      formazioneId: personaleId,
      action: action,
      title: action == 'delete'
          ? 'Formazione RFI eliminata'
          : 'Formazione RFI aggiornata',
      message: 'Corso: $track',
    );
  }

  Future<void> _addColumn() async {
    final trackCtrl = TextEditingController();
    final fieldCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Nuova colonna RFI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: trackCtrl,
                decoration: const InputDecoration(labelText: 'Nome tab/blocco'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fieldCtrl,
                decoration: const InputDecoration(labelText: 'Nome sotto-colonna'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aggiungi')),
          ],
        );
      },
    );
    if (ok != true) return;
    final track = trackCtrl.text.trim();
    final field = fieldCtrl.text.trim();
    if (track.isEmpty || field.isEmpty) {
      _snack('Inserisci tab e sotto-colonna', error: true);
      return;
    }
    if (_isProgrammazioneFieldKey(field)) {
      _snack(
        'I campi programmazione si gestiscono solo in Modifica formazione',
        error: true,
      );
      return;
    }
    setState(() {
      if (!_tracks.contains(track)) _tracks.add(track);
      final list = _fieldsByTrack.putIfAbsent(track, () => <String>[]);
      if (!list.contains(field)) list.add(field);
      _tracks.sort((a, b) {
        final pa = _trackPriority(a);
        final pb = _trackPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
      for (final t in _tracks) {
        final fields = _fieldsByTrack[t];
        if (fields == null) continue;
        fields.sort((a, b) {
          final pa = _fieldPriority(a);
          final pb = _fieldPriority(b);
          if (pa != pb) return pa.compareTo(pb);
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
      }
    });
    _snack('Colonna aggiunta. Tocca una cella per inserire il valore');
  }

  Future<void> _openPersonSummary({
    required int personaleId,
    required String personaleUuid,
    required String name,
  }) async {
    final items = _tracks.map((track) {
      final fields = _visibleFieldsForTrack(track);
      final values = <String, String>{};
      for (final f in fields) {
        values[f] = _cellByCompositeKey[_cellKey(personaleUuid, track, f)] ?? '';
      }
      for (final pf in _editFormExtraFields) {
        values[pf] = _cellByCompositeKey[_cellKey(personaleUuid, track, pf)] ?? '';
      }
      return <String, dynamic>{
        'track': track,
        'fields': fields,
        'values': values,
      };
    }).where((e) {
      final values = (e['values'] as Map<String, String>).values;
      return values.any((v) => v.trim().isNotEmpty);
    }).toList(growable: false);

    TextStyle scadTextStyle(String value) {
      final dt = _tryParseDateLike(value);
      if (dt == null) return const TextStyle();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(dt.year, dt.month, dt.day);
      final days = target.difference(today).inDays;
      if (days < 0) return const TextStyle(color: Colors.red, fontWeight: FontWeight.w700);
      if (days <= 45) return TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700);
      if (days <= 60) return TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w700);
      return TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700);
    }

    String val(Map<String, String> values, String key) {
      final v = (values[key] ?? '').trim();
      return v.isEmpty ? '-' : v;
    }

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
                ? const Center(child: Text('Nessun dato RFI disponibile'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final track = (it['track'] ?? '').toString();
                      final fields = (it['fields'] as List).cast<String>();
                      final values = (it['values'] as Map).cast<String, String>();
                      final summaryFields = List<String>.from(
                        fields.isEmpty ? values.keys : fields,
                      );
                      for (final af in _editFormExtraFields) {
                        if (!summaryFields.contains(af)) summaryFields.add(af);
                      }
                      final mainDateFields = summaryFields
                          .where(
                            (f) =>
                                _normalizeForSort(f).contains('data attestato') ||
                                _normalizeForSort(f).contains('mantenimento') ||
                                _normalizeForSort(f).contains('rinnovo') ||
                                _normalizeForSort(f).contains('scadenza'),
                          )
                          .toList(growable: false);
                      final detailFields = <String>[
                        'ente',
                        'primo_rilascio_aggiornamento',
                        'data_programmazione_dal',
                        'data_programmazione_al',
                        'oda',
                        'orario',
                        'modalita',
                        'struttura_link',
                      ];
                      final extraFields = summaryFields
                          .where(
                            (f) =>
                                !mainDateFields.contains(f) &&
                                !detailFields.contains(f) &&
                                _normalizeForSort(f) != 'note',
                          )
                          .toList(growable: false);
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
                              track,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Date principali',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: mainDateFields.map((f) {
                                final raw = val(values, f);
                                final label = _labelFromField(f);
                                final isScad = _normalizeForSort(f).contains('scadenza');
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                                      children: [
                                        TextSpan(
                                          text: '$label: ',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        TextSpan(
                                          text: raw,
                                          style: isScad ? scadTextStyle(raw) : const TextStyle(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(growable: false),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Dettagli',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: detailFields.map((f) {
                                return Text(
                                  '${_labelFromField(f)}: ${val(values, f)}',
                                  style: const TextStyle(fontSize: 13),
                                );
                              }).toList(growable: false),
                            ),
                            if (extraFields.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Altri campi',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                children: extraFields.map((f) {
                                  return Text(
                                    '${_labelFromField(f)}: ${val(values, f)}',
                                    style: const TextStyle(fontSize: 13),
                                  );
                                }).toList(growable: false),
                              ),
                            ],
                            const SizedBox(height: 8),
                            NotePreviewText(
                              note: val(values, 'note'),
                              prefix: 'Note: ',
                              maxChars: 10,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                              emptyText: 'Note: -',
                            ),
                            if (!widget.readOnly) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      await _openFullEditor(
                                        personaleId: personaleId,
                                        personaleUuid: personaleUuid,
                                        track: track,
                                        field: fields.isEmpty ? 'data_attestato' : fields.first,
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
                                            'Vuoi eliminare il corso "$track" per questo dipendente?',
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
                                      await SupabaseService.client
                                          .from('formazione_rfi_records')
                                          .delete()
                                          .eq('personale_id', personaleId)
                                          .eq('track_key', track);
                                      await _notifyEmployeeRfiChange(
                                        personaleId: personaleId,
                                        action: 'delete',
                                        track: track,
                                      );
                                      if (!context.mounted) return;
                                      Navigator.of(ctx).pop();
                                      await _load();
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

  String _cellValue(String uuid, String track, String field) {
    return _cellByCompositeKey[_cellKey(uuid, track, field)] ?? '';
  }

  Future<void> _upsertField({
    required int personaleId,
    required String track,
    required String field,
    required String rawValue,
  }) async {
    final raw = rawValue.trim();
    if (raw.isEmpty) {
      await SupabaseService.client
          .from('formazione_rfi_records')
          .delete()
          .eq('personale_id', personaleId)
          .eq('track_key', track)
          .eq('field_key', field);
      return;
    }
    final isoDate = parseFlexibleDateToIsoDate(raw);
    await SupabaseService.client.from('formazione_rfi_records').upsert(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'personale_id': personaleId,
          'track_key': track,
          'field_key': field,
          'value_date': isoDate,
          'value_text': raw,
          'source_file': 'app_manual',
          'updated_at': supabaseNowIsoUtc(),
        },
      ],
      onConflict: 'personale_id,track_key,field_key',
    );
  }

  Future<void> _openFullEditor({
    required int personaleId,
    required String personaleUuid,
    required String track,
    required String field,
  }) async {
    final personOptions = _people
        .map((e) => <String, dynamic>{
              'id': e['id'],
              'uuid': e['uuid'],
              'name': e['name'],
            })
        .toList(growable: false);

    int selectedPersonId = personaleId;
    String selectedTrack = track;
    final Map<String, TextEditingController> fieldCtrls =
        <String, TextEditingController>{};
    final List<String> currentFields = <String>[];
    final corsoCtrl = TextEditingController(text: selectedTrack);
    void disposeEditors() {
      for (final c in fieldCtrls.values) {
        c.dispose();
      }
      fieldCtrls.clear();
      corsoCtrl.dispose();
    }

    List<String> fieldsForTrack(String t) {
      final base = List<String>.from(_fieldsByTrack[t] ?? const <String>[])
          .where((f) => !_isRetiredFieldKey(f))
          .toList();
      if (base.isEmpty && !_isRetiredFieldKey(field)) base.add(field);
      if (!base.contains(field) && !_isRetiredFieldKey(field)) {
        base.insert(0, field);
      }
      for (final af in _editFormExtraFields) {
        if (!base.contains(af)) base.add(af);
      }
      return base;
    }

    void rebuildEditors() {
      for (final c in fieldCtrls.values) {
        c.dispose();
      }
      fieldCtrls.clear();
      currentFields
        ..clear()
        ..addAll(fieldsForTrack(selectedTrack));
      final uuid = (_personaleUuidById[selectedPersonId] ?? personaleUuid).trim();
      for (final f in currentFields) {
        var text = _cellValue(uuid, selectedTrack, f);
        if (f == 'data_programmazione_dal' && text.isEmpty) {
          text = _cellValue(uuid, selectedTrack, 'data_programmazione_corso');
        }
        if (f == 'data_programmazione_al' && text.isEmpty) {
          final dal = _cellValue(uuid, selectedTrack, 'data_programmazione_dal');
          final legacy = _cellValue(uuid, selectedTrack, 'data_programmazione_corso');
          if (dal.isNotEmpty) {
            text = dal;
          } else if (legacy.isNotEmpty) {
            text = legacy;
          }
        }
        fieldCtrls[f] = TextEditingController(text: text);
      }
      for (final f in FormazioneRfiStruttureService.recordFieldKeys) {
        fieldCtrls.putIfAbsent(
          f,
          () => TextEditingController(text: _cellValue(uuid, selectedTrack, f)),
        );
      }
    }

    bool isFirstReleaseField(String f) =>
        _normalizeForSort(f).contains('primo rilascio') ||
        _normalizeForSort(f).contains('aggiornamento');
    bool isModalitaField(String f) => _normalizeForSort(f).contains('modalita');

    rebuildEditors();

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final personValue = personOptions.any((p) => p['id'] == selectedPersonId)
                ? selectedPersonId
                : null;
            final corsoValue = _tracks.contains(selectedTrack) ? selectedTrack : null;
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              title: const Text('Modifica formazione RFI'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: personValue,
                        decoration: const InputDecoration(
                          labelText: 'Dipendente',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: personOptions
                            .map(
                              (p) => DropdownMenuItem<int>(
                                value: p['id'] as int,
                                child: Text((p['name'] ?? '').toString()),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() {
                            selectedPersonId = v;
                            rebuildEditors();
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: corsoValue,
                        decoration: const InputDecoration(
                          labelText: 'Corso',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: _tracks
                            .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() {
                            selectedTrack = v;
                            corsoCtrl.text = v;
                            rebuildEditors();
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: corsoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Corso (testo libero)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onChanged: (v) {
                          setLocal(() {
                            selectedTrack = v.trim();
                            rebuildEditors();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoCols = constraints.maxWidth >= 680;
                          final fieldWidth =
                              twoCols ? (constraints.maxWidth - 8) / 2 : constraints.maxWidth;

                          Widget buildField(String f) {
                            final ctrl = fieldCtrls[f]!;
                            final label = _labelFromField(f);
                            final normalized = _normalizeForSort(f);
                            final dateLike = normalized.contains('data') ||
                                normalized.contains('scadenza') ||
                                normalized.contains('rinnovo') ||
                                normalized.contains('mantenimento');
                            final isWideField = normalized.contains('note') ||
                                normalized.contains('struttura');
                            const labelStyle = TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF455A64),
                              letterSpacing: 0.2,
                            );
                            const valueStyle = TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            );
                            const hintStyle = TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF9E9E9E),
                              fontStyle: FontStyle.italic,
                            );

                            Widget withLabel(Widget child) {
                              return SizedBox(
                                width: (twoCols && !isWideField) ? fieldWidth : constraints.maxWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: labelStyle,
                                      ),
                                      const SizedBox(height: 3),
                                      child,
                                    ],
                                  ),
                                ),
                              );
                            }

                            if (isFirstReleaseField(f)) {
                              final options = <String>{..._firstReleaseOptions, ctrl.text.trim()}
                                ..removeWhere((e) => e.trim().isEmpty);
                              final value =
                                  options.contains(ctrl.text.trim()) ? ctrl.text.trim() : null;
                              return withLabel(
                                DropdownButtonFormField<String>(
                                  initialValue: value,
                                  decoration: const InputDecoration(
                                    hintText: 'Seleziona valore',
                                    isDense: true,
                                    contentPadding:
                                        EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  ),
                                  items: options
                                      .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                                      .toList(growable: false),
                                  style: valueStyle,
                                  onChanged: (v) {
                                    setLocal(() {
                                      ctrl.text = v ?? '';
                                    });
                                  },
                                ),
                              );
                            }
                            if (isModalitaField(f)) {
                              final options = _modalitaOptions;
                              final trimmed = ctrl.text.trim();
                              final value = _modalitaOptions.contains(trimmed)
                                  ? trimmed
                                  : null;
                              return withLabel(
                                DropdownButtonFormField<String>(
                                  initialValue: value,
                                  decoration: const InputDecoration(
                                    hintText: 'Seleziona modalita',
                                    isDense: true,
                                    contentPadding:
                                        EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  ),
                                  items: options
                                      .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                                      .toList(growable: false),
                                  style: valueStyle,
                                  onChanged: (v) {
                                    setLocal(() {
                                      ctrl.text = v ?? '';
                                    });
                                  },
                                ),
                              );
                            }
                            if (f == 'struttura_link') {
                              final modalita =
                                  fieldCtrls['modalita']?.text.trim().toLowerCase() ?? '';
                              final isOnline = modalita == 'online';
                              final idCtrl = fieldCtrls['struttura_rfi_id']!;
                              final nomeCtrl = fieldCtrls['struttura_nome']!;
                              final indirizzoCtrl = fieldCtrls['struttura_indirizzo']!;
                              final selectedId = idCtrl.text.trim().isEmpty
                                  ? null
                                  : idCtrl.text.trim();
                              return withLabel(
                                RfiStrutturaSelector(
                                  strutture: _rfiStrutture,
                                  selectedId: selectedId,
                                  onlineMode: isOnline,
                                  onlineLinkController: ctrl,
                                  onChanged: (s) {
                                    setLocal(() {
                                      final m =
                                          FormazioneRfiStruttureService.fieldsFromStruttura(s);
                                      idCtrl.text = m['struttura_rfi_id'] ?? '';
                                      nomeCtrl.text = m['struttura_nome'] ?? '';
                                      indirizzoCtrl.text = m['struttura_indirizzo'] ?? '';
                                      ctrl.text = m['struttura_link'] ?? '';
                                    });
                                  },
                                ),
                              );
                            }
                            return withLabel(
                              TextField(
                                controller: ctrl,
                                style: valueStyle,
                                keyboardType:
                                    dateLike ? TextInputType.number : TextInputType.text,
                                inputFormatters:
                                    dateLike ? <TextInputFormatter>[_DateSlashInputFormatter()] : null,
                                decoration: InputDecoration(
                                  hintText: dateLike ? 'Inserisci data (GG/MM/AAAA)' : 'Inserisci valore',
                                  hintStyle: hintStyle,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                ),
                                maxLines: normalized.contains('note') ? 3 : 1,
                              ),
                            );
                          }

                          return Wrap(
                            spacing: 8,
                            runSpacing: 0,
                            children: currentFields
                                .where((f) => !_strutturaMetaFieldKeys.contains(f))
                                .map(buildField)
                                .toList(growable: false),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text('Cancella'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    if (action == null || action == 'cancel') {
      disposeEditors();
      return;
    }
    final targetTrack = selectedTrack.trim();
    if (targetTrack.isEmpty) {
      disposeEditors();
      _snack('Il corso non puo essere vuoto', error: true);
      return;
    }

    try {
      if (action == 'delete') {
        final confirmDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Conferma cancellazione'),
              content: const Text(
                'Vuoi davvero cancellare questo record formazione RFI?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Si, cancella'),
                ),
              ],
            );
          },
        );
        if (confirmDelete != true) return;
        await SupabaseService.client
            .from('formazione_rfi_records')
            .delete()
            .eq('personale_id', selectedPersonId)
            .eq('track_key', targetTrack);
        await _notifyEmployeeRfiChange(
          personaleId: selectedPersonId,
          action: 'delete',
          track: targetTrack,
        );
        await _load();
        _snack('Record cancellato');
        return;
      }

      final fields = <String, String>{
        for (final f in currentFields) f: fieldCtrls[f]!.text,
      };
      for (final f in FormazioneRfiStruttureService.recordFieldKeys) {
        fields[f] = fieldCtrls[f]?.text ?? '';
      }

      if (selectedPersonId != personaleId || targetTrack != track) {
        await SupabaseService.client
            .from('formazione_rfi_records')
            .delete()
            .eq('personale_id', personaleId)
            .eq('track_key', track);
      }

      for (final entry in fields.entries) {
        await _upsertField(
          personaleId: selectedPersonId,
          track: targetTrack,
          field: entry.key,
          rawValue: entry.value,
        );
      }
      await SupabaseService.client
          .from('formazione_rfi_records')
          .delete()
          .eq('personale_id', selectedPersonId)
          .eq('track_key', targetTrack)
          .eq('field_key', 'data_programmazione_corso');
      await _notifyEmployeeRfiChange(
        personaleId: selectedPersonId,
        action: 'update',
        track: targetTrack,
      );
      await _load();
      _snack('Record aggiornato');
    } catch (_) {
      _snack('Errore salvataggio record', error: true);
    } finally {
      disposeEditors();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final personaleRes = await UsersDirectory.visiblePersonale(
        await SupabaseService.client
            .from('personale')
            .select('id, id_uuid, full_name')
            .order('full_name', ascending: true) as List,
      );
      final struttureRes = await FormazioneRfiStruttureService.loadAll();
      final recordsRes = await SupabaseService.client
          .from('formazione_rfi_records')
          .select(
            'personale_id, track_key, field_key, value_date, value_text, '
            'field_timestamps, updated_at, created_at',
          )
          .order('id', ascending: true);
      var recordsList =
          (recordsRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final cleaned = await _cleanupExpiredProgrammazioneRows(recordsList);
      if (cleaned) {
        final refreshed = await SupabaseService.client
            .from('formazione_rfi_records')
            .select(
              'personale_id, track_key, field_key, value_date, value_text, '
              'field_timestamps, updated_at, created_at',
            )
            .order('id', ascending: true);
        recordsList =
            (refreshed as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      _personaleNameById.clear();
      _personaleUuidById.clear();
      _tracks.clear();
      _fieldsByTrack.clear();
      _cellByCompositeKey.clear();
      _cellRowByCompositeKey.clear();

      for (final row in personaleRes) {
        final id = int.tryParse((row['id'] ?? '').toString());
        final uuid = (row['id_uuid'] ?? '').toString().trim();
        final name = (row['full_name'] ?? '').toString().trim();
        if (id == null || uuid.isEmpty) continue;
        _personaleNameById[id] = name.isEmpty ? uuid : name;
        _personaleUuidById[id] = uuid;
      }

      final trackSeen = <String>{};
      final fieldsSeenByTrack = <String, Set<String>>{};

      for (final row in recordsList) {
        final pid = int.tryParse((row['personale_id'] ?? '').toString());
        final track = (row['track_key'] ?? '').toString().trim();
        final field = (row['field_key'] ?? '').toString().trim();
        if (pid == null || track.isEmpty || field.isEmpty) continue;
        final uuid = _personaleUuidById[pid];
        if (uuid == null || uuid.isEmpty) continue;

        if (!trackSeen.contains(track)) {
          trackSeen.add(track);
          _tracks.add(track);
        }
        fieldsSeenByTrack.putIfAbsent(track, () => <String>{});
        if (!_isProgrammazioneFieldKey(field) &&
            !_isRetiredFieldKey(field) &&
            !fieldsSeenByTrack[track]!.contains(field)) {
          fieldsSeenByTrack[track]!.add(field);
          _fieldsByTrack.putIfAbsent(track, () => <String>[]).add(field);
        }

        final valueDate = row['value_date'];
        final valueText = (row['value_text'] ?? '').toString().trim();
        final display = _formatExcelLikeCellValue(valueDate, valueText);
        if (display.isEmpty) continue;
        final key = _cellKey(uuid, track, field);
        _cellByCompositeKey[key] = display;
        _cellRowByCompositeKey[key] = row;
      }

      final auditIds = <String>{};
      for (final row in _cellRowByCompositeKey.values) {
        mergeFieldTimestampActorUuids(row, auditIds);
      }
      _auditUserNamesByUuid
        ..clear()
        ..addAll(await loadUserNamesByUuid(auditIds));

      _tracks.sort((a, b) {
        final pa = _trackPriority(a);
        final pb = _trackPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
      for (final track in _tracks) {
        final fields = _fieldsByTrack[track];
        if (fields == null) continue;
        fields.sort((a, b) {
          final pa = _fieldPriority(a);
          final pb = _fieldPriority(b);
          if (pa != pb) return pa.compareTo(pb);
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
      }

      _rfiStrutture = struttureRes;

      _people = _personaleUuidById.entries.map((e) {
        final id = e.key;
        final uuid = e.value;
        return <String, dynamic>{
          'id': id,
          'uuid': uuid,
          'name': _personaleNameById[id] ?? uuid,
        };
      }).toList()
        ..sort(
          (a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore caricamento Formazione RFI')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildMobilePeopleList(List<Map<String, dynamic>> visiblePeople) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      itemCount: visiblePeople.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = visiblePeople[i];
        final name = (p['name'] ?? '').toString();
        final uuid = (p['uuid'] ?? '').toString();
        final pid = (p['id'] as int?) ?? 0;
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.22)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            subtitle: const Text('Riepilogo corsi e modifica'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPersonSummary(
              personaleId: pid,
              personaleUuid: uuid,
              name: name,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobileList = useMobileUi(context);
    final isCompact = useCompactPageLayout(context) || isMobileList;
    final q = _searchCtrl.text.trim().toLowerCase();
    final visibleTracks = _visibleTracks;
    final visiblePeople = _people.where((p) {
      final nameOk = q.isEmpty || (p['name'] as String).toLowerCase().contains(q);
      if (!nameOk) return false;
      final uuid = (p['uuid'] ?? '').toString();
      return _personMatchesExpiryFilter(uuid);
    }).toList();

    final leftNumberWidth = isCompact ? 44.0 : 50.0;
    final leftNameWidth = isCompact ? 170.0 : 210.0;
    final cellWidth = isCompact ? 132.0 : 150.0;
    const topHeaderHeight = 46.0;
    const subHeaderHeight = 42.0;
    const rowHeight = 42.0;
    final gridColor = Colors.blueGrey.withValues(alpha: 0.22);
    final dividerColor = Colors.blueGrey.withValues(alpha: 0.42);

    final totalCells =
        visibleTracks.fold<int>(0, (acc, t) => acc + _visibleFieldsForTrack(t).length);

    Widget rightHeaderTop() {
      return Row(
        children: visibleTracks.map((track) {
          final fields = _visibleFieldsForTrack(track);
          final width = fields.length * cellWidth;
          return Container(
            width: width <= 0 ? cellWidth : width,
            height: topHeaderHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: dividerColor, width: 1.2),
                bottom: BorderSide(color: gridColor, width: 0.8),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              track,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.15),
            ),
          );
        }).toList(growable: false),
      );
    }

    Widget rightHeaderBottom() {
      return Row(
        children: _tracks.expand((track) {
          final fields = _visibleFieldsForTrack(track);
          return fields.map((field) {
            return Container(
              width: cellWidth,
              height: subHeaderHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: gridColor, width: 0.8),
                  bottom: BorderSide(color: dividerColor, width: 1.0),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _labelFromField(field),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
              ),
            );
          });
        }).toList(growable: false),
      );
    }

    Widget leftHeader() {
      return Column(
        children: [
          Row(
            children: [
              Container(
                width: leftNumberWidth,
                height: topHeaderHeight + subHeaderHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: gridColor, width: 0.8),
                    bottom: BorderSide(color: dividerColor, width: 1.0),
                  ),
                ),
                child: const Text('#', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                width: leftNameWidth,
                height: topHeaderHeight + subHeaderHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: dividerColor, width: 1.2),
                    bottom: BorderSide(color: dividerColor, width: 1.0),
                  ),
                ),
                child: const Text('Nominativi', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Admin - Formazione RFI'),
        actions: [
          if (!widget.readOnly)
            IconButton(
              tooltip: 'Strutture RFI (DOIT)',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => useMobileUi(context)
                      ? const AdminFormazioneRfiStruttureMobilePage()
                      : const AdminFormazioneRfiStrutturePage(),
                ),
              ),
              icon: const Icon(Icons.location_city_outlined),
            ),
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
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
        ],
      )),
      body: PageWithTopLogo(
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 8 : 12),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Cerca dipendente',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: isCompact ? Alignment.centerLeft : Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _expiryFilter = _expiryFilter == _filter60 ? null : _filter60;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _expiryFilter == _filter60 ? Colors.yellow.shade100 : null,
                        visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                      ),
                      child: Text(isCompact ? '60g' : 'Scadenza 60 giorni'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _expiryFilter = _expiryFilter == _filter45 ? null : _filter45;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _expiryFilter == _filter45 ? Colors.red.shade100 : null,
                        visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                      ),
                      child: Text(isCompact ? '45g' : 'Scadenza 45 giorni'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _expiryFilter = _expiryFilter == _filterExpired ? null : _filterExpired;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _expiryFilter == _filterExpired ? Colors.red.shade200 : null,
                        visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                      ),
                      child: const Text('Scaduti'),
                    ),
                    if (!widget.readOnly)
                      OutlinedButton.icon(
                        onPressed: _addColumn,
                        icon: const Icon(Icons.view_column),
                        label: const Text('Nuova colonna'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : isMobileList
                        ? _buildMobilePeopleList(visiblePeople)
                        : Row(
                        children: [
                          SizedBox(
                            width: leftNumberWidth + leftNameWidth,
                            child: Column(
                              children: [
                                leftHeader(),
                                Expanded(
                                  child: ListView.builder(
                                    controller: _leftV,
                                    itemCount: visiblePeople.length,
                                    itemExtent: rowHeight,
                                    itemBuilder: (context, i) {
                                      final rowBg = i.isEven
                                          ? Colors.transparent
                                          : Colors.blueGrey.withValues(alpha: 0.03);
                                      final name = (visiblePeople[i]['name'] ?? '').toString();
                                      return Row(
                                        children: [
                                          Container(
                                            width: leftNumberWidth,
                                            height: rowHeight,
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: rowBg,
                                              border: Border(
                                                right: BorderSide(color: gridColor, width: 0.8),
                                                bottom: BorderSide(color: gridColor, width: 0.8),
                                              ),
                                            ),
                                            child: Text('${i + 1}'),
                                          ),
                                          Container(
                                            width: leftNameWidth,
                                            height: rowHeight,
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: rowBg,
                                              border: Border(
                                                right: BorderSide(color: dividerColor, width: 1.2),
                                                bottom: BorderSide(color: gridColor, width: 0.8),
                                              ),
                                            ),
                                            child: InkWell(
                                              onTap: () => _openPersonSummary(
                                                personaleId:
                                                    (visiblePeople[i]['id'] as int?) ?? 0,
                                                personaleUuid:
                                                    (visiblePeople[i]['uuid'] ?? '').toString(),
                                                name: name,
                                              ),
                                              child: Text(
                                                name,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
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
                          Expanded(
                            child: Column(
                              children: [
                                Scrollbar(
                                  controller: _headerH,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _headerH,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: totalCells * cellWidth,
                                      child: Column(
                                        children: [rightHeaderTop(), rightHeaderBottom()],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _bodyH,
                                    thumbVisibility: true,
                                    notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                                    child: SingleChildScrollView(
                                      controller: _bodyH,
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: totalCells * cellWidth,
                                        child: ListView.builder(
                                          controller: _rightV,
                                          itemCount: visiblePeople.length,
                                          itemExtent: rowHeight,
                                          itemBuilder: (context, i) {
                                            final rowBg = i.isEven
                                                ? Colors.transparent
                                                : Colors.blueGrey.withValues(alpha: 0.03);
                                            final uuid = (visiblePeople[i]['uuid'] ?? '').toString();
                                            final pid = (visiblePeople[i]['id'] as int?) ?? 0;
                                            return Row(
                                              children: _tracks.expand((track) {
                                                final fields =
                                                    _visibleFieldsForTrack(track);
                                                return fields.map((field) {
                                                  final value = _cellByCompositeKey[
                                                          _cellKey(uuid, track, field)] ??
                                                      '';
                                                  final dateBg = _dateBgForScadenza(field, value, rowBg);
                                                  final cellKey =
                                                      _cellKey(uuid, track, field);
                                                  final recordRow =
                                                      _cellRowByCompositeKey[cellKey];
                                                  final cellBody = Container(
                                                    width: cellWidth,
                                                    height: rowHeight,
                                                    alignment: Alignment.center,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: dateBg ?? rowBg,
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
                                                    child: Text(
                                                      value,
                                                      textAlign: TextAlign.center,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11),
                                                    ),
                                                  );
                                                  return InkWell(
                                                    onTap: widget.readOnly
                                                        ? null
                                                        : () => _openFullEditor(
                                                              personaleId: pid,
                                                              personaleUuid: uuid,
                                                              track: track,
                                                              field: field,
                                                            ),
                                                    child: recordRow == null
                                                        ? cellBody
                                                        : wrapWithAuditHover(
                                                            cellBody,
                                                            row: recordRow,
                                                            fieldKey: rfiRecordAuditFieldKey(
                                                              recordRow,
                                                            ),
                                                            userNamesByUuid:
                                                                _auditUserNamesByUuid,
                                                            rowAuditWhenFieldMissing:
                                                                false,
                                                          ),
                                                  );
                                                });
                                              }).toList(growable: false),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
