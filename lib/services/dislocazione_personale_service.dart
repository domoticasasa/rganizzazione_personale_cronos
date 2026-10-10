import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dislocazione_period_utils.dart';
import '../utils/personale_name_matcher.dart';
import '../utils/users_directory.dart';
import 'dislocazione_programma_impegno_import.dart';

/// Caricamento/salvataggio dislocazione con merge periodi.
class DislocazionePersonaleService {
  DislocazionePersonaleService({SupabaseClient? client})
      : _supa = client ?? Supabase.instance.client;

  final SupabaseClient _supa;

  static const int _pageSize = 1000;

  static String _nomKey(String nominativo) => nominativo.trim().toUpperCase();

  Future<Map<String, String>> loadCommesseAttive() async {
    final res = await _supa
        .from('commesse')
        .select('id_uuid,nome,active')
        .eq('active', true)
        .order('nome');
    return Map<String, String>.fromEntries(
      (res as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return MapEntry(
          (m['id_uuid'] ?? '').toString(),
          (m['nome'] ?? '').toString(),
        );
      }),
    );
  }

  /// Tutti i nominativi distinti (dislocazione + anagrafica personale attiva).
  /// Paginato: Supabase restituisce al massimo 1000 righe per richiesta.
  Future<Set<String>> loadNominativiEsclusiChiavi() async {
    try {
      final res = await _supa
          .from('dislocazione_nominativi_esclusi')
          .select('nominativo_chiave');
      return (res as List)
          .map((e) => (e['nominativo_chiave'] ?? '').toString().trim())
          .where((k) => k.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Rimuove dalla lista dislocazione: cancella assegnazioni ed esclude da anagrafica.
  Future<void> rimuoviNominativoDallaLista(String nominativo) async {
    final nome = nominativo.trim();
    if (nome.isEmpty) return;
    await _eliminaTutteVariantiNominativo(nome);
    await _supa.from('dislocazione_nominativi_esclusi').upsert(
      <String, dynamic>{
        'nominativo_chiave': _nomKey(nome),
        'nominativo_originale': nome,
        'escluso_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'nominativo_chiave',
    );
  }

  Future<void> rimuoviEsclusioneNominativo(String nominativo) async {
    final key = _nomKey(nominativo);
    if (key.isEmpty) return;
    try {
      await _supa
          .from('dislocazione_nominativi_esclusi')
          .delete()
          .eq('nominativo_chiave', key);
    } catch (_) {}
  }

  /// Nominativi come in Gestione Dipendenti (`personale` visibile).
  /// Le assegnazioni restano in `dislocazione_personale` (match per nome normalizzato).
  Future<List<PersonaRiga>> loadPersone() async {
    final byKey = <String, PersonaRiga>{};
    final esclusi = await loadNominativiEsclusiChiavi();
    final abilitaPerChiave = <String, String>{};
    final attivitaPerChiave = <String, String>{};

    var from = 0;
    while (true) {
      final res = await _supa
          .from('dislocazione_personale')
          .select('nominativo, abilitazioni, attivita')
          .order('nominativo')
          .range(from, from + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (list.isEmpty) break;
      for (final m in list) {
        final nome = (m['nominativo'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final key = _nomKey(nome);
        final ab = (m['abilitazioni'] ?? '').toString().trim();
        if (ab.isNotEmpty) abilitaPerChiave.putIfAbsent(key, () => ab);
        final at = (m['attivita'] ?? '').toString().trim();
        if (at.isNotEmpty) attivitaPerChiave.putIfAbsent(key, () => at);
      }
      if (list.length < _pageSize) break;
      from += _pageSize;
    }

    final hiddenKeys = await UsersDirectory.loadHiddenLinkKeys();
    from = 0;
    while (true) {
      final res = await _supa
          .from('personale')
          .select('id, id_uuid, full_name, email, user_id')
          .order('full_name')
          .range(from, from + _pageSize - 1);
      final list = res as List;
      if (list.isEmpty) break;
      final visible = UsersDirectory.onlyVisiblePersonale(
        list.map((e) => Map<String, dynamic>.from(e as Map)),
        hiddenKeys,
      );
      for (final raw in visible) {
        final nome = (raw['full_name'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final key = _nomKey(nome);
        if (esclusi.contains(key)) continue;
        final ab = abilitaPerChiave[key];
        final at = attivitaPerChiave[key];
        byKey.putIfAbsent(
          key,
          () => PersonaRiga(
            nominativo: nome,
            abilitazioni: (ab == null || ab.isEmpty) ? null : ab,
            attivita: (at == null || at.isEmpty) ? null : at,
          ),
        );
      }
      if (list.length < _pageSize) break;
      from += _pageSize;
    }

    final out = byKey.values.toList()
      ..sort((a, b) => a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase()));
    return out;
  }

  /// Estremi date presenti in dislocazione (2 righe, non scansione completa).
  Future<({DateTime? min, DateTime? max})> loadPeriodBounds() async {
    DateTime? minD;
    DateTime? maxD;
    try {
      final minRes = await _supa
          .from('dislocazione_personale')
          .select('data_inizio')
          .order('data_inizio', ascending: true)
          .limit(1);
      if (minRes.isNotEmpty) {
        minD = parseIsoDate(minRes.first['data_inizio']);
      }
      final maxRes = await _supa
          .from('dislocazione_personale')
          .select('data_fine')
          .order('data_fine', ascending: false)
          .limit(1);
      if (maxRes.isNotEmpty) {
        maxD = parseIsoDate(maxRes.first['data_fine']) ?? minD;
      }
    } catch (_) {}
    return (min: minD, max: maxD);
  }

  /// Righe che intersecano [dal, al].
  Future<List<Map<String, dynamic>>> loadRigheNelPeriodo({
    required DateTime dal,
    required DateTime al,
    String? nominativo,
  }) async {
    final start = _iso(dal);
    final end = _iso(al);
    var q = _supa
        .from('dislocazione_personale')
        .select('nominativo, abilitazioni, commessa_id, stato, data_inizio, data_fine')
        .lte('data_inizio', end)
        .gte('data_fine', start); // intersezione [dal, al]
    if (nominativo != null && nominativo.trim().isNotEmpty) {
      q = q.eq('nominativo', nominativo.trim());
    }

    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final res = await q
          .order('nominativo')
          .order('data_inizio')
          .range(from, from + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (list.isEmpty) break;
      out.addAll(list);
      if (list.length < _pageSize) break;
      from += _pageSize;
    }
    return out;
  }

  /// Ferie, permessi, malattia, infortunio approvati/segnalati su [cache].
  /// Sovrascrive la commessa nei giorni di assenza (il dipendente non è in cantiere).
  Future<void> overlayAssenzeSuCache({
    required Map<String, Map<DateTime, DislocazioneGiornoValore>> cache,
    required DateTime dal,
    required DateTime al,
    required List<String> nominativiCanoni,
  }) async {
    if (nominativiCanoni.isEmpty) return;
    final start = dateOnly(dal);
    final end = dateOnly(al);
    List<dynamic> rows;
    try {
      rows = await _supa
          .from('dipendente_assenze')
          .select(
            'tipo_assenza,data_dal,data_al,workflow_status,'
            'segnalazione_admin,dipendente_nome,personale_id_uuid,active',
          )
          .eq('active', true)
          .lte('data_dal', _iso(end))
          .gte('data_al', _iso(start));
    } catch (_) {
      return;
    }

    final idToNome = <String, String>{};
    var from = 0;
    while (true) {
      final res = await _supa
          .from('personale')
          .select('id_uuid,full_name')
          .range(from, from + _pageSize - 1);
      final list = res as List;
      if (list.isEmpty) break;
      for (final raw in list) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        final nome = (m['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && nome.isNotEmpty) idToNome[id] = nome;
      }
      if (list.length < _pageSize) break;
      from += _pageSize;
    }

    final byId = <String, String>{
      for (final n in nominativiCanoni) n: n,
    };

    String? resolveNome(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      final key = _nomKey(t);
      for (final n in nominativiCanoni) {
        if (_nomKey(n) == key) return n;
      }
      return PersonaleNameMatcher.findPersonaleIdByNominativoDislocazione(
        t,
        byId,
      );
    }

    for (final raw in rows) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (!_assenzaVisibileInDislocazione(m)) continue;
      final tipo = _normalizzaTipoAssenza(
        (m['tipo_assenza'] ?? '').toString(),
      );
      if (tipo.isEmpty) continue;
      final pid = (m['personale_id_uuid'] ?? '').toString().trim();
      final nome = resolveNome(idToNome[pid] ?? '') ??
          resolveNome((m['dipendente_nome'] ?? '').toString());
      if (nome == null) continue;
      final aDal = parseIsoDate(m['data_dal']);
      final aAl = parseIsoDate(m['data_al']) ?? aDal;
      if (aDal == null) continue;
      var d = aDal.isBefore(start) ? start : aDal;
      final last = aAl == null || aAl.isAfter(end) ? end : aAl;
      final val = DislocazioneGiornoValore(stato: tipo);
      final map = cache.putIfAbsent(
        nome,
        () => <DateTime, DislocazioneGiornoValore>{},
      );
      while (!d.isAfter(last)) {
        map[d] = val;
        d = d.add(const Duration(days: 1));
      }
    }
  }

  static bool _assenzaVisibileInDislocazione(Map<String, dynamic> row) {
    final segnalazione = row['segnalazione_admin'];
    if (segnalazione == true ||
        segnalazione == 'true' ||
        segnalazione == 't') {
      return true;
    }
    final st = (row['workflow_status'] ?? '').toString().trim().toUpperCase();
    return st == 'APPROVATA_ADMIN' || st == 'APPROVATA_DT';
  }

  static String _normalizzaTipoAssenza(String raw) {
    final up = raw.trim().toUpperCase();
    switch (up) {
      case 'PERMESSI':
        return 'PERMESSO';
      case 'MALATTIE':
        return 'MALATTIA';
      case 'INFORTUNI':
        return 'INFORTUNIO';
      default:
        return up;
    }
  }

  Future<List<Map<String, dynamic>>> loadRighePerNominativo(String nominativo) async {
    final res = await _supa
        .from('dislocazione_personale')
        .select()
        .eq('nominativo', nominativo)
        .order('data_inizio');
    return List<Map<String, dynamic>>.from(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  /// Salva assegnazione di un singolo giorno (ricomprime tutti i periodi della persona).
  Future<void> salvaGiorno({
    required String nominativo,
    required String? abilitazioni,
    String? attivita,
    required DateTime giorno,
    required DislocazioneGiornoValore valore,
    Map<DateTime, DislocazioneGiornoValore>? giorniAttuali,
  }) async {
    await salvaIntervalloGiorni(
      nominativo: nominativo,
      abilitazioni: abilitazioni,
      attivita: attivita,
      dal: giorno,
      al: giorno,
      valore: valore,
      giorniAttuali: giorniAttuali,
    );
  }

  /// Copia lo stesso valore su più giorni consecutivi (trascinamento tipo Excel).
  /// [giorniAttuali] (cache UI) viene unita ai dati completi dal DB: la cache
  /// contiene solo la finestra visibile, non va usata da sola.
  Future<void> salvaIntervalloGiorni({
    required String nominativo,
    required String? abilitazioni,
    String? attivita,
    required DateTime dal,
    required DateTime al,
    required DislocazioneGiornoValore valore,
    Map<DateTime, DislocazioneGiornoValore>? giorniAttuali,
  }) async {
    final map = await _giorniConVarianti(nominativo);
    if (giorniAttuali != null) {
      for (final e in giorniAttuali.entries) {
        if (e.value.isEmpty) {
          map.remove(e.key);
        } else {
          map[e.key] = e.value;
        }
      }
    }
    var d = dateOnly(dal.isBefore(al) ? dal : al);
    final end = dateOnly(dal.isBefore(al) ? al : dal);
    while (!d.isAfter(end)) {
      if (valore.isEmpty) {
        map.remove(d);
      } else {
        map[d] = valore;
      }
      d = d.add(const Duration(days: 1));
    }
    final payloads = comprimiGiorni(
      nominativo: nominativo.trim(),
      abilitazioni: abilitazioni,
      attivita: attivita,
      giorni: map,
    );
    await _eliminaTutteVariantiNominativo(nominativo);
    if (payloads.isNotEmpty) {
      await _supa.from('dislocazione_personale').insert(payloads);
    }
  }

  /// Applica modifiche puntuali (es. undo, incolla): [null] = rimuovi il giorno.
  /// [giorniAttuali] unisce la cache UI (finestra visibile) prima di salvare.
  Future<void> applicaModificheGiorni({
    required String nominativo,
    required String? abilitazioni,
    String? attivita,
    required Map<DateTime, DislocazioneGiornoValore?> modifiche,
    Map<DateTime, DislocazioneGiornoValore>? giorniAttuali,
  }) async {
    if (modifiche.isEmpty) return;

    final map = await _giorniConVarianti(nominativo);

    if (giorniAttuali != null) {
      for (final e in giorniAttuali.entries) {
        final d = dateOnly(e.key);
        if (e.value.isEmpty) {
          map.remove(d);
        } else {
          map[d] = e.value;
        }
      }
    }

    for (final e in modifiche.entries) {
      final d = dateOnly(e.key);
      final v = e.value;
      if (v == null || v.isEmpty) {
        map.remove(d);
      } else {
        map[d] = v;
      }
    }

    final payloads = comprimiGiorni(
      nominativo: nominativo.trim(),
      abilitazioni: abilitazioni,
      attivita: attivita,
      giorni: map,
    );
    await _eliminaTutteVariantiNominativo(nominativo);
    if (payloads.isNotEmpty) {
      await _supa.from('dislocazione_personale').insert(payloads);
    }
  }

  Future<void> _sostituisciRigheNominativo(
    String nominativo,
    List<Map<String, dynamic>> payloads,
  ) async {
    await _supa.from('dislocazione_personale').delete().eq('nominativo', nominativo);
    if (payloads.isEmpty) return;
    await _supa.from('dislocazione_personale').insert(payloads);
  }

  /// Aggiorna abilitazioni e/o attività su tutte le righe del nominativo.
  Future<bool> aggiornaMetaPersona({
    required String nominativo,
    String? abilitazioni,
    String? attivita,
    bool updateAbilitazioni = false,
    bool updateAttivita = false,
  }) async {
    if (!updateAbilitazioni && !updateAttivita) return false;
    final righe = await loadRighePerNominativo(nominativo);
    if (righe.isEmpty) return false;

    String? ab;
    if (updateAbilitazioni) {
      ab = abilitazioni?.trim();
      if (ab != null && ab.isEmpty) ab = null;
    } else {
      ab = (righe.first['abilitazioni'] ?? '').toString().trim();
      if (ab.isEmpty) ab = null;
    }

    String? at;
    if (updateAttivita) {
      at = attivita?.trim();
      if (at != null && at.isEmpty) at = null;
    } else {
      at = (righe.first['attivita'] ?? '').toString().trim();
      if (at.isEmpty) at = null;
    }

    final map = espandiPeriodi(righe);
    final payloads = comprimiGiorni(
      nominativo: nominativo,
      abilitazioni: ab,
      attivita: at,
      giorni: map,
    );
    await _sostituisciRigheNominativo(nominativo, payloads);
    return true;
  }

  /// Aggiorna il campo abilitazioni su tutte le righe del nominativo.
  Future<bool> aggiornaAbilitazioni({
    required String nominativo,
    required String? abilitazioni,
  }) async {
    return aggiornaMetaPersona(
      nominativo: nominativo,
      abilitazioni: abilitazioni,
      updateAbilitazioni: true,
    );
  }

  Future<bool> aggiornaAttivita({
    required String nominativo,
    required String? attivita,
  }) async {
    return aggiornaMetaPersona(
      nominativo: nominativo,
      attivita: attivita,
      updateAttivita: true,
    );
  }

  /// Track Formazione RFI con date di scadenza/rinnovo (come pagina Formazione RFI).
  Future<List<FormazioneRfiTrackInfo>> loadFormazioniRfiTracksPerNominativo(
    String nominativo,
  ) async {
    final map = await loadFormazioniRfiTracksPerNominativi([nominativo]);
    return map[nominativo.trim()] ?? const [];
  }

  /// Carica Formazioni RFI per più nominativi (una query records).
  Future<Map<String, List<FormazioneRfiTrackInfo>>>
      loadFormazioniRfiTracksPerNominativi(
    Iterable<String> nominativi,
  ) async {
    final noms = nominativi
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (noms.isEmpty) return const {};

    final personaleRes = await _supa
        .from('personale')
        .select('id, id_uuid, full_name')
        .eq('active', true)
        .order('full_name');
    final byUuid = <String, String>{};
    final idByUuid = <String, int>{};
    for (final raw in personaleRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = int.tryParse((m['id'] ?? '').toString());
      final uuid = (m['id_uuid'] ?? '').toString().trim();
      final full = (m['full_name'] ?? '').toString().trim();
      if (id == null || uuid.isEmpty || full.isEmpty) continue;
      byUuid[uuid] = full;
      idByUuid[uuid] = id;
    }

    final pidByNominativo = <String, int>{};
    final nominativiByPid = <int, List<String>>{};
    for (final nome in noms) {
      final uuid = PersonaleNameMatcher.findPersonaleIdByNominativoDislocazione(
        nome,
        byUuid,
      );
      if (uuid == null) continue;
      final pid = idByUuid[uuid];
      if (pid == null) continue;
      pidByNominativo[nome] = pid;
      nominativiByPid.putIfAbsent(pid, () => <String>[]).add(nome);
    }
    if (pidByNominativo.isEmpty) {
      return {for (final n in noms) n: const <FormazioneRfiTrackInfo>[]};
    }

    final pids = pidByNominativo.values.toSet().toList(growable: false);
    final res = await _supa
        .from('formazione_rfi_records')
        .select('personale_id, track_key, field_key, value_date, value_text')
        .inFilter('personale_id', pids);

    final tracksWithValueByPid = <int, Set<String>>{};
    final scadenzaByPidTrack = <int, Map<String, DateTime>>{};
    final rinnovoByPidTrack = <int, Map<String, DateTime>>{};

    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final pid = int.tryParse((m['personale_id'] ?? '').toString());
      if (pid == null) continue;
      final track = (m['track_key'] ?? '').toString().trim();
      if (track.isEmpty) continue;
      final field = (m['field_key'] ?? '').toString().trim();
      final dateRaw = (m['value_date'] ?? '').toString().trim();
      final textRaw = (m['value_text'] ?? '').toString().trim();
      if (dateRaw.isEmpty && textRaw.isEmpty) continue;
      tracksWithValueByPid.putIfAbsent(pid, () => <String>{}).add(track);

      final dt = _parseRfiDate(dateRaw.isNotEmpty ? dateRaw : textRaw);
      if (dt == null) continue;
      final n = _normRfiField(field);
      if (n.contains('mantenimento 2') || n.contains('mantenimento 3')) {
        continue;
      }
      if (n.startsWith('rinnovo') ||
          (n.contains('scadenza') && n.contains('rinnovo'))) {
        rinnovoByPidTrack.putIfAbsent(pid, () => <String, DateTime>{})[track] =
            dt;
        continue;
      }
      if (n == 'prossima scadenza' ||
          (n.contains('prossima') && n.contains('scadenza')) ||
          (n.contains('scadenza') && !n.contains('mantenimento'))) {
        final map = scadenzaByPidTrack.putIfAbsent(pid, () => <String, DateTime>{});
        final prev = map[track];
        if (prev == null || dt.isBefore(prev)) {
          map[track] = dt;
        }
      }
    }

    final out = <String, List<FormazioneRfiTrackInfo>>{
      for (final n in noms) n: const <FormazioneRfiTrackInfo>[],
    };
    for (final e in nominativiByPid.entries) {
      final pid = e.key;
      final tracks = tracksWithValueByPid[pid] ?? const <String>{};
      final scadMap = scadenzaByPidTrack[pid] ?? const <String, DateTime>{};
      final rinnMap = rinnovoByPidTrack[pid] ?? const <String, DateTime>{};
      final list = tracks
          .map(
            (track) => FormazioneRfiTrackInfo(
              track: track,
              scadenza: scadMap[track],
              rinnovo: rinnMap[track],
            ),
          )
          .toList()
        ..sort((a, b) => a.track.toLowerCase().compareTo(b.track.toLowerCase()));
      for (final nome in e.value) {
        out[nome] = list;
      }
    }
    return out;
  }

  static String _normRfiField(String value) {
    final lower = value.toLowerCase().replaceAll('_', ' ');
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DateTime? _parseRfiDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (dateOnly != null) {
      final y = int.tryParse(dateOnly.group(1)!);
      final m = int.tryParse(dateOnly.group(2)!);
      final d = int.tryParse(dateOnly.group(3)!);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    final it = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(value);
    if (it != null) {
      final d = int.tryParse(it.group(1)!);
      final m = int.tryParse(it.group(2)!);
      final y = int.tryParse(it.group(3)!);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return null;
  }

  /// Nomi anagrafica attiva: chiave normalizzata → [full_name] come in app.
  Future<Map<String, String>> loadPersonaleNomiPerChiave() async {
    final out = <String, String>{};
    var from = 0;
    while (true) {
      final res = await _supa
          .from('personale')
          .select('full_name')
          .eq('active', true)
          .order('full_name')
          .range(from, from + _pageSize - 1);
      final list = res as List;
      if (list.isEmpty) break;
      for (final raw in list) {
        final nome = (raw['full_name'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        out.putIfAbsent(_nomKey(nome), () => nome);
      }
      if (list.length < _pageSize) break;
      from += _pageSize;
    }
    return out;
  }

  /// Nominativi distinti presenti in tabella dislocazione (testo esatto su DB).
  Future<List<String>> loadNominativiDislocazioneDistinti() async {
    final out = <String>{};
    var from = 0;
    while (true) {
      final res = await _supa
          .from('dislocazione_personale')
          .select('nominativo')
          .order('nominativo')
          .range(from, from + _pageSize - 1);
      final list = res as List;
      if (list.isEmpty) break;
      for (final raw in list) {
        final nome = (raw['nominativo'] ?? '').toString().trim();
        if (nome.isNotEmpty) out.add(nome);
      }
      if (list.length < _pageSize) break;
      from += _pageSize;
    }
    final sorted = out.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  static List<String> tokenizzaNome(String nominativo) {
    return nominativo
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static bool isPrefissoTokenNome(List<String> corto, List<String> lungo) {
    if (corto.length < 2 || lungo.length <= corto.length) return false;
    for (var i = 0; i < corto.length; i++) {
      if (corto[i] != lungo[i]) return false;
    }
    return true;
  }

  /// Trova coppie nome incompleto → nome completo (priorità anagrafica app).
  List<NominativoMergeCoppia> trovaCoppieUnioneNominativi({
    required List<String> tuttiNominativi,
    required Map<String, String> personalePerChiave,
  }) {
    final tokens = <String, List<String>>{
      for (final n in tuttiNominativi) n: tokenizzaNome(n),
    };
    final usatiComeIncompleti = <String>{};
    final out = <NominativoMergeCoppia>[];

    final ordinati = List<String>.from(tuttiNominativi)
      ..sort((a, b) => tokens[a]!.length.compareTo(tokens[b]!.length));

    for (final corto in ordinati) {
      final tc = tokens[corto]!;
      if (tc.length < 2) continue;
      final keyCorto = _nomKey(corto);
      if (usatiComeIncompleti.contains(keyCorto)) continue;

      final candidati = <String>[];
      for (final lungo in tuttiNominativi) {
        if (lungo == corto) continue;
        final tl = tokens[lungo]!;
        if (isPrefissoTokenNome(tc, tl)) candidati.add(lungo);
      }
      if (candidati.isEmpty) continue;

      var completo = candidati.first;
      for (var i = 1; i < candidati.length; i++) {
        completo = _preferisciNomeCompleto(
          completo,
          candidati[i],
          personalePerChiave,
        );
      }

      if (tokens[completo]!.length <= tc.length) continue;
      if (_nomKey(completo) == keyCorto) continue;

      usatiComeIncompleti.add(keyCorto);
      out.add(NominativoMergeCoppia(incompleto: corto, completo: completo));
    }

    out.sort((a, b) => a.incompleto.compareTo(b.incompleto));
    return out;
  }

  static String _preferisciNomeCompleto(
    String a,
    String b,
    Map<String, String> personalePerChiave,
  ) {
    final aInApp = personalePerChiave.containsKey(_nomKey(a));
    final bInApp = personalePerChiave.containsKey(_nomKey(b));
    if (aInApp && !bInApp) return a;
    if (bInApp && !aInApp) return b;
    final ta = tokenizzaNome(a);
    final tb = tokenizzaNome(b);
    if (tb.length != ta.length) return tb.length > ta.length ? b : a;
    return a.length >= b.length ? a : b;
  }

  String _nomeCanonicoTarget(
    String completo,
    Map<String, String> personalePerChiave,
  ) {
    return personalePerChiave[_nomKey(completo)] ?? completo;
  }

  /// Anteprima: quanti giorni verrebbero copiati dal nome incompleto.
  Future<int> contaGiorniDaUnire({
    required String incompleto,
    required String completo,
  }) async {
    final da = espandiPeriodi(await loadRighePerNominativo(incompleto));
    if (da.isEmpty) return 0;
    final a = espandiPeriodi(await loadRighePerNominativo(completo));
    var n = 0;
    for (final e in da.entries) {
      final esistente = a[e.key];
      if (esistente == null || esistente.isEmpty) n++;
    }
    return n;
  }

  /// Sposta dati dal nominativo incompleto al completo (anagrafica app) ed elimina l'incompleto.
  Future<void> unisciNominativo({
    required String incompleto,
    required String completo,
    required Map<String, String> personalePerChiave,
  }) async {
    if (_nomKey(incompleto) == _nomKey(completo)) return;

    final target = _nomeCanonicoTarget(completo, personalePerChiave);
    final righeIncompleto = await loadRighePerNominativo(incompleto);
    final righeCompleto = <Map<String, dynamic>>[
      ...await loadRighePerNominativo(completo),
      if (_nomKey(completo) != _nomKey(target))
        ...await loadRighePerNominativo(target),
    ];

    String? abilita;
    String? attivita;
    for (final r in [...righeCompleto, ...righeIncompleto]) {
      final ab = (r['abilitazioni'] ?? '').toString().trim();
      if (ab.isNotEmpty) abilita ??= ab;
      final at = (r['attivita'] ?? '').toString().trim();
      if (at.isNotEmpty) attivita ??= at;
    }

    final mapTarget = espandiPeriodi(righeCompleto);
    final mapSource = espandiPeriodi(righeIncompleto);
    for (final e in mapSource.entries) {
      final esistente = mapTarget[e.key];
      if (esistente == null || esistente.isEmpty) {
        mapTarget[e.key] = e.value;
      }
    }

    final payloads = comprimiGiorni(
      nominativo: target,
      abilitazioni: abilita,
      attivita: attivita,
      giorni: mapTarget,
    );
    await _sostituisciRigheNominativo(target, payloads);
    await _eliminaTutteVariantiNominativo(incompleto);
  }

  Future<Map<DateTime, DislocazioneGiornoValore>> _giorniConVarianti(
    String nominativo,
  ) async {
    final map = <DateTime, DislocazioneGiornoValore>{};
    for (final v in await _variantiPerChiave(nominativo)) {
      for (final e in espandiPeriodi(await loadRighePerNominativo(v)).entries) {
        map.putIfAbsent(e.key, () => e.value);
      }
    }
    return map;
  }

  Future<void> _eliminaTutteVariantiNominativo(String nominativo) async {
    final key = _nomKey(nominativo);
    final distinti = await loadNominativiDislocazioneDistinti();
    for (final n in distinti) {
      if (_nomKey(n) == key) {
        await _supa.from('dislocazione_personale').delete().eq('nominativo', n);
      }
    }
  }

  Future<List<String>> _variantiPerChiave(String nominativo) async {
    final key = _nomKey(nominativo);
    final distinti = await loadNominativiDislocazioneDistinti();
    final varianti = distinti.where((n) => _nomKey(n) == key).toList();
    if (varianti.isEmpty) varianti.add(nominativo.trim());
    return varianti;
  }

  /// Rinomina un nominativo (aggiorna dislocazione, unisce se esiste già omonimo).
  Future<void> rinominaNominativo({
    required String vecchio,
    required String nuovo,
  }) async {
    final oldName = vecchio.trim();
    final newName = nuovo.trim();
    if (oldName.isEmpty || newName.isEmpty) {
      throw ArgumentError('Il nominativo non può essere vuoto.');
    }
    if (oldName == newName) return;

    final oldKey = _nomKey(oldName);
    final newKey = _nomKey(newName);

    String? abilita;
    String? attivita;
    final mapSource = <DateTime, DislocazioneGiornoValore>{};
    for (final v in await _variantiPerChiave(oldName)) {
      for (final r in await loadRighePerNominativo(v)) {
        final ab = (r['abilitazioni'] ?? '').toString().trim();
        if (ab.isNotEmpty) abilita ??= ab;
        final at = (r['attivita'] ?? '').toString().trim();
        if (at.isNotEmpty) attivita ??= at;
      }
      final map = espandiPeriodi(await loadRighePerNominativo(v));
      for (final e in map.entries) {
        final prev = mapSource[e.key];
        if (prev == null || prev.isEmpty) {
          mapSource[e.key] = e.value;
        }
      }
    }

    final mapTarget = <DateTime, DislocazioneGiornoValore>{};
    if (newKey != oldKey) {
      for (final v in await _variantiPerChiave(newName)) {
        for (final r in await loadRighePerNominativo(v)) {
          final ab = (r['abilitazioni'] ?? '').toString().trim();
          if (ab.isNotEmpty) abilita ??= ab;
          final at = (r['attivita'] ?? '').toString().trim();
          if (at.isNotEmpty) attivita ??= at;
        }
        final map = espandiPeriodi(await loadRighePerNominativo(v));
        for (final e in map.entries) {
          final prev = mapTarget[e.key];
          if (prev == null || prev.isEmpty) {
            mapTarget[e.key] = e.value;
          }
        }
      }
    }

    final merged = Map<DateTime, DislocazioneGiornoValore>.from(mapTarget);
    for (final e in mapSource.entries) {
      final esistente = merged[e.key];
      if (esistente == null || esistente.isEmpty) {
        merged[e.key] = e.value;
      }
    }

    await _eliminaTutteVariantiNominativo(oldName);
    if (newKey != oldKey) {
      await _eliminaTutteVariantiNominativo(newName);
    }

    if (merged.isNotEmpty) {
      final payloads = comprimiGiorni(
        nominativo: newName,
        abilitazioni: abilita,
        attivita: attivita,
        giorni: merged,
      );
      if (payloads.isNotEmpty) {
        await _supa.from('dislocazione_personale').insert(payloads);
      }
    }

    if (mapSource.isEmpty && oldKey != newKey) {
      await _supa.from('dislocazione_nominativi_esclusi').upsert(
        <String, dynamic>{
          'nominativo_chiave': oldKey,
          'nominativo_originale': oldName,
          'escluso_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'nominativo_chiave',
      );
    }

    if (oldKey != newKey) {
      await rimuoviEsclusioneNominativo(newName);
    }
  }

  /// Trova e unisce tutte le coppie incompleto → completo.
  Future<UnificaNominativiRisultato> unificaTuttiNominativiDuplicati() async {
    final personale = await loadPersonaleNomiPerChiave();
    final daDislocazione = await loadNominativiDislocazioneDistinti();
    final persone = await loadPersone();
    final tutti = <String>{
      ...daDislocazione,
      ...persone.map((p) => p.nominativo),
      ...personale.values,
    }.toList();

    final coppie = trovaCoppieUnioneNominativi(
      tuttiNominativi: tutti,
      personalePerChiave: personale,
    );

    var unite = 0;
    var giorniCopiati = 0;
    for (final c in coppie) {
      giorniCopiati += await contaGiorniDaUnire(
        incompleto: c.incompleto,
        completo: c.completo,
      );
      await unisciNominativo(
        incompleto: c.incompleto,
        completo: c.completo,
        personalePerChiave: personale,
      );
      unite++;
    }

    return UnificaNominativiRisultato(
      coppie: coppie,
      unite: unite,
      giorniCopiati: giorniCopiati,
    );
  }

  /// Sostituisce le assegnazioni dal file Excel. I nominativi restano [esistenti].
  Future<DislocazioneImportEsito> importaProgrammaImpegnoSostituendo({
    required Uint8List bytes,
    required List<PersonaRiga> esistenti,
    required Map<String, String> commesse,
    required List<String> statiCatalogo,
  }) async {
    final parsed = DislocazioneProgrammaImpegnoImport.parseBytes(bytes);
    final nomi = esistenti.map((p) => p.nominativo).toList(growable: false);
    final abilitaPerNome = <String, String?>{
      for (final p in esistenti) p.nominativo: p.abilitazioni,
    };
    final attivitaPerNome = <String, String?>{
      for (final p in esistenti) p.nominativo: p.attivita,
    };
    final giorniPerNome = <String, Map<DateTime, DislocazioneGiornoValore>>{
      for (final p in esistenti) p.nominativo: <DateTime, DislocazioneGiornoValore>{},
    };

    var importati = 0;
    var saltati = 0;
    var attivitaImportate = 0;
    for (final excelP in parsed.persone) {
      final nome = DislocazioneProgrammaImpegnoImport.matchNominativoEsistente(
        nominativoExcel: excelP.nominativoExcel,
        nominativiEsistenti: nomi,
      );
      if (nome == null) {
        saltati++;
        continue;
      }
      importati++;
      if ((excelP.abilitazioni ?? '').trim().isNotEmpty) {
        final existingAb = (abilitaPerNome[nome] ?? '').trim();
        // Non sovrascrivere abilitazioni già impostate in app.
        if (existingAb.isEmpty) {
          abilitaPerNome[nome] = excelP.abilitazioni!.trim();
        }
      }
      final at = DislocazioneProgrammaImpegnoImport.normalizzaAttivita(
        excelP.attivita,
      );
      if (at != null) {
        final existingAt = (attivitaPerNome[nome] ?? '').trim();
        // Non cancellare/sovrascrivere DT, PM, ecc. già impostati.
        if (existingAt.isEmpty) {
          attivitaPerNome[nome] = at;
          attivitaImportate++;
        }
      }
      final map = giorniPerNome[nome]!;
      for (final e in excelP.giorni.entries) {
        final val = parseDislocazioneTesto(
          e.value,
          statiCatalogo: statiCatalogo,
          commesse: commesse,
        );
        if (val == null || val.isEmpty) continue;
        map[dateOnly(e.key)] = val;
      }
    }

    final payloads = <Map<String, dynamic>>[];
    for (final p in esistenti) {
      final giorni =
          giorniPerNome[p.nominativo] ?? <DateTime, DislocazioneGiornoValore>{};
      final ab = abilitaPerNome[p.nominativo];
      final at = attivitaPerNome[p.nominativo];
      final periodi = comprimiGiorni(
        nominativo: p.nominativo,
        abilitazioni: ab,
        attivita: at,
        giorni: giorni,
      );
      if (periodi.isNotEmpty) {
        payloads.addAll(periodi);
      } else if ((at ?? '').trim().isNotEmpty || (ab ?? '').trim().isNotEmpty) {
        // Solo meta (attività/abilitazioni) senza giorni: riga senza date.
        payloads.add(<String, dynamic>{
          'nominativo': p.nominativo,
          'abilitazioni': ab,
          'attivita': at,
          'commessa_id': null,
          'stato': null,
          'data_inizio': null,
          'data_fine': null,
          'active': true,
        });
      }
    }

    await _svuotaDislocazione();
    const chunk = 250;
    for (var i = 0; i < payloads.length; i += chunk) {
      final end = i + chunk > payloads.length ? payloads.length : i + chunk;
      await _supa.from('dislocazione_personale').insert(payloads.sublist(i, end));
    }

    return DislocazioneImportEsito(
      importati: importati,
      saltatiExcel: saltati,
      periodi: payloads.length,
      attivitaImportate: attivitaImportate,
    );
  }

  Future<void> _svuotaDislocazione() async {
    try {
      await _supa
          .from('dislocazione_personale')
          .delete()
          .gte('created_at', '1970-01-01T00:00:00Z');
    } catch (_) {
      final distinti = await loadNominativiDislocazioneDistinti();
      for (final n in distinti) {
        await _supa.from('dislocazione_personale').delete().eq('nominativo', n);
      }
    }
  }

  static String _iso(DateTime d) {
    final x = dateOnly(d);
    return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }
}

class FormazioneRfiTrackInfo {
  const FormazioneRfiTrackInfo({
    required this.track,
    this.scadenza,
    this.rinnovo,
  });

  final String track;
  final DateTime? scadenza;
  final DateTime? rinnovo;
}

class PersonaRiga {
  const PersonaRiga({
    required this.nominativo,
    this.abilitazioni,
    this.attivita,
  });

  final String nominativo;
  final String? abilitazioni;
  /// Tipo attività (LFM, IS, TE, OP. CIVILI, …).
  final String? attivita;
}

class NominativoMergeCoppia {
  const NominativoMergeCoppia({
    required this.incompleto,
    required this.completo,
  });

  final String incompleto;
  final String completo;
}

class UnificaNominativiRisultato {
  const UnificaNominativiRisultato({
    required this.coppie,
    required this.unite,
    required this.giorniCopiati,
  });

  final List<NominativoMergeCoppia> coppie;
  final int unite;
  final int giorniCopiati;
}
