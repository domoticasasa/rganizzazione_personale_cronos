import '../utils/date_formatters.dart';
import 'formazione_programmazione_config_service.dart';
import 'formazione_programmazione_service.dart';
import 'formazione_rfi_strutture_service.dart';
import 'supabase_service.dart';

/// Programmazione corsi su [formazione_rfi_records] (EAV per track/dipendente).
abstract final class FormazioneRfiProgrammazioneService {
  static const String fieldDal = 'data_programmazione_dal';
  static const String fieldAl = 'data_programmazione_al';
  static const String legacyFieldCorso = 'data_programmazione_corso';

  static const List<String> programmazioneFieldKeys = <String>[
    fieldDal,
    fieldAl,
    'oda',
    'orario',
    'modalita',
    ...FormazioneRfiStruttureService.recordFieldKeys,
    'note',
  ];

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static DateTime? _dateFromRecord(Map<String, dynamic> r) {
    final vd = r['value_date'];
    if (vd != null && vd.toString().trim().isNotEmpty) {
      final d = DateTime.tryParse(vd.toString());
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    final vt = _s(r['value_text']);
    if (vt.isEmpty) return null;
    final iso = parseFlexibleDateToIsoDate(vt);
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  static String? _textFromRecords(
    List<Map<String, dynamic>> cells,
    String fieldKey,
  ) {
    for (final r in cells) {
      if (_s(r['field_key']) != fieldKey) continue;
      final vd = r['value_date'];
      if (vd != null && vd.toString().trim().isNotEmpty) {
        return formatDateDdMmYyyy(vd);
      }
      final t = _s(r['value_text']);
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static String? _isoFromRecords(List<Map<String, dynamic>> cells, String fieldKey) {
    for (final r in cells) {
      if (_s(r['field_key']) != fieldKey) continue;
      final vd = r['value_date'];
      if (vd != null && vd.toString().trim().isNotEmpty) {
        return vd.toString().split('T').first;
      }
      final iso = parseFlexibleDateToIsoDate(_s(r['value_text']));
      if (iso != null) return iso;
    }
    return null;
  }

  static String? _scadenzaIso(List<Map<String, dynamic>> cells) {
    for (final r in cells) {
      final fk = _s(r['field_key']).toLowerCase().replaceAll('_', ' ');
      if (!fk.contains('prossima scadenza') && fk != 'scadenza') continue;
      final d = _dateFromRecord(r);
      if (d != null) return d.toIso8601String().split('T').first;
    }
    return null;
  }

  static Map<String, dynamic> _rowFromCells({
    required int personaleIdInt,
    required String personaleUuid,
    required String track,
    required List<Map<String, dynamic>> cells,
  }) {
    var dalIso = _isoFromRecords(cells, fieldDal);
    var alIso = _isoFromRecords(cells, fieldAl);
    if (dalIso == null) {
      dalIso = _isoFromRecords(cells, legacyFieldCorso);
      if (dalIso != null && alIso == null) alIso = dalIso;
    }

    return <String, dynamic>{
      'personale_id': personaleUuid,
      'personale_id_int': personaleIdInt,
      'corso': track,
      'prima_data': dalIso,
      'seconda_data': alIso,
      'oda': _textFromRecords(cells, 'oda'),
      'orario': _textFromRecords(cells, 'orario'),
      'modalita': _textFromRecords(cells, 'modalita'),
      'struttura_rfi_id': _textFromRecords(cells, 'struttura_rfi_id'),
      'struttura_nome': _textFromRecords(cells, 'struttura_nome'),
      'struttura_indirizzo': _textFromRecords(cells, 'struttura_indirizzo'),
      'struttura_link': _textFromRecords(cells, 'struttura_link'),
      'note': _textFromRecords(cells, 'note'),
      'scadenza_attestato': _scadenzaIso(cells),
      'ente': '',
      'data_attestato': null,
      'primo_rilascio_aggiornamento': '',
    };
  }

  static bool rowHasProgrammazione(Map<String, dynamic> row) =>
      FormazioneProgrammazioneService.parseDateOnly(row['prima_data']) != null;

  static bool rowVisibleOnProgrammazioneScreen(Map<String, dynamic> row) {
    if (!rowHasProgrammazione(row)) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !FormazioneProgrammazioneConfigService.shouldHideRfiRowAfterCourseEnd(
      row,
      today,
    );
  }

  static Future<({
    Map<int, String> uuidByPersonaleId,
    Map<String, Map<String, dynamic>> personaleByUuid,
  })> loadPersonaleIndex() async {
    final res = await SupabaseService.client
        .from('personale')
        .select('id, id_uuid, full_name, matricola, telefono, email, active');
    final uuidByPersonaleId = <int, String>{};
    final personaleByUuid = <String, Map<String, dynamic>>{};
    for (final e in (res as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final idInt = int.tryParse(_s(m['id']));
      final uuid = _s(m['id_uuid']);
      if (idInt == null || uuid.isEmpty) continue;
      uuidByPersonaleId[idInt] = uuid;
      personaleByUuid[uuid] = m;
    }
    return (uuidByPersonaleId: uuidByPersonaleId, personaleByUuid: personaleByUuid);
  }

  /// Nomi corso (`track_key`) distinti già presenti in archivio RFI.
  static Future<List<String>> loadDistinctTracks() async {
    final res = await SupabaseService.client
        .from('formazione_rfi_records')
        .select('track_key');
    final set = <String>{};
    for (final e in (res as List)) {
      final t = _s((e as Map)['track_key']);
      if (t.isNotEmpty) set.add(t);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  static int? _personaleIdIntForUuid(
    Map<int, String> uuidByPersonaleId,
    String? personaleUuid,
  ) {
    if (personaleUuid == null || personaleUuid.isEmpty) return null;
    for (final e in uuidByPersonaleId.entries) {
      if (e.value == personaleUuid) return e.key;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> loadProgrammazioneRows({
    String? onlyPersonaleUuid,
    bool purgeExpired = false,
  }) async {
    // Percorso veloce: RPC definer (solo track con data programmazione).
    try {
      return await _loadProgrammazioneRowsViaRpc(
        onlyPersonaleUuid: onlyPersonaleUuid,
        purgeExpired: purgeExpired,
      );
    } catch (_) {
      // Fallback client-side (es. RPC non ancora deployata).
    }

    Map<int, String> uuidByPersonaleId;
    if (onlyPersonaleUuid != null && onlyPersonaleUuid.isNotEmpty) {
      final p = await SupabaseService.client
          .from('personale')
          .select('id, id_uuid')
          .eq('id_uuid', onlyPersonaleUuid)
          .maybeSingle();
      final idInt = int.tryParse(_s(p?['id']));
      final uuid = _s(p?['id_uuid']);
      if (idInt == null || uuid.isEmpty) return <Map<String, dynamic>>[];
      uuidByPersonaleId = <int, String>{idInt: uuid};
    } else {
      final index = await loadPersonaleIndex();
      uuidByPersonaleId = index.uuidByPersonaleId;
    }

    final onlyPersonaleIdInt = _personaleIdIntForUuid(
      uuidByPersonaleId,
      onlyPersonaleUuid,
    );
    if (onlyPersonaleUuid != null &&
        onlyPersonaleUuid.isNotEmpty &&
        onlyPersonaleIdInt == null) {
      return <Map<String, dynamic>>[];
    }

    var recordsQuery = SupabaseService.client
        .from('formazione_rfi_records')
        .select('personale_id, track_key, field_key, value_date, value_text');
    if (onlyPersonaleIdInt != null) {
      recordsQuery = recordsQuery.eq('personale_id', onlyPersonaleIdInt);
    }
    final recordsRes = await recordsQuery.order('id', ascending: true);
    final records = (recordsRes as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return _rowsFromRawRecords(
      records: records,
      uuidByPersonaleId: uuidByPersonaleId,
      onlyPersonaleUuid: onlyPersonaleUuid,
      purgeExpired: purgeExpired,
    );
  }

  static Future<List<Map<String, dynamic>>> _loadProgrammazioneRowsViaRpc({
    String? onlyPersonaleUuid,
    bool purgeExpired = false,
  }) async {
    final res = await SupabaseService.client.rpc(
      'formazione_rfi_programmazione_records',
      params: <String, dynamic>{
        'p_only_personale_uuid':
            (onlyPersonaleUuid ?? '').trim().isEmpty ? null : onlyPersonaleUuid,
      },
    );
    final records = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final uuidByPersonaleId = <int, String>{};
    for (final r in records) {
      final pid = int.tryParse(_s(r['personale_id']));
      final uuid = _s(r['personale_uuid']);
      if (pid == null || uuid.isEmpty) continue;
      uuidByPersonaleId[pid] = uuid;
    }
    return _rowsFromRawRecords(
      records: records,
      uuidByPersonaleId: uuidByPersonaleId,
      onlyPersonaleUuid: onlyPersonaleUuid,
      purgeExpired: purgeExpired,
    );
  }

  static Future<List<Map<String, dynamic>>> _rowsFromRawRecords({
    required List<Map<String, dynamic>> records,
    required Map<int, String> uuidByPersonaleId,
    String? onlyPersonaleUuid,
    bool purgeExpired = false,
  }) async {
    if (purgeExpired &&
        FormazioneProgrammazioneConfigService.rfiAutoPurgeAfterCourseEnd) {
      await purgeExpiredFromRecords(records, uuidByPersonaleId);
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final pid = int.tryParse(_s(r['personale_id']));
      final track = _s(r['track_key']);
      if (pid == null || track.isEmpty) continue;
      final uuid = uuidByPersonaleId[pid] ?? _s(r['personale_uuid']);
      if (uuid.isEmpty) continue;
      if (onlyPersonaleUuid != null &&
          onlyPersonaleUuid.isNotEmpty &&
          uuid != onlyPersonaleUuid) {
        continue;
      }
      grouped.putIfAbsent('$pid|$track', () => <Map<String, dynamic>>[]).add(r);
    }

    final rows = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|');
      final pid = int.tryParse(parts.first);
      final track = parts.sublist(1).join('|');
      if (pid == null) continue;
      final uuid =
          uuidByPersonaleId[pid] ?? _s(entry.value.first['personale_uuid']);
      if (uuid.isEmpty) continue;
      final row = _rowFromCells(
        personaleIdInt: pid,
        personaleUuid: uuid,
        track: track,
        cells: entry.value,
      );
      if (!rowHasProgrammazione(row)) continue;
      if (FormazioneProgrammazioneConfigService.shouldHideRfiRowAfterCourseEnd(
        row,
        today,
      )) {
        continue;
      }
      rows.add(row);
    }

    rows.sort((a, b) {
      final da = FormazioneProgrammazioneService.parseDateOnly(a['prima_data']);
      final db = FormazioneProgrammazioneService.parseDateOnly(b['prima_data']);
      if (da == null && db == null) {
        return _s(a['corso']).compareTo(_s(b['corso']));
      }
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return _s(a['corso']).compareTo(_s(b['corso']));
    });

    return rows;
  }

  static Future<int> purgeExpiredFromRecords(
    List<Map<String, dynamic>> records,
    Map<int, String> uuidByPersonaleId,
  ) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final pid = int.tryParse(_s(r['personale_id']));
      final track = _s(r['track_key']);
      if (pid == null || track.isEmpty) continue;
      grouped.putIfAbsent('$pid|$track', () => <Map<String, dynamic>>[]).add(r);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var cleared = 0;

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|');
      final pid = int.tryParse(parts.first);
      final track = parts.sublist(1).join('|');
      if (pid == null) continue;
      final row = _rowFromCells(
        personaleIdInt: pid,
        personaleUuid: uuidByPersonaleId[pid] ?? '',
        track: track,
        cells: entry.value,
      );
      if (!FormazioneProgrammazioneConfigService.shouldHideRfiRowAfterCourseEnd(
        row,
        today,
      )) {
        continue;
      }
      for (final field in programmazioneFieldKeys) {
        await SupabaseService.client
            .from('formazione_rfi_records')
            .delete()
            .eq('personale_id', pid)
            .eq('track_key', track)
            .eq('field_key', field);
      }
      await SupabaseService.client
          .from('formazione_rfi_records')
          .delete()
          .eq('personale_id', pid)
          .eq('track_key', track)
          .eq('field_key', legacyFieldCorso);
      cleared++;
    }
    return cleared;
  }

  static Future<void> _upsertField({
    required int personaleId,
    required String track,
    required String field,
    required String? isoDate,
    required String rawText,
  }) async {
    if ((isoDate == null || isoDate.isEmpty) && rawText.trim().isEmpty) {
      await SupabaseService.client
          .from('formazione_rfi_records')
          .delete()
          .eq('personale_id', personaleId)
          .eq('track_key', track)
          .eq('field_key', field);
      return;
    }
    await SupabaseService.client.from('formazione_rfi_records').upsert(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'personale_id': personaleId,
          'track_key': track,
          'field_key': field,
          'value_date': isoDate,
          'value_text': rawText.trim().isEmpty ? null : rawText.trim(),
          'source_file': 'app_programmazione_rfi',
          'updated_at': supabaseNowIsoUtc(),
        },
      ],
      onConflict: 'personale_id,track_key,field_key',
    );
  }

  static Future<void> saveProgrammazione({
    required int personaleIdInt,
    required String track,
    required String? primaIso,
    required String? secondaIso,
    required String oda,
    required String orario,
    required String modalita,
    String? strutturaRfiId,
    String? strutturaNome,
    String? strutturaIndirizzo,
    required String strutturaLink,
    required String note,
  }) async {
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: fieldDal,
      isoDate: primaIso,
      rawText: '',
    );
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: fieldAl,
      isoDate: secondaIso,
      rawText: '',
    );
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: 'oda',
      isoDate: null,
      rawText: oda,
    );
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: 'orario',
      isoDate: null,
      rawText: orario,
    );
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: 'modalita',
      isoDate: null,
      rawText: modalita,
    );
    final strutturaFields = FormazioneRfiStruttureService.fieldsFromStruttura(
      strutturaRfiId != null && strutturaRfiId.trim().isNotEmpty
          ? <String, dynamic>{
              'id_uuid': strutturaRfiId.trim(),
              'nome': strutturaNome ?? '',
              'indirizzo': strutturaIndirizzo ?? '',
              'maps_link': strutturaLink,
            }
          : (strutturaLink.trim().isNotEmpty ||
                  (strutturaNome ?? '').trim().isNotEmpty)
              ? <String, dynamic>{
                  'id_uuid': '',
                  'nome': strutturaNome ?? '',
                  'indirizzo': strutturaIndirizzo ?? '',
                  'maps_link': strutturaLink,
                }
              : null,
    );
    for (final entry in strutturaFields.entries) {
      await _upsertField(
        personaleId: personaleIdInt,
        track: track,
        field: entry.key,
        isoDate: null,
        rawText: entry.value,
      );
    }
    await _upsertField(
      personaleId: personaleIdInt,
      track: track,
      field: 'note',
      isoDate: null,
      rawText: note,
    );
    await SupabaseService.client
        .from('formazione_rfi_records')
        .delete()
        .eq('personale_id', personaleIdInt)
        .eq('track_key', track)
        .eq('field_key', legacyFieldCorso);
  }

  /// Rimuove solo i campi di programmazione (lascia attestato/scadenze del corso).
  static Future<void> clearProgrammazione({
    required int personaleIdInt,
    required String track,
  }) async {
    final t = track.trim();
    if (t.isEmpty) return;
    for (final field in programmazioneFieldKeys) {
      await SupabaseService.client
          .from('formazione_rfi_records')
          .delete()
          .eq('personale_id', personaleIdInt)
          .eq('track_key', t)
          .eq('field_key', field);
    }
    await SupabaseService.client
        .from('formazione_rfi_records')
        .delete()
        .eq('personale_id', personaleIdInt)
        .eq('track_key', t)
        .eq('field_key', legacyFieldCorso);
  }
}
