import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logistica_box_linked_sync.dart';
import 'supabase_service.dart';

class MdoFerroviarioRiga {
  const MdoFerroviarioRiga({
    required this.id,
    required this.matricolaInterna,
    required this.targaRfi,
    required this.descrizione,
    required this.modello,
    required this.commessa,
    required this.cantiereAttuale,
    required this.dtNome,
    this.posizioneGps,
  });

  final String id;
  final String matricolaInterna;
  final String targaRfi;
  final String descrizione;
  final String modello;
  final String commessa;
  final String cantiereAttuale;
  final String dtNome;
  final String? posizioneGps;

  String get titolo {
    if (matricolaInterna.isNotEmpty && descrizione.isNotEmpty) {
      return '$matricolaInterna · $descrizione';
    }
    if (matricolaInterna.isNotEmpty) return matricolaInterna;
    if (descrizione.isNotEmpty) return descrizione;
    return targaRfi.isNotEmpty ? targaRfi : id;
  }

  String get sottotitolo {
    final parts = <String>[
      if (targaRfi.isNotEmpty) 'Targa RFI: $targaRfi',
      if (modello.isNotEmpty) 'Modello: $modello',
      if (dtNome.isNotEmpty) 'DT: $dtNome',
    ];
    return parts.join(' · ');
  }
}

class MdoCommessaGroup {
  const MdoCommessaGroup({
    required this.commessaKey,
    required this.label,
    required this.mezzi,
  });

  /// Chiave normalizzata ('' = senza commessa).
  final String commessaKey;
  final String label;
  final List<MdoFerroviarioRiga> mezzi;

  int get count => mezzi.length;
}

/// Trasferimento MDO in corso / storico.
class MdoTrasferimento {
  const MdoTrasferimento({
    required this.id,
    required this.mdoId,
    required this.mdoLabel,
    required this.matricolaInterna,
    required this.targaRfi,
    required this.commessaOrigine,
    required this.cantiereOrigine,
    required this.commessaDestinazione,
    required this.cantiereDestinazione,
    required this.aggiornaCantiere,
    required this.periodoTipo,
    required this.dataInizio,
    required this.dataFine,
    required this.stato,
    this.note,
    this.trasportatore,
    this.createdAt,
    this.referenteCaricoPersonaleUuid,
    this.referenteCaricoNome,
    this.referenteCaricoTelefono,
    this.referenteScaricoPersonaleUuid,
    this.referenteScaricoNome,
    this.referenteScaricoTelefono,
    this.luogoCarico,
    this.luogoScarico,
    this.modalitaCarico,
    this.modalitaScarico,
  });

  final String id;
  final String mdoId;
  final String mdoLabel;
  final String matricolaInterna;
  final String targaRfi;
  final String commessaOrigine;
  final String cantiereOrigine;
  final String commessaDestinazione;
  final String? cantiereDestinazione;
  final bool aggiornaCantiere;
  /// `giorno` | `settimana`
  final String periodoTipo;
  final DateTime dataInizio;
  final DateTime dataFine;
  /// `in_corso` | `completato` | `annullato`
  final String stato;
  final String? note;
  final String? trasportatore;
  final DateTime? createdAt;
  final String? referenteCaricoPersonaleUuid;
  final String? referenteCaricoNome;
  final String? referenteCaricoTelefono;
  final String? referenteScaricoPersonaleUuid;
  final String? referenteScaricoNome;
  final String? referenteScaricoTelefono;
  final String? luogoCarico;
  final String? luogoScarico;
  /// `piano_a_raso` | `gru`
  final String? modalitaCarico;
  /// `piano_a_raso` | `gru`
  final String? modalitaScarico;

  bool get isInCorso => stato == 'in_corso';

  static String? _emptyToNull(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String periodoLabel([DateFormat? df]) {
    final fmt = df ?? DateFormat('dd/MM/yyyy');
    if (periodoTipo == 'settimana' || dataInizio != dataFine) {
      return '${fmt.format(dataInizio)} – ${fmt.format(dataFine)}'
          '${periodoTipo == 'settimana' ? ' (settimana)' : ''}';
    }
    return fmt.format(dataInizio);
  }

  static MdoTrasferimento fromMap(Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return DateTime(v.year, v.month, v.day);
      final s = (v ?? '').toString();
      final d = DateTime.tryParse(s);
      if (d == null) return DateTime.now();
      return DateTime(d.year, d.month, d.day);
    }

    return MdoTrasferimento(
      id: (m['id_uuid'] ?? '').toString(),
      mdoId: (m['mdo_id'] ?? '').toString(),
      mdoLabel: (m['mdo_label'] ?? '').toString().trim(),
      matricolaInterna: (m['matricola_interna'] ?? '').toString().trim(),
      targaRfi: (m['targa_rfi'] ?? '').toString().trim(),
      commessaOrigine: (m['commessa_origine'] ?? '').toString().trim(),
      cantiereOrigine: (m['cantiere_origine'] ?? '').toString().trim(),
      commessaDestinazione: (m['commessa_destinazione'] ?? '').toString().trim(),
      cantiereDestinazione: (m['cantiere_destinazione'] as String?)?.trim(),
      aggiornaCantiere: m['aggiorna_cantiere'] == true,
      periodoTipo: (m['periodo_tipo'] ?? 'giorno').toString(),
      dataInizio: parseDate(m['data_inizio']),
      dataFine: parseDate(m['data_fine']),
      stato: (m['stato'] ?? 'in_corso').toString(),
      note: _emptyToNull(m['note']),
      trasportatore: _emptyToNull(m['trasportatore']),
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
      referenteCaricoPersonaleUuid: _emptyToNull(m['referente_carico_personale_uuid']),
      referenteCaricoNome: _emptyToNull(m['referente_carico_nome']),
      referenteCaricoTelefono: _emptyToNull(m['referente_carico_telefono']),
      referenteScaricoPersonaleUuid:
          _emptyToNull(m['referente_scarico_personale_uuid']),
      referenteScaricoNome: _emptyToNull(m['referente_scarico_nome']),
      referenteScaricoTelefono: _emptyToNull(m['referente_scarico_telefono']),
      luogoCarico: _emptyToNull(m['luogo_carico']),
      luogoScarico: _emptyToNull(m['luogo_scarico']),
      modalitaCarico: _emptyToNull(m['modalita_carico']),
      modalitaScarico: _emptyToNull(m['modalita_scarico']),
    );
  }
}

class PersonaleReferentePick {
  const PersonaleReferentePick({
    required this.idUuid,
    required this.fullName,
    this.telefono = '',
  });

  final String idUuid;
  final String fullName;
  final String telefono;

  String get label {
    final tel = telefono.trim();
    if (tel.isEmpty) return fullName;
    return '$fullName · $tel';
  }
}

/// Caricamento e trasferimento MDO ferroviari raggruppati per commessa.
abstract final class DislocazioneMdoPerCommessaService {
  DislocazioneMdoPerCommessaService._();

  static SupabaseClient get _supa => SupabaseService.client;

  static String normalizeCommessaKey(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Lunedì della settimana ISO (lun–dom) che contiene [day].
  static DateTime mondayOfWeek(DateTime day) {
    final d = dateOnly(day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static DateTime sundayOfWeek(DateTime day) =>
      mondayOfWeek(day).add(const Duration(days: 6));

  static ({DateTime inizio, DateTime fine}) resolvePeriodo({
    required String periodoTipo,
    required DateTime riferimento,
  }) {
    final d = dateOnly(riferimento);
    if (periodoTipo == 'settimana') {
      return (inizio: mondayOfWeek(d), fine: sundayOfWeek(d));
    }
    return (inizio: d, fine: d);
  }

  static Future<Map<String, String>> loadCommesseAttive() async {
    final res = await _supa
        .from('commesse')
        .select('id_uuid,nome')
        .eq('active', true)
        .order('nome');
    return {
      for (final raw in res as List)
        (raw['id_uuid'] ?? '').toString(): (raw['nome'] ?? '').toString().trim(),
    }..removeWhere((k, v) => k.isEmpty || v.isEmpty);
  }

  static Future<List<MdoFerroviarioRiga>> loadMezziAttivi() async {
    final res = await _supa
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid,matricola_interna,codice_identificativo_targa_rfi,'
          'descrizione_mezzo,modello,commessa,cantiere_attuale,dt_nome,posizione_gps',
        )
        .eq('active', true)
        .order('matricola_interna');

    final out = <MdoFerroviarioRiga>[];
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      out.add(
        MdoFerroviarioRiga(
          id: id,
          matricolaInterna: (m['matricola_interna'] ?? '').toString().trim(),
          targaRfi: (m['codice_identificativo_targa_rfi'] ?? '').toString().trim(),
          descrizione: (m['descrizione_mezzo'] ?? '').toString().trim(),
          modello: (m['modello'] ?? '').toString().trim(),
          commessa: (m['commessa'] ?? '').toString().trim(),
          cantiereAttuale: (m['cantiere_attuale'] ?? '').toString().trim(),
          dtNome: (m['dt_nome'] ?? '').toString().trim(),
          posizioneGps: (m['posizione_gps'] ?? '').toString().trim().isEmpty
              ? null
              : (m['posizione_gps'] ?? '').toString().trim(),
        ),
      );
    }
    return out;
  }

  static List<MdoCommessaGroup> groupByCommessa(List<MdoFerroviarioRiga> mezzi) {
    final map = <String, List<MdoFerroviarioRiga>>{};
    for (final m in mezzi) {
      final key = normalizeCommessaKey(m.commessa);
      map.putIfAbsent(key, () => []).add(m);
    }
    for (final list in map.values) {
      list.sort(
        (a, b) => a.matricolaInterna.toLowerCase().compareTo(
              b.matricolaInterna.toLowerCase(),
            ),
      );
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty && b.isEmpty) return 0;
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });
    return [
      for (final k in keys)
        MdoCommessaGroup(
          commessaKey: k,
          label: k.isEmpty
              ? 'Senza commessa'
              : (map[k]!.first.commessa.isEmpty
                  ? 'Senza commessa'
                  : map[k]!.first.commessa),
          mezzi: map[k]!,
        ),
    ];
  }

  static Future<List<MdoTrasferimento>> loadTrasferimentiInCorso() async {
    final res = await _supa
        .from('logistica_mdo_trasferimenti')
        .select()
        .eq('stato', 'in_corso')
        .order('data_inizio', ascending: true)
        .order('created_at', ascending: true);
    final list = [
      for (final raw in res as List)
        MdoTrasferimento.fromMap(Map<String, dynamic>.from(raw as Map)),
    ];
    list.sort((a, b) {
      final byDate = a.dataInizio.compareTo(b.dataInizio);
      if (byDate != 0) return byDate;
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca != null && cb != null) return ca.compareTo(cb);
      if (ca != null) return -1;
      if (cb != null) return 1;
      return a.mdoLabel.toLowerCase().compareTo(b.mdoLabel.toLowerCase());
    });
    return list;
  }

  static Future<List<PersonaleReferentePick>> loadPersonaleReferenti() async {
    final res = await _supa
        .from('personale')
        .select('id_uuid,full_name,telefono,active')
        .eq('active', true)
        .order('full_name');
    final out = <PersonaleReferentePick>[];
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      final name = (m['full_name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) continue;
      out.add(
        PersonaleReferentePick(
          idUuid: id,
          fullName: name,
          telefono: (m['telefono'] ?? '').toString().trim(),
        ),
      );
    }
    return out;
  }

  static Map<String, dynamic> _logisticaExtraFields({
    String? referenteCaricoPersonaleUuid,
    String? referenteCaricoNome,
    String? referenteCaricoTelefono,
    String? referenteScaricoPersonaleUuid,
    String? referenteScaricoNome,
    String? referenteScaricoTelefono,
    String? luogoCarico,
    String? luogoScarico,
    String? modalitaCarico,
    String? modalitaScarico,
    String? trasportatore,
  }) {
    String? n(String? v) {
      final s = (v ?? '').trim();
      return s.isEmpty ? null : s;
    }

    String? moda(String? v) {
      final s = n(v);
      if (s == null) return null;
      if (s == 'piano_a_raso' || s == 'gru') return s;
      return null;
    }

    return {
      'referente_carico_personale_uuid': n(referenteCaricoPersonaleUuid),
      'referente_carico_nome': n(referenteCaricoNome),
      'referente_carico_telefono': n(referenteCaricoTelefono),
      'referente_scarico_personale_uuid': n(referenteScaricoPersonaleUuid),
      'referente_scarico_nome': n(referenteScaricoNome),
      'referente_scarico_telefono': n(referenteScaricoTelefono),
      'luogo_carico': n(luogoCarico),
      'luogo_scarico': n(luogoScarico),
      'modalita_carico': moda(modalitaCarico),
      'modalita_scarico': moda(modalitaScarico),
      'trasportatore': n(trasportatore),
    };
  }

  /// Crea trasferimenti in corso (non aggiorna ancora la dislocazione MDO).
  static Future<int> creaTrasferimenti({
    required List<MdoFerroviarioRiga> mezzi,
    required String nuovaCommessa,
    String? nuovoCantiere,
    required bool aggiornaCantiere,
    required String periodoTipo,
    required DateTime dataRiferimento,
    String? note,
    String? trasportatore,
    String? referenteCaricoPersonaleUuid,
    String? referenteCaricoNome,
    String? referenteCaricoTelefono,
    String? referenteScaricoPersonaleUuid,
    String? referenteScaricoNome,
    String? referenteScaricoTelefono,
    String? luogoCarico,
    String? luogoScarico,
    String? modalitaCarico,
    String? modalitaScarico,
  }) async {
    final dest = nuovaCommessa.trim();
    if (mezzi.isEmpty || dest.isEmpty) return 0;

    final period = resolvePeriodo(
      periodoTipo: periodoTipo,
      riferimento: dataRiferimento,
    );
    final tipo = periodoTipo == 'settimana' ? 'settimana' : 'giorno';
    final extra = _logisticaExtraFields(
      referenteCaricoPersonaleUuid: referenteCaricoPersonaleUuid,
      referenteCaricoNome: referenteCaricoNome,
      referenteCaricoTelefono: referenteCaricoTelefono,
      referenteScaricoPersonaleUuid: referenteScaricoPersonaleUuid,
      referenteScaricoNome: referenteScaricoNome,
      referenteScaricoTelefono: referenteScaricoTelefono,
      luogoCarico: luogoCarico,
      luogoScarico: luogoScarico,
      modalitaCarico: modalitaCarico,
      modalitaScarico: modalitaScarico,
      trasportatore: trasportatore,
    );

    final rows = <Map<String, dynamic>>[];
    for (final m in mezzi) {
      rows.add({
        'mdo_id': m.id,
        'mdo_label': m.titolo,
        'matricola_interna': m.matricolaInterna,
        'targa_rfi': m.targaRfi,
        'commessa_origine': m.commessa,
        'cantiere_origine': m.cantiereAttuale,
        'commessa_destinazione': dest,
        'cantiere_destinazione': aggiornaCantiere &&
                (nuovoCantiere?.trim().isNotEmpty ?? false)
            ? nuovoCantiere!.trim()
            : null,
        'aggiorna_cantiere': aggiornaCantiere,
        'periodo_tipo': tipo,
        'data_inizio': DateFormat('yyyy-MM-dd').format(period.inizio),
        'data_fine': DateFormat('yyyy-MM-dd').format(period.fine),
        'stato': 'in_corso',
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        ...extra,
      });
    }

    await _supa.from('logistica_mdo_trasferimenti').insert(rows);
    return rows.length;
  }

  static Future<void> aggiornaTrasferimento({
    required String trasferimentoId,
    required String nuovaCommessa,
    String? nuovoCantiere,
    required bool aggiornaCantiere,
    required String periodoTipo,
    required DateTime dataRiferimento,
    String? note,
    String? trasportatore,
    String? referenteCaricoPersonaleUuid,
    String? referenteCaricoNome,
    String? referenteCaricoTelefono,
    String? referenteScaricoPersonaleUuid,
    String? referenteScaricoNome,
    String? referenteScaricoTelefono,
    String? luogoCarico,
    String? luogoScarico,
    String? modalitaCarico,
    String? modalitaScarico,
  }) async {
    final dest = nuovaCommessa.trim();
    if (trasferimentoId.isEmpty || dest.isEmpty) return;

    final period = resolvePeriodo(
      periodoTipo: periodoTipo,
      riferimento: dataRiferimento,
    );
    final tipo = periodoTipo == 'settimana' ? 'settimana' : 'giorno';

    await _supa.from('logistica_mdo_trasferimenti').update({
      'commessa_destinazione': dest,
      'cantiere_destinazione': aggiornaCantiere &&
              (nuovoCantiere?.trim().isNotEmpty ?? false)
          ? nuovoCantiere!.trim()
          : null,
      'aggiorna_cantiere': aggiornaCantiere,
      'periodo_tipo': tipo,
      'data_inizio': DateFormat('yyyy-MM-dd').format(period.inizio),
      'data_fine': DateFormat('yyyy-MM-dd').format(period.fine),
      if (note != null) 'note': note.trim().isEmpty ? null : note.trim(),
      ..._logisticaExtraFields(
        referenteCaricoPersonaleUuid: referenteCaricoPersonaleUuid,
        referenteCaricoNome: referenteCaricoNome,
        referenteCaricoTelefono: referenteCaricoTelefono,
        referenteScaricoPersonaleUuid: referenteScaricoPersonaleUuid,
        referenteScaricoNome: referenteScaricoNome,
        referenteScaricoTelefono: referenteScaricoTelefono,
        luogoCarico: luogoCarico,
        luogoScarico: luogoScarico,
        modalitaCarico: modalitaCarico,
        modalitaScarico: modalitaScarico,
        trasportatore: trasportatore,
      ),
    }).eq('id_uuid', trasferimentoId).eq('stato', 'in_corso');
  }

  static Future<void> annullaTrasferimento(String trasferimentoId) async {
    await _supa.from('logistica_mdo_trasferimenti').update({
      'stato': 'annullato',
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id_uuid', trasferimentoId).eq('stato', 'in_corso');
  }

  /// Conferma arrivo: aggiorna dislocazione MDO e chiude il trasferimento.
  static Future<void> confermaArrivo({
    required MdoTrasferimento t,
    Map<String, String>? commesseById,
  }) async {
    if (!t.isInCorso || t.mdoId.isEmpty) return;

    await applicaDislocazioneMezzi(
      mdoIds: [t.mdoId],
      nuovaCommessa: t.commessaDestinazione,
      nuovoCantiere: t.aggiornaCantiere ? t.cantiereDestinazione : null,
      commesseById: commesseById,
    );

    await _supa.from('logistica_mdo_trasferimenti').update({
      'stato': 'completato',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id_uuid', t.id).eq('stato', 'in_corso');
  }

  /// Aggiorna immediatamente commessa/cantiere su anagrafica MDO (+ sync box).
  static Future<int> applicaDislocazioneMezzi({
    required List<String> mdoIds,
    required String nuovaCommessa,
    String? nuovoCantiere,
    Map<String, String>? commesseById,
  }) async {
    final ids = mdoIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final dest = nuovaCommessa.trim();
    if (ids.isEmpty || dest.isEmpty) return 0;

    final payload = <String, dynamic>{
      'commessa': dest,
      if (nuovoCantiere != null)
        'cantiere_attuale':
            nuovoCantiere.trim().isEmpty ? null : nuovoCantiere.trim(),
    };

    await _supa.from('logistica_mdo_ferroviari').update(payload).inFilter('id_uuid', ids);

    for (final id in ids) {
      await propagateMdoUpdateById(
        _supa,
        id,
        commesseById: commesseById,
      );
    }
    return ids.length;
  }

  /// @Deprecated Use [creaTrasferimenti] + [confermaArrivo]. Kept for compat.
  static Future<int> trasferisciMezzi({
    required List<String> mdoIds,
    required String nuovaCommessa,
    String? nuovoCantiere,
    Map<String, String>? commesseById,
  }) =>
      applicaDislocazioneMezzi(
        mdoIds: mdoIds,
        nuovaCommessa: nuovaCommessa,
        nuovoCantiere: nuovoCantiere,
        commesseById: commesseById,
      );
}
