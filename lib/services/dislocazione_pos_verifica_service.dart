import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';

import '../utils/dislocazione_period_utils.dart';
import '../utils/excel_web_safe.dart';
import '../utils/personale_name_matcher.dart';
import 'logistica_box_linked_sync.dart';
import 'pos_commessa_dipendente_service.dart';
import 'supabase_service.dart';

/// Esito controllo: dipendente in dislocazione su commessa ma assente in lista POS.
class DislocazionePosVerificaMancante {
  const DislocazionePosVerificaMancante({
    required this.nominativo,
    required this.commessaId,
    required this.commessaNome,
    required this.motivo,
    this.personaleFullName,
    this.giorni = const [],
  });

  final String nominativo;
  final String commessaId;
  final String commessaNome;
  /// `non_in_pos` | `anagrafica_non_trovata` | `pos_vuota`
  final String motivo;
  final String? personaleFullName;
  final List<DateTime> giorni;
}

/// Mezzo assegnato a un dipendente su commessa ma assente in lista POS mezzi.
class DislocazionePosVerificaMezzoMancante {
  const DislocazionePosVerificaMezzoMancante({
    required this.mezzoId,
    required this.label,
    required this.assegnatario,
    required this.commessaId,
    required this.commessaNome,
    required this.motivo,
    this.targa = '',
    this.tipologia = '',
    this.giorni = const [],
  });

  final String mezzoId;
  final String label;
  final String assegnatario;
  final String commessaId;
  final String commessaNome;
  /// `non_in_pos` | `pos_vuota`
  final String motivo;
  final String targa;
  final String tipologia;
  final List<DateTime> giorni;
}

/// Esito verifica POS per un singolo MDO in trasferimento verso una commessa.
class DislocazionePosVerificaMdoTrasferimentoEsito {
  const DislocazionePosVerificaMdoTrasferimentoEsito({
    required this.mdoId,
    required this.mdoLabel,
    required this.commessaDestinazione,
    required this.esito,
    required this.messaggio,
    this.commessaId = '',
    this.posCount = 0,
  });

  final String mdoId;
  final String mdoLabel;
  final String commessaDestinazione;
  final String commessaId;
  /// `presente` | `non_in_pos` | `pos_vuota` | `commessa_non_risolta` | `errore`
  final String esito;
  final String messaggio;
  final int posCount;

  bool get ok => esito == 'presente';
}

/// MDO ferroviario in anagrafica su una commessa ma assente in lista POS QSA.
class DislocazionePosVerificaMdoMancante {
  const DislocazionePosVerificaMdoMancante({
    required this.mdoId,
    required this.label,
    required this.commessaId,
    required this.commessaNome,
    required this.motivo,
    this.matricola = '',
    this.targaRfi = '',
    this.cantiere = '',
  });

  final String mdoId;
  final String label;
  final String commessaId;
  final String commessaNome;
  /// `non_in_pos` | `pos_vuota` | `commessa_non_risolta`
  final String motivo;
  final String matricola;
  final String targaRfi;
  final String cantiere;
}

class DislocazionePosVerificaRisultato {
  const DislocazionePosVerificaRisultato({
    required this.mancanti,
    required this.commesseVerificate,
    this.mezziMancanti = const [],
    this.mdoMancanti = const [],
    this.periodoDal,
    this.periodoAl,
  });

  final List<DislocazionePosVerificaMancante> mancanti;
  final List<DislocazionePosVerificaMezzoMancante> mezziMancanti;
  final List<DislocazionePosVerificaMdoMancante> mdoMancanti;
  final List<String> commesseVerificate;
  final DateTime? periodoDal;
  final DateTime? periodoAl;

  bool get tuttoOk =>
      mancanti.isEmpty && mezziMancanti.isEmpty && mdoMancanti.isEmpty;
  int get anomalieTotali =>
      mancanti.length + mezziMancanti.length + mdoMancanti.length;
}

abstract final class DislocazionePosVerificaService {
  DislocazionePosVerificaService._();

  static String codiceCommessa(String nome) {
    final t = nome.trim();
    if (t.isEmpty) return '';
    final sp = t.indexOf(' ');
    if (sp > 0) return t.substring(0, sp);
    return t;
  }

  /// Tutti i dipendenti POS della commessa (unione TE, IS, TLC, FLM, ecc.).
  static Future<Map<String, Set<String>>> loadPosPersonaleIdsPerCommessa(
    Iterable<String> commessaIds,
  ) async {
    final ids = commessaIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final out = <String, Set<String>>{};
    for (var i = 0; i < ids.length; i += 80) {
      final end = i + 80 > ids.length ? ids.length : i + 80;
      final chunk = ids.sublist(i, end);
      final res = await SupabaseService.client
          .from('pos_commessa_dipendenti')
          .select('commessa_id, personale_id')
          .inFilter('commessa_id', chunk);

      for (final raw in res as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final cid = (m['commessa_id'] ?? '').toString().trim();
        final pid = (m['personale_id'] ?? '').toString().trim();
        if (cid.isEmpty || pid.isEmpty) continue;
        out.putIfAbsent(cid, () => <String>{}).add(pid);
      }
    }
    return out;
  }

  /// Mezzi POS stradali per commessa → set di `mezzo_id`.
  static Future<Map<String, Set<String>>> loadPosMezzoIdsPerCommessa(
    Iterable<String> commessaIds,
  ) async {
    final ids = commessaIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final out = <String, Set<String>>{};
    for (var i = 0; i < ids.length; i += 80) {
      final end = i + 80 > ids.length ? ids.length : i + 80;
      final chunk = ids.sublist(i, end);
      final res = await SupabaseService.client
          .from('pos_commessa_mezzi_stradali')
          .select('commessa_id, mezzo_id')
          .inFilter('commessa_id', chunk);

      for (final raw in res as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final cid = (m['commessa_id'] ?? '').toString().trim();
        final mid = (m['mezzo_id'] ?? '').toString().trim();
        if (cid.isEmpty || mid.isEmpty) continue;
        out.putIfAbsent(cid, () => <String>{}).add(mid);
      }
    }
    return out;
  }

  /// MDO ferroviari POS (QSA) per commessa → set di `mdo_id`.
  static Future<Map<String, Set<String>>> loadPosMdoIdsPerCommessa(
    Iterable<String> commessaIds,
  ) async {
    final ids = commessaIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final out = <String, Set<String>>{};
    for (var i = 0; i < ids.length; i += 80) {
      final end = i + 80 > ids.length ? ids.length : i + 80;
      final chunk = ids.sublist(i, end);
      final res = await SupabaseService.client
          .from('pos_commessa_mdo_ferroviari')
          .select('commessa_id, mdo_id')
          .inFilter('commessa_id', chunk);

      for (final raw in res as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final cid = (m['commessa_id'] ?? '').toString().trim();
        final mid = (m['mdo_id'] ?? '').toString().trim();
        if (cid.isEmpty || mid.isEmpty) continue;
        out.putIfAbsent(cid, () => <String>{}).add(mid);
      }
    }
    return out;
  }

  /// Mezzi attivi con assegnatario → abbinati ai nominativi in dislocazione.
  static Future<Map<String, List<_MezzoAssegnato>>> _loadMezziPerNominativo(
    Iterable<String> nominativi,
  ) async {
    final noms = nominativi
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (noms.isEmpty) return const {};

    final res = await SupabaseService.client
        .from('logistica_mezzi_stradali')
        .select(
          'id_uuid,targa,marca,modello,tipologia_mezzo,assegnatario_attuale,numerazione',
        )
        .eq('active', true);

    final byAssigneeNorm = <String, List<_MezzoAssegnato>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      final assegnatario = (m['assegnatario_attuale'] ?? '').toString().trim();
      if (id.isEmpty || assegnatario.isEmpty) continue;
      final k = PersonaleNameMatcher.normalize(assegnatario);
      if (k.isEmpty) continue;
      final targa = (m['targa'] ?? '').toString().trim();
      final marca = (m['marca'] ?? '').toString().trim();
      final modello = (m['modello'] ?? '').toString().trim();
      final tip = (m['tipologia_mezzo'] ?? '').toString().trim();
      final numRaw = m['numerazione'];
      final num = numRaw is int ? numRaw : int.tryParse('$numRaw');
      final labelParts = <String>[
        if (targa.isNotEmpty) targa,
        if (marca.isNotEmpty && modello.isNotEmpty)
          '$marca $modello'
        else if (modello.isNotEmpty)
          modello,
        if (num != null) '(N$num)',
      ];
      byAssigneeNorm.putIfAbsent(k, () => []).add(
            _MezzoAssegnato(
              id: id,
              label: labelParts.isEmpty ? id : labelParts.join(' · '),
              targa: targa,
              tipologia: tip,
              assegnatarioAnagrafica: assegnatario,
            ),
          );
    }

    final out = <String, List<_MezzoAssegnato>>{};
    for (final nom in noms) {
      final k = PersonaleNameMatcher.normalize(nom);
      final found = <_MezzoAssegnato>[];
      final seen = <String>{};

      void addAll(Iterable<_MezzoAssegnato> list) {
        for (final m in list) {
          if (seen.add(m.id)) found.add(m);
        }
      }

      addAll(byAssigneeNorm[k] ?? const []);
      if (found.isEmpty) {
        final tokP = PersonaleNameMatcher.tokens(nom).toSet();
        if (tokP.isNotEmpty) {
          for (final e in byAssigneeNorm.entries) {
            final tokA = PersonaleNameMatcher.tokens(e.key).toSet();
            if (tokA.isEmpty) continue;
            if (tokP.length == tokA.length && tokP.containsAll(tokA)) {
              addAll(e.value);
            }
          }
        }
      }
      if (found.isNotEmpty) out[nom] = found;
    }
    return out;
  }

  static Future<DislocazionePosVerificaRisultato> verificaNelPeriodo({
    required Map<String, Map<DateTime, DislocazioneGiornoValore>> cacheGiorni,
    required List<DateTime> giorniFinestra,
    required Map<String, String> commesse,
  }) async {
    final giorniSet = giorniFinestra.map(dateOnly).toSet();
    if (giorniSet.isEmpty) {
      return const DislocazionePosVerificaRisultato(
        mancanti: [],
        mezziMancanti: [],
        mdoMancanti: [],
        commesseVerificate: [],
      );
    }

    final personaleById = await PosCommessaDipendenteService.loadPersonaleAttivo();

    // commessaId -> nominativo -> giorni
    final assegnazioni = <String, Map<String, Set<DateTime>>>{};
    final commesseIds = <String>{};
    final nominativiSuCommessa = <String>{};

    for (final entry in cacheGiorni.entries) {
      final nominativo = entry.key;
      for (final g in entry.value.entries) {
        final d = dateOnly(g.key);
        if (!giorniSet.contains(d)) continue;
        final val = g.value;
        final cid = (val.commessaId ?? '').trim();
        if (cid.isEmpty || val.isEmpty) continue;
        commesseIds.add(cid);
        nominativiSuCommessa.add(nominativo);
        assegnazioni
            .putIfAbsent(cid, () => <String, Set<DateTime>>{})
            .putIfAbsent(nominativo, () => <DateTime>{})
            .add(d);
      }
    }

    final mancanti = <DislocazionePosVerificaMancante>[];
    final mezziMancanti = <DislocazionePosVerificaMezzoMancante>[];
    final mezziAcc = <String, DislocazionePosVerificaMezzoMancante>{};

    if (commesseIds.isNotEmpty) {
      final posByCommessa = await loadPosPersonaleIdsPerCommessa(commesseIds);
      final posMezziByCommessa = await loadPosMezzoIdsPerCommessa(commesseIds);
      final mezziPerNom = await _loadMezziPerNominativo(nominativiSuCommessa);

    for (final cid in commesseIds) {
      final nomeCommessa = commesse[cid] ?? cid;
      final posSet = posByCommessa[cid] ?? <String>{};
        final posMezzi = posMezziByCommessa[cid] ?? <String>{};
      final perNom = assegnazioni[cid] ?? {};

      for (final entry in perNom.entries) {
        final nominativo = entry.key;
        final giorni = entry.value.toList()..sort();

        if (posSet.isEmpty) {
          mancanti.add(
            DislocazionePosVerificaMancante(
              nominativo: nominativo,
              commessaId: cid,
              commessaNome: nomeCommessa,
              motivo: 'pos_vuota',
              giorni: giorni,
            ),
          );
          } else {
            final pid =
                PersonaleNameMatcher.findPersonaleIdByNominativoDislocazione(
          nominativo,
          personaleById,
        );
        if (pid == null) {
          mancanti.add(
            DislocazionePosVerificaMancante(
              nominativo: nominativo,
              commessaId: cid,
              commessaNome: nomeCommessa,
              motivo: 'anagrafica_non_trovata',
              giorni: giorni,
            ),
          );
            } else if (!posSet.contains(pid)) {
          mancanti.add(
            DislocazionePosVerificaMancante(
              nominativo: nominativo,
              commessaId: cid,
              commessaNome: nomeCommessa,
              motivo: 'non_in_pos',
              personaleFullName: personaleById[pid],
              giorni: giorni,
            ),
          );
            }
          }

          final mezzi = mezziPerNom[nominativo] ?? const <_MezzoAssegnato>[];
          for (final mezzo in mezzi) {
            final key = '$cid|${mezzo.id}';
            String? motivo;
            if (posMezzi.isEmpty) {
              motivo = 'pos_vuota';
            } else if (!posMezzi.contains(mezzo.id)) {
              motivo = 'non_in_pos';
            }
            if (motivo == null) continue;

            final prev = mezziAcc[key];
            if (prev == null) {
              mezziAcc[key] = DislocazionePosVerificaMezzoMancante(
                mezzoId: mezzo.id,
                label: mezzo.label,
                assegnatario: nominativo,
                commessaId: cid,
                commessaNome: nomeCommessa,
                motivo: motivo,
                targa: mezzo.targa,
                tipologia: mezzo.tipologia,
                giorni: List<DateTime>.from(giorni),
              );
            } else {
              final merged = {...prev.giorni, ...giorni}.toList()..sort();
              mezziAcc[key] = DislocazionePosVerificaMezzoMancante(
                mezzoId: prev.mezzoId,
                label: prev.label,
                assegnatario: prev.assegnatario,
                commessaId: prev.commessaId,
                commessaNome: prev.commessaNome,
                motivo: prev.motivo,
                targa: prev.targa,
                tipologia: prev.tipologia,
                giorni: merged,
              );
            }
          }
        }
      }
    }

    mezziMancanti.addAll(mezziAcc.values);

    final mdoEsito = await _verificaMdoFerroviariPos(commesse: commesse);
    final allCommessaIds = <String>{
      ...commesseIds,
      ...mdoEsito.commessaIds,
    };

    mancanti.sort((a, b) {
      final c = a.commessaNome.toLowerCase().compareTo(b.commessaNome.toLowerCase());
      if (c != 0) return c;
      return a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase());
    });
    mezziMancanti.sort((a, b) {
      final c = a.commessaNome.toLowerCase().compareTo(b.commessaNome.toLowerCase());
      if (c != 0) return c;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    final nomiCommesse = allCommessaIds.map((id) => commesse[id] ?? id).toList()
      ..sort();
    // Aggiungi eventuali label di MDO non risolte.
    for (final m in mdoEsito.mancanti) {
      if (m.motivo == 'commessa_non_risolta' &&
          !nomiCommesse.any((n) => n.toLowerCase() == m.commessaNome.toLowerCase())) {
        nomiCommesse.add(m.commessaNome);
      }
    }
    nomiCommesse.sort();

    return DislocazionePosVerificaRisultato(
      mancanti: mancanti,
      mezziMancanti: mezziMancanti,
      mdoMancanti: mdoEsito.mancanti,
      commesseVerificate: nomiCommesse,
      periodoDal: _minDate(giorniSet),
      periodoAl: _maxDate(giorniSet),
    );
  }

  /// Confronta MDO in anagrafica (campo `commessa`) con liste POS QSA.
  static Future<({List<DislocazionePosVerificaMdoMancante> mancanti, Set<String> commessaIds})>
      _verificaMdoFerroviariPos({
    required Map<String, String> commesse,
  }) async {
    final res = await SupabaseService.client
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid,matricola_interna,codice_identificativo_targa_rfi,'
          'descrizione_mezzo,commessa,cantiere_attuale',
        )
        .eq('active', true);

    final mancanti = <DislocazionePosVerificaMdoMancante>[];
    final byCommessa = <String, List<Map<String, dynamic>>>{};
    final unresolved = <Map<String, dynamic>>[];

    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      final commessaTxt = (m['commessa'] ?? '').toString().trim();
      if (id.isEmpty || commessaTxt.isEmpty) continue;

      final cid = findCommessaIdByText(commessaTxt, commesse);
      if (cid == null || cid.isEmpty) {
        unresolved.add(m);
        continue;
      }
      byCommessa.putIfAbsent(cid, () => []).add(m);
    }

    for (final m in unresolved) {
      final id = (m['id_uuid'] ?? '').toString().trim();
      final mat = (m['matricola_interna'] ?? '').toString().trim();
      final targa = (m['codice_identificativo_targa_rfi'] ?? '').toString().trim();
      final desc = (m['descrizione_mezzo'] ?? '').toString().trim();
      final commessaTxt = (m['commessa'] ?? '').toString().trim();
      final cantiere = (m['cantiere_attuale'] ?? '').toString().trim();
      mancanti.add(
        DislocazionePosVerificaMdoMancante(
          mdoId: id,
          label: _mdoLabel(mat, desc, targa),
          commessaId: '',
          commessaNome: commessaTxt,
          motivo: 'commessa_non_risolta',
          matricola: mat,
          targaRfi: targa,
          cantiere: cantiere,
        ),
      );
    }

    final ids = byCommessa.keys.toSet();
    final posMdo = await loadPosMdoIdsPerCommessa(ids);

    for (final e in byCommessa.entries) {
      final cid = e.key;
      final nomeCommessa = commesse[cid] ?? cid;
      final posSet = posMdo[cid] ?? <String>{};
      for (final m in e.value) {
        final id = (m['id_uuid'] ?? '').toString().trim();
        final mat = (m['matricola_interna'] ?? '').toString().trim();
        final targa = (m['codice_identificativo_targa_rfi'] ?? '').toString().trim();
        final desc = (m['descrizione_mezzo'] ?? '').toString().trim();
        final cantiere = (m['cantiere_attuale'] ?? '').toString().trim();
        String? motivo;
        if (posSet.isEmpty) {
          motivo = 'pos_vuota';
        } else if (!posSet.contains(id)) {
          motivo = 'non_in_pos';
        }
        if (motivo == null) continue;
        mancanti.add(
          DislocazionePosVerificaMdoMancante(
            mdoId: id,
            label: _mdoLabel(mat, desc, targa),
            commessaId: cid,
            commessaNome: nomeCommessa,
            motivo: motivo,
            matricola: mat,
            targaRfi: targa,
            cantiere: cantiere,
          ),
        );
      }
    }

    mancanti.sort((a, b) {
      final c = a.commessaNome.toLowerCase().compareTo(b.commessaNome.toLowerCase());
      if (c != 0) return c;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return (mancanti: mancanti, commessaIds: ids);
  }

  static String _mdoLabel(String matricola, String descrizione, String targa) {
    final parts = <String>[
      if (matricola.isNotEmpty) matricola,
      if (descrizione.isNotEmpty) descrizione,
      if (targa.isNotEmpty) 'Targa $targa',
    ];
    return parts.isEmpty ? 'MDO' : parts.join(' · ');
  }

  static DateTime? _minDate(Set<DateTime> days) {
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  static DateTime? _maxDate(Set<DateTime> days) {
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  static String motivoLabel(String motivo) => switch (motivo) {
        'pos_vuota' => 'Lista POS vuota per questa commessa',
        'anagrafica_non_trovata' => 'Non trovato in anagrafica personale',
        'non_in_pos' => 'Non presente in lista POS',
        _ => motivo,
      };

  static String motivoMezzoLabel(String motivo) => switch (motivo) {
        'pos_vuota' => 'Lista POS mezzi vuota per questa commessa',
        'non_in_pos' => 'Mezzo non presente in lista POS mezzi stradali',
        _ => motivo,
      };

  static String motivoMdoLabel(String motivo) => switch (motivo) {
        'pos_vuota' => 'Lista POS MDO ferroviari vuota per questa commessa',
        'non_in_pos' => 'MDO non presente in lista POS Elenco MdO Ferroviari (QSA)',
        'commessa_non_risolta' =>
          'Commessa in anagrafica MDO non abbinata alle commesse attive',
        _ => motivo,
      };

  /// Verifica se un MDO in trasferimento è già in lista POS della commessa destinazione.
  static Future<DislocazionePosVerificaMdoTrasferimentoEsito>
      verificaMdoSuPosCommessaDestinazione({
    required String mdoId,
    required String mdoLabel,
    required String commessaDestinazione,
    required Map<String, String> commesseById,
  }) async {
    final mid = mdoId.trim();
    final destTxt = commessaDestinazione.trim();
    if (mid.isEmpty) {
      return DislocazionePosVerificaMdoTrasferimentoEsito(
        mdoId: mid,
        mdoLabel: mdoLabel,
        commessaDestinazione: destTxt,
        esito: 'errore',
        messaggio: 'Mezzo non identificato.',
      );
    }
    if (destTxt.isEmpty) {
      return DislocazionePosVerificaMdoTrasferimentoEsito(
        mdoId: mid,
        mdoLabel: mdoLabel,
        commessaDestinazione: destTxt,
        esito: 'errore',
        messaggio: 'Commessa destinazione mancante.',
      );
    }

    final cid = findCommessaIdByText(destTxt, commesseById);
    if (cid == null || cid.isEmpty) {
      return DislocazionePosVerificaMdoTrasferimentoEsito(
        mdoId: mid,
        mdoLabel: mdoLabel,
        commessaDestinazione: destTxt,
        esito: 'commessa_non_risolta',
        messaggio:
            'Commessa destinazione «$destTxt» non abbinata alle commesse attive.',
      );
    }

    final nome = (commesseById[cid] ?? destTxt).trim();
    final posMap = await loadPosMdoIdsPerCommessa([cid]);
    final posSet = posMap[cid] ?? <String>{};

    if (posSet.isEmpty) {
      return DislocazionePosVerificaMdoTrasferimentoEsito(
        mdoId: mid,
        mdoLabel: mdoLabel,
        commessaId: cid,
        commessaDestinazione: nome,
        esito: 'pos_vuota',
        messaggio:
            'Lista POS MdO Ferroviari (QSA) vuota per «$nome». '
            'Il mezzo non risulta coperto.',
      );
    }

    if (posSet.contains(mid)) {
      return DislocazionePosVerificaMdoTrasferimentoEsito(
        mdoId: mid,
        mdoLabel: mdoLabel,
        commessaId: cid,
        commessaDestinazione: nome,
        esito: 'presente',
        messaggio:
            '«$mdoLabel» è presente nella lista POS di «$nome».',
        posCount: posSet.length,
      );
    }

    return DislocazionePosVerificaMdoTrasferimentoEsito(
      mdoId: mid,
      mdoLabel: mdoLabel,
      commessaId: cid,
      commessaDestinazione: nome,
      esito: 'non_in_pos',
      messaggio:
          '«$mdoLabel» NON è nella lista POS di «$nome» '
          '(${posSet.length} mezzi in lista).',
      posCount: posSet.length,
    );
  }

  /// Verifica in blocco tutti i MDO in trasferimento vs lista POS della destinazione.
  static Future<List<DislocazionePosVerificaMdoTrasferimentoEsito>>
      verificaTrasferimentiSuPosCommessaDestinazione({
    required List<({String mdoId, String mdoLabel, String commessaDestinazione})>
        trasferimenti,
    required Map<String, String> commesseById,
  }) async {
    if (trasferimenti.isEmpty) return const [];

    final destToCid = <String, String?>{};
    final cidSet = <String>{};
    for (final t in trasferimenti) {
      final dest = t.commessaDestinazione.trim();
      if (dest.isEmpty) {
        destToCid[dest] = null;
        continue;
      }
      if (!destToCid.containsKey(dest)) {
        final cid = findCommessaIdByText(dest, commesseById);
        destToCid[dest] = (cid != null && cid.isNotEmpty) ? cid : null;
        if (cid != null && cid.isNotEmpty) cidSet.add(cid);
      }
    }

    final posMap = await loadPosMdoIdsPerCommessa(cidSet);
    final out = <DislocazionePosVerificaMdoTrasferimentoEsito>[];

    for (final t in trasferimenti) {
      final mid = t.mdoId.trim();
      final label = t.mdoLabel.trim();
      final destTxt = t.commessaDestinazione.trim();

      if (mid.isEmpty) {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaDestinazione: destTxt,
            esito: 'errore',
            messaggio: 'Mezzo non identificato.',
          ),
        );
        continue;
      }
      if (destTxt.isEmpty) {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaDestinazione: destTxt,
            esito: 'errore',
            messaggio: 'Commessa destinazione mancante.',
          ),
        );
        continue;
      }

      final cid = destToCid[destTxt];
      if (cid == null || cid.isEmpty) {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaDestinazione: destTxt,
            esito: 'commessa_non_risolta',
            messaggio:
                'Commessa destinazione «$destTxt» non abbinata alle commesse attive.',
          ),
        );
        continue;
      }

      final nome = (commesseById[cid] ?? destTxt).trim();
      final posSet = posMap[cid] ?? <String>{};

      if (posSet.isEmpty) {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaId: cid,
            commessaDestinazione: nome,
            esito: 'pos_vuota',
            messaggio:
                'Lista POS MdO Ferroviari (QSA) vuota per «$nome».',
          ),
        );
        continue;
      }

      if (posSet.contains(mid)) {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaId: cid,
            commessaDestinazione: nome,
            esito: 'presente',
            messaggio: 'Presente in lista POS.',
            posCount: posSet.length,
          ),
        );
      } else {
        out.add(
          DislocazionePosVerificaMdoTrasferimentoEsito(
            mdoId: mid,
            mdoLabel: label,
            commessaId: cid,
            commessaDestinazione: nome,
            esito: 'non_in_pos',
            messaggio:
                'NON in lista POS (${posSet.length} mezzi in lista).',
            posCount: posSet.length,
          ),
        );
      }
    }

    return out;
  }

  /// Export anomalie verifica POS (dipendenti + mezzi).
  static Uint8List buildExcelBytes(
    DislocazionePosVerificaRisultato risultato, {
    DateFormat? dateFmt,
  }) {
    final df = dateFmt ?? DateFormat('dd/MM/yyyy');
    final excel = Excel.createExcel();
    final sheet = excelUseDefaultSheet(excel);

    final periodo = (risultato.periodoDal != null && risultato.periodoAl != null)
        ? '${df.format(risultato.periodoDal!)} – ${df.format(risultato.periodoAl!)}'
        : '';

    sheet.appendRow(['Verifica POS — dipendenti, mezzi stradali e MDO ferroviari']);
    sheet.appendRow(['Periodo', periodo]);
    sheet.appendRow([
      'Commesse controllate',
      risultato.commesseVerificate.length.toString(),
    ]);
    sheet.appendRow(['Anomalie dipendenti', risultato.mancanti.length.toString()]);
    sheet.appendRow([
      'Anomalie mezzi stradali',
      risultato.mezziMancanti.length.toString(),
    ]);
    sheet.appendRow([
      'Anomalie MDO ferroviari',
      risultato.mdoMancanti.length.toString(),
    ]);
    sheet.appendRow([]);

    sheet.appendRow(['— DIPENDENTI —']);
    sheet.appendRow([
      'Commessa',
      'Commessa (nome completo)',
      'Nominativo dislocazione',
      'Anagrafica',
      'Motivo',
      'Dal',
      'Al',
      'N. giorni',
      'Giorni (dettaglio)',
    ]);

    if (risultato.mancanti.isEmpty) {
      sheet.appendRow([
        risultato.commesseVerificate.isEmpty
            ? 'Nessuna assegnazione a commessa nel periodo'
            : 'Nessuna anomalia dipendenti',
      ]);
    } else {
      for (final m in risultato.mancanti) {
        final giorni = m.giorni.map(dateOnly).toList()..sort();
        final dal = giorni.isEmpty ? '' : df.format(giorni.first);
        final al = giorni.isEmpty ? '' : df.format(giorni.last);
        final dettaglio = giorni.length <= 31
            ? giorni.map(df.format).join(', ')
            : '$dal … $al';
        sheet.appendRow([
          codiceCommessa(m.commessaNome),
          m.commessaNome,
          m.nominativo,
          m.personaleFullName ?? '',
          motivoLabel(m.motivo),
          dal,
          al,
          giorni.length.toString(),
          dettaglio,
        ]);
      }
    }

    sheet.appendRow([]);
    sheet.appendRow(['— MEZZI STRADALI —']);
    sheet.appendRow([
      'Commessa',
      'Commessa (nome completo)',
      'Mezzo',
      'Targa',
      'Tipologia',
      'Assegnatario (dislocazione)',
      'Motivo',
      'Dal',
      'Al',
      'N. giorni',
      'Giorni (dettaglio)',
    ]);

    if (risultato.mezziMancanti.isEmpty) {
      sheet.appendRow([
        risultato.commesseVerificate.isEmpty
            ? 'Nessuna assegnazione a commessa nel periodo'
            : 'Nessuna anomalia mezzi',
      ]);
    } else {
      for (final m in risultato.mezziMancanti) {
        final giorni = m.giorni.map(dateOnly).toList()..sort();
        final dal = giorni.isEmpty ? '' : df.format(giorni.first);
        final al = giorni.isEmpty ? '' : df.format(giorni.last);
        final dettaglio = giorni.length <= 31
            ? giorni.map(df.format).join(', ')
            : '$dal … $al';
        sheet.appendRow([
          codiceCommessa(m.commessaNome),
          m.commessaNome,
          m.label,
          m.targa,
          m.tipologia,
          m.assegnatario,
          motivoMezzoLabel(m.motivo),
          dal,
          al,
          giorni.length.toString(),
          dettaglio,
        ]);
      }
    }

    sheet.appendRow([]);
    sheet.appendRow(['— MDO FERROVIARI (QSA) —']);
    sheet.appendRow([
      'Commessa',
      'Commessa (nome completo)',
      'MDO',
      'Matricola',
      'Targa RFI',
      'Cantiere',
      'Motivo',
    ]);

    if (risultato.mdoMancanti.isEmpty) {
      sheet.appendRow(['Nessuna anomalia MDO ferroviari']);
    } else {
      for (final m in risultato.mdoMancanti) {
        sheet.appendRow([
          codiceCommessa(m.commessaNome),
          m.commessaNome,
          m.label,
          m.matricola,
          m.targaRfi,
          m.cantiere,
          motivoMdoLabel(m.motivo),
        ]);
      }
    }

  return Uint8List.fromList(excel.encode()!);
  }
}

class _MezzoAssegnato {
  const _MezzoAssegnato({
    required this.id,
    required this.label,
    required this.targa,
    required this.tipologia,
    required this.assegnatarioAnagrafica,
  });

  final String id;
  final String label;
  final String targa;
  final String tipologia;
  final String assegnatarioAnagrafica;
}
