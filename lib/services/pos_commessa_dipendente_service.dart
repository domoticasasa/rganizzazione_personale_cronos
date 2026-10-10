import '../utils/personale_name_matcher.dart';
import 'pos_maestranze_import_parser.dart';
import 'supabase_service.dart';

class PosCommessaDipendenteRow {
  final String id;
  final String commessaId;
  final String personaleId;
  final String? cognomeImport;
  final String? nomeImport;
  final String? mansione;
  final DateTime? idoneitaSanitaria;
  final String? note;
  final String personaleFullName;
  final List<String> formazioni81;
  final List<String> formazioniRfi;

  const PosCommessaDipendenteRow({
    required this.id,
    required this.commessaId,
    required this.personaleId,
    required this.personaleFullName,
    this.cognomeImport,
    this.nomeImport,
    this.mansione,
    this.idoneitaSanitaria,
    this.note,
    this.formazioni81 = const [],
    this.formazioniRfi = const [],
  });
}

/// Riepilogo POS per commessa (lista pre-selezione).
class PosCommessaRiepilogo {
  final String commessaId;
  final String nome;
  final int dipendentiCount;
  final int dipendentiConFormazione;
  final DateTime? dataUltimoAggiornamento;
  final DateTime? metaUpdatedAt;
  final DateTime? ultimoAggiornamentoInApp;

  const PosCommessaRiepilogo({
    required this.commessaId,
    required this.nome,
    required this.dipendentiCount,
    required this.dipendentiConFormazione,
    this.dataUltimoAggiornamento,
    this.metaUpdatedAt,
    this.ultimoAggiornamentoInApp,
  });

  bool get haDatiInseriti => dipendentiCount > 0;

  int get percentualeDatiInseriti => dipendentiCount == 0
      ? 0
      : ((dipendentiConFormazione * 100) / dipendentiCount).round();

  /// Ultimo salvataggio in app (meta o righe dipendenti POS).
  DateTime? get ultimoAggiornamentoApp => ultimoAggiornamentoInApp;
}

class PosImportMatchPreview {
  final PosMaestranzeImportRow importRow;
  final String? personaleId;
  final String? personaleFullName;

  bool get matched => personaleId != null && personaleId!.isNotEmpty;

  const PosImportMatchPreview({
    required this.importRow,
    this.personaleId,
    this.personaleFullName,
  });

  PosImportMatchPreview copyWith({
    String? personaleId,
    String? personaleFullName,
    bool clearMatch = false,
  }) {
    return PosImportMatchPreview(
      importRow: importRow,
      personaleId: clearMatch ? null : (personaleId ?? this.personaleId),
      personaleFullName:
          clearMatch ? null : (personaleFullName ?? this.personaleFullName),
    );
  }
}

abstract final class PosCommessaDipendenteService {
  PosCommessaDipendenteService._();
  static const String listaDefault = '';

  static DateTime? _parseDateField(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static DateTime? _maxDateTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String normalizeListaMldKey(String? raw) {
    final v = (raw ?? '').trim().toUpperCase();
    if (v == 'LFC') return 'FLM';
    return v;
  }

  /// Statistiche POS per tutte le commesse attive (prima della selezione).
  static Future<List<PosCommessaRiepilogo>> loadCommesseRiepilogo(
    Map<String, String> commesseAttive,
  ) async {
    if (commesseAttive.isEmpty) return const [];

    final dipRes = await SupabaseService.client
        .from('pos_commessa_dipendenti')
        .select('commessa_id, personale_id, updated_at');

    final personaleByCommessa = <String, Set<String>>{};
    final lastDipUpdateByCommessa = <String, DateTime>{};
    for (final raw in dipRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = (m['commessa_id'] ?? '').toString().trim();
      final pid = (m['personale_id'] ?? '').toString().trim();
      if (cid.isEmpty || pid.isEmpty) continue;
      personaleByCommessa.putIfAbsent(cid, () => <String>{}).add(pid);
      final dipUpd = _parseDateField(m['updated_at']);
      if (dipUpd != null) {
        lastDipUpdateByCommessa[cid] =
            _maxDateTime(lastDipUpdateByCommessa[cid], dipUpd)!;
      }
    }

    final metaByCommessa = <String, DateTime?>{};
    final metaRes = await SupabaseService.client
        .from('pos_commessa_lista_meta')
        .select('commessa_id, updated_at');
    for (final raw in metaRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = (m['commessa_id'] ?? '').toString().trim();
      if (cid.isEmpty) continue;
      metaByCommessa[cid] = _maxDateTime(
        metaByCommessa[cid],
        _parseDateField(m['updated_at']),
      );
    }

    final out = <PosCommessaRiepilogo>[];
    for (final entry in commesseAttive.entries) {
      final cid = entry.key;
      final pids = personaleByCommessa[cid] ?? const <String>{};
      final metaUpd = metaByCommessa[cid];
      out.add(
        PosCommessaRiepilogo(
          commessaId: cid,
          nome: entry.value,
          dipendentiCount: pids.length,
          dipendentiConFormazione: 0,
          dataUltimoAggiornamento: null,
          metaUpdatedAt: metaUpd,
          ultimoAggiornamentoInApp:
              _maxDateTime(metaUpd, lastDipUpdateByCommessa[cid]),
        ),
      );
    }

    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  static Future<Map<String, String>> loadCommesseAttive() async {
    final res = await SupabaseService.client
        .from('commesse')
        .select('id_uuid,nome')
        .eq('active', true)
        .order('nome');
    return {
      for (final raw in res as List)
        (raw['id_uuid'] ?? '').toString(): (raw['nome'] ?? '').toString(),
    }..removeWhere((k, v) => k.isEmpty);
  }

  static Future<Map<String, String>> loadPersonaleAttivo() async {
    final res = await SupabaseService.client
        .from('personale')
        .select('id_uuid,full_name')
        .eq('active', true)
        .order('full_name');
    return {
      for (final raw in res as List)
        (raw['id_uuid'] ?? '').toString(): (raw['full_name'] ?? '').toString(),
    }..removeWhere((k, v) => k.isEmpty || v.isEmpty);
  }

  /// Ultimo aggiornamento salvato in app (import, aggiunta/rimozione dipendenti).
  static Future<DateTime?> loadUltimoAggiornamentoApp(
    String commessaId, {
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    DateTime? latest;
    final meta = await SupabaseService.client
        .from('pos_commessa_lista_meta')
        .select('updated_at')
        .eq('commessa_id', commessaId)
        .eq('lista_mld', lista)
        .maybeSingle();
    if (meta != null) {
      latest = _maxDateTime(latest, _parseDateField(meta['updated_at']));
    }
    final dips = await SupabaseService.client
        .from('pos_commessa_dipendenti')
        .select('updated_at')
        .eq('commessa_id', commessaId)
        .eq('lista_mld', lista);
    for (final raw in dips as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      latest = _maxDateTime(latest, _parseDateField(m['updated_at']));
    }
    return latest;
  }

  static Future<DateTime?> loadDataUltimoAggiornamento(
    String commessaId, {
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    final row = await SupabaseService.client
        .from('pos_commessa_lista_meta')
        .select('data_ultimo_aggiornamento')
        .eq('commessa_id', commessaId)
        .eq('lista_mld', lista)
        .maybeSingle();
    if (row == null) return null;
    final raw = row['data_ultimo_aggiornamento']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<Map<String, List<String>>> loadFormazioni81ByPersonale(
    Set<String> personaleIds,
  ) async {
    return _loadCorsiByPersonale(
      table: 'formazione_corsi',
      personaleIds: personaleIds,
    );
  }

  /// Profili RFI come in «Formazione RFI» (formazione_rfi_records), non solo formazione_rfi_corsi.
  static Future<Map<String, List<String>>> loadFormazioniRfiByPersonale(
    Set<String> personaleUuids,
  ) async {
    if (personaleUuids.isEmpty) return {};

    final uuids = personaleUuids.where((id) => id.isNotEmpty).toList();
    if (uuids.isEmpty) return {};

    final pres = await SupabaseService.client
        .from('personale')
        .select('id, id_uuid')
        .inFilter('id_uuid', uuids);

    final intByUuid = <String, int>{};
    final ints = <int>[];
    for (final raw in pres as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = int.tryParse((m['id'] ?? '').toString());
      final uuid = (m['id_uuid'] ?? '').toString().trim();
      if (id == null || uuid.isEmpty) continue;
      intByUuid[uuid] = id;
      ints.add(id);
    }

    final tracksByPersonaleInt = <int, Set<String>>{};
    if (ints.isNotEmpty) {
      for (var i = 0; i < ints.length; i += 80) {
        final end = i + 80 > ints.length ? ints.length : i + 80;
        final chunk = ints.sublist(i, end);
        final res = await SupabaseService.client
            .from('formazione_rfi_records')
            .select('personale_id, track_key, field_key, value_date, value_text')
            .inFilter('personale_id', chunk);

        for (final raw in res as List) {
          final m = Map<String, dynamic>.from(raw as Map);
          final pid = int.tryParse((m['personale_id'] ?? '').toString());
          final track = (m['track_key'] ?? '').toString().trim();
          if (pid == null || track.isEmpty) continue;
          if (!_rfiRecordCellHasValue(m)) continue;
          tracksByPersonaleInt.putIfAbsent(pid, () => <String>{}).add(track);
        }
      }
    }

    final corsiExtra = await _loadCorsiByPersonale(
      table: 'formazione_rfi_corsi',
      personaleIds: personaleUuids,
    );

    final out = <String, List<String>>{};
    for (final uuid in uuids) {
      final pid = intByUuid[uuid];
      final labels = <String>{};
      if (pid != null) {
        labels.addAll(tracksByPersonaleInt[pid] ?? const {});
      }
      labels.addAll(corsiExtra[uuid] ?? const []);
      if (labels.isEmpty) continue;
      out[uuid] = (labels.toList()..sort(_compareRfiTrackLabels));
    }
    return out;
  }

  static bool _rfiRecordCellHasValue(Map<String, dynamic> row) {
    final dateRaw = (row['value_date'] ?? '').toString().trim();
    if (dateRaw.isNotEmpty) return true;
    return (row['value_text'] ?? '').toString().trim().isNotEmpty;
  }

  static const List<String> _rfiTrackOrderHints = <String>[
    'profili rfi mi mepc',
    'profili rfi agenti ia pl',
    'profili rfi mdo ditte',
    'profili rfi mod ditte',
    'profili rfi qp mett',
    'profili rfi te ditte',
    'profili rfi is0',
    'conversione abilitazione fse',
    'conversione abilitazione eav',
  ];

  static int _rfiTrackPriority(String track) {
    final n = track.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    for (var i = 0; i < _rfiTrackOrderHints.length; i++) {
      if (n.contains(_rfiTrackOrderHints[i])) return i;
    }
    return 999;
  }

  static int _compareRfiTrackLabels(String a, String b) {
    final pa = _rfiTrackPriority(a);
    final pb = _rfiTrackPriority(b);
    if (pa != pb) return pa.compareTo(pb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static Future<Map<String, List<String>>> _loadCorsiByPersonale({
    required String table,
    required Set<String> personaleIds,
  }) async {
    if (personaleIds.isEmpty) return {};
    final ids = personaleIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return {};

    final res = await SupabaseService.client
        .from(table)
        .select('personale_id, corso')
        .inFilter('personale_id', ids);

    final grouped = <String, Set<String>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final pid = (m['personale_id'] ?? '').toString().trim();
      final corso = (m['corso'] ?? '').toString().trim();
      if (pid.isEmpty || corso.isEmpty) continue;
      grouped.putIfAbsent(pid, () => <String>{}).add(corso);
    }

    return {
      for (final e in grouped.entries)
        e.key: (e.value.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))),
    };
  }

  static Future<List<PosCommessaDipendenteRow>> loadDipendentiPos(
    String commessaId, {
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    final nomi = await loadPersonaleAttivo();
    final res = await SupabaseService.client
        .from('pos_commessa_dipendenti')
        .select('id, commessa_id, personale_id, cognome_import, nome_import, note')
        .eq('commessa_id', commessaId)
        .eq('lista_mld', lista);

    final out = <PosCommessaDipendenteRow>[];
    final personaleIds = <String>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final pid = (m['personale_id'] ?? '').toString();
      if (pid.isNotEmpty) personaleIds.add(pid);
      out.add(
        PosCommessaDipendenteRow(
          id: (m['id'] ?? '').toString(),
          commessaId: (m['commessa_id'] ?? '').toString(),
          personaleId: pid,
          personaleFullName: nomi[pid] ?? '',
          cognomeImport: m['cognome_import']?.toString(),
          nomeImport: m['nome_import']?.toString(),
          note: m['note']?.toString(),
        ),
      );
    }

    final f81 = await loadFormazioni81ByPersonale(personaleIds);
    final fRfi = await loadFormazioniRfiByPersonale(personaleIds);

    final enriched = out
        .map(
          (r) => PosCommessaDipendenteRow(
            id: r.id,
            commessaId: r.commessaId,
            personaleId: r.personaleId,
            personaleFullName: r.personaleFullName,
            cognomeImport: r.cognomeImport,
            nomeImport: r.nomeImport,
            note: r.note,
            formazioni81: f81[r.personaleId] ?? const [],
            formazioniRfi: fRfi[r.personaleId] ?? const [],
          ),
        )
        .toList();
    enriched.sort(
      (a, b) =>
          a.personaleFullName.toLowerCase().compareTo(b.personaleFullName.toLowerCase()),
    );
    return enriched;
  }

  static Future<void> upsertListaMeta({
    required String commessaId,
    DateTime? dataUltimoAggiornamento,
    String? updatedByUserUuid,
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    await SupabaseService.client.from('pos_commessa_lista_meta').upsert({
      'commessa_id': commessaId,
      'lista_mld': lista,
      'data_ultimo_aggiornamento': dataUltimoAggiornamento?.toIso8601String().substring(0, 10),
      'updated_by_user_uuid': updatedByUserUuid,
    }, onConflict: 'commessa_id,lista_mld');
  }

  static Future<void> addDipendente({
    required String commessaId,
    required String personaleId,
    String? cognomeImport,
    String? nomeImport,
    String? mansione,
    DateTime? idoneitaSanitaria,
    String? note,
    String? createdByUserUuid,
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    await SupabaseService.client.from('pos_commessa_dipendenti').upsert({
      'commessa_id': commessaId,
      'lista_mld': lista,
      'personale_id': personaleId,
      'cognome_import': cognomeImport,
      'nome_import': nomeImport,
      'mansione': mansione,
      'idoneita_sanitaria': idoneitaSanitaria?.toIso8601String().substring(0, 10),
      'note': note,
      'created_by_user_uuid': createdByUserUuid,
    }, onConflict: 'commessa_id,lista_mld,personale_id');
  }

  static Future<void> updateDipendente({
    required String id,
    String? mansione,
    DateTime? idoneitaSanitaria,
    String? note,
  }) async {
    await SupabaseService.client.from('pos_commessa_dipendenti').update({
      'mansione': ?mansione,
      if (idoneitaSanitaria != null)
        'idoneita_sanitaria': idoneitaSanitaria.toIso8601String().substring(0, 10),
      'note': ?note,
    }).eq('id', id);
  }

  static Future<void> removeDipendente(String id) async {
    await SupabaseService.client.from('pos_commessa_dipendenti').delete().eq('id', id);
  }

  static List<PosImportMatchPreview> previewImportMatches({
    required List<PosMaestranzeImportRow> righe,
    required Map<String, String> personaleById,
  }) {
    return righe
        .map((r) {
          final pid = PersonaleNameMatcher.findBestPersonaleId(
            cognomeImport: r.cognome,
            nomeImport: r.nome,
            personaleById: personaleById,
          );
          return PosImportMatchPreview(
            importRow: r,
            personaleId: pid,
            personaleFullName: pid != null ? personaleById[pid] : null,
          );
        })
        .toList(growable: false);
  }

  static Future<({int added, int updated, int skipped})> applyImport({
    required String commessaId,
    required List<PosImportMatchPreview> previews,
    DateTime? dataUltimoAggiornamento,
    String? userUuid,
    bool replaceExisting = false,
    String? listaMldKey,
  }) async {
    final lista = normalizeListaMldKey(listaMldKey);
    if (replaceExisting) {
      await SupabaseService.client
          .from('pos_commessa_dipendenti')
          .delete()
          .eq('commessa_id', commessaId)
          .eq('lista_mld', lista);
    }

    final existingIds = replaceExisting
        ? <String>{}
        : (await loadDipendentiPos(commessaId, listaMldKey: lista))
            .map((r) => r.personaleId)
            .toSet();

    var added = 0;
    var updated = 0;
    var skipped = 0;
    for (final p in previews) {
      final pid = p.personaleId;
      if (pid == null || pid.isEmpty) {
        skipped++;
        continue;
      }
      await addDipendente(
        commessaId: commessaId,
        personaleId: pid,
        cognomeImport: p.importRow.cognome,
        nomeImport: p.importRow.nome,
        createdByUserUuid: userUuid,
        listaMldKey: lista,
      );
      if (existingIds.contains(pid)) {
        updated++;
      } else {
        added++;
        existingIds.add(pid);
      }
    }

    if (dataUltimoAggiornamento != null) {
      await upsertListaMeta(
        commessaId: commessaId,
        dataUltimoAggiornamento: dataUltimoAggiornamento,
        updatedByUserUuid: userUuid,
        listaMldKey: lista,
      );
    }

    return (added: added, updated: updated, skipped: skipped);
  }
}
