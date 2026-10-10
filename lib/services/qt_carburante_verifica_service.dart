import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'qt_carburante_fatturazione_parser.dart';
import 'qt_multicard_storico_assignee.dart';

enum QtCarburanteStatoVerifica {
  giustificato,
  mancante,
}

enum QtCarburanteFonteGiustificativo {
  rccStradali,
  rccMdo,
}

class QtCarburanteVerificaRow {
  final QtCarburanteTrxRow transazione;
  final QtCarburanteStatoVerifica stato;
  final QtCarburanteFonteGiustificativo? fonte;
  final String? rccIdUuid;
  final String? nota;
  final String? assegnatario;
  final String? assegnatarioAttuale;
  final bool responsabileDaStorico;
  final String? rccCommessa;
  final String? rccNomeCognome;

  const QtCarburanteVerificaRow({
    required this.transazione,
    required this.stato,
    this.fonte,
    this.rccIdUuid,
    this.nota,
    this.assegnatario,
    this.assegnatarioAttuale,
    this.responsabileDaStorico = false,
    this.rccCommessa,
    this.rccNomeCognome,
  });
}

class QtCarburanteSchedaRiepilogo {
  final String numeroCarta;
  final String? assegnatario;
  final String? assegnatarioAttuale;
  final bool responsabileDaStorico;
  final String? commessa;
  final int totale;
  final int giustificati;
  final int mancanti;
  final double importoTotale;
  final double importoGiustificato;
  final double importoMancante;

  const QtCarburanteSchedaRiepilogo({
    required this.numeroCarta,
    this.assegnatario,
    this.assegnatarioAttuale,
    this.responsabileDaStorico = false,
    this.commessa,
    required this.totale,
    required this.giustificati,
    required this.mancanti,
    required this.importoTotale,
    required this.importoGiustificato,
    required this.importoMancante,
  });
}

class QtCarburanteVerificaResult {
  final List<QtCarburanteVerificaRow> righe;
  final List<QtCarburanteSchedaRiepilogo> perScheda;
  final List<QtCarburanteRccSenzaFatturaRow> giustificativiSenzaFattura;
  final List<QtCarburantePossibileErroreBattitura> possibiliErroriBattitura;
  final DateTime dataMin;
  final DateTime dataMax;

  const QtCarburanteVerificaResult({
    required this.righe,
    required this.perScheda,
    required this.giustificativiSenzaFattura,
    required this.possibiliErroriBattitura,
    required this.dataMin,
    required this.dataMax,
  });

  int get totale => righe.length;
  int get giustificati =>
      righe.where((r) => r.stato == QtCarburanteStatoVerifica.giustificato).length;
  int get mancanti => totale - giustificati;
  int get senzaFattura => giustificativiSenzaFattura.length;
  int get possibiliErrori => possibiliErroriBattitura.length;
}

class QtCarburanteRccSenzaFatturaRow {
  final QtCarburanteFonteGiustificativo fonte;
  final String idUuid;
  final String numeroCarta;
  final DateTime dataRifornimento;
  final double? litri;
  final double? euro;
  final String? tipoCarburante;
  final String? nomeCognome;
  final String? cantiere;

  const QtCarburanteRccSenzaFatturaRow({
    required this.fonte,
    required this.idUuid,
    required this.numeroCarta,
    required this.dataRifornimento,
    this.litri,
    this.euro,
    this.tipoCarburante,
    this.nomeCognome,
    this.cantiere,
  });
}

/// Abbinamento probabile tra giustificativo RCC e transazione QT con differenze
/// su data, litri o importo (possibile errore di battitura).
class QtCarburantePossibileErroreBattitura {
  const QtCarburantePossibileErroreBattitura({
    required this.rcc,
    required this.transazione,
    required this.punteggio,
    required this.differenze,
  });

  final QtCarburanteRccSenzaFatturaRow rcc;
  final QtCarburanteTrxRow transazione;
  final int punteggio;
  final List<String> differenze;
}

abstract final class QtCarburanteVerificaService {
  QtCarburanteVerificaService._();

  static const _maxDateSkewDays = 2;
  static const _maxNearDateSkewDays = 7;
  static const _tolLitriPct = 0.03;
  static const _tolEuroPct = 0.03;
  static const _tolLitriMin = 0.5;
  static const _tolEuroMin = 1.0;
  static const _nearTolLitriPct = 0.15;
  static const _nearTolEuroPct = 0.15;
  static const _nearTolLitriMin = 8.0;
  static const _nearTolEuroMin = 15.0;
  static const _minNearMatchScore = 45;

  @visibleForTesting
  static bool volumeMatchForTest(double qt, double? rcc) => _volumeMatch(qt, rcc);

  @visibleForTesting
  static bool euroMatchForTest(double qt, double? rcc) => _euroMatch(qt, rcc);

  @visibleForTesting
  static int dateSkewDaysForTest(String qtIso, String rccIso) =>
      _dateSkewDays(qtIso, rccIso);

  @visibleForTesting
  static String isoDayFromDbForTest(dynamic raw) => _isoDayFromDb(raw);

  @visibleForTesting
  static bool prodottiCompatibiliForTest(String qt, String rcc) =>
      _prodottiCompatibili(qt, rcc);

  static Future<QtCarburanteVerificaResult> verifica({
    required SupabaseClient supa,
    required List<QtCarburanteTrxRow> transazioni,
    int? riferimentoAnno,
    int? riferimentoMese,
  }) async {
    if (transazioni.isEmpty) {
      throw ArgumentError('Nessuna transazione da verificare.');
    }

    var dataMin = transazioni.first.dataTransazione;
    var dataMax = transazioni.first.dataTransazione;
    for (final t in transazioni) {
      if (t.dataTransazione.isBefore(dataMin)) dataMin = t.dataTransazione;
      if (t.dataTransazione.isAfter(dataMax)) dataMax = t.dataTransazione;
    }

    final isoStart = _isoDay(
      dataMin.subtract(const Duration(days: _maxDateSkewDays)),
    );
    final isoEnd = _isoDay(
      dataMax.add(const Duration(days: _maxDateSkewDays)),
    );

    var multicardProfiles = await QtMulticardStoricoAssigneeLoader.load(supa);
    final mezziByTarga = await _loadMezziAssignees(supa);
    multicardProfiles = [
      for (final m in multicardProfiles)
        if ((m.assegnatarioAttuale ?? '').trim().isEmpty && m.targa != null)
          m.withAssigneeFallback(
            mezziByTarga[m.targa!.toLowerCase()] ?? '',
          )
        else
          m,
    ];

    final stradali = await _loadStradali(supa, isoStart: isoStart, isoEnd: isoEnd);
    final mdo = await _loadMdo(supa, isoStart: isoStart, isoEnd: isoEnd);

    final pool = [...mdo, ...stradali];
    final used = <String>{};

    final verifiche = <QtCarburanteVerificaRow>[];
    for (final trx in transazioni) {
      final assignee = _resolveAssigneeAtDate(
        cartaNorm: trx.cartaNorm,
        data: trx.dataTransazione,
        profiles: multicardProfiles,
      );
      final match = _findMatch(
        trx: trx,
        pool: pool,
        used: used,
      );
      if (match != null) {
        used.add(match.usedKey);
        verifiche.add(
          QtCarburanteVerificaRow(
            transazione: trx,
            stato: QtCarburanteStatoVerifica.giustificato,
            fonte: match.fonte,
            rccIdUuid: match.idUuid,
            assegnatario: assignee.responsabile,
            assegnatarioAttuale: assignee.assegnatarioAttuale,
            responsabileDaStorico: assignee.daStorico,
            rccCommessa: match.cantiere,
            rccNomeCognome: match.nomeCognome,
          ),
        );
        continue;
      }

      verifiche.add(
        QtCarburanteVerificaRow(
          transazione: trx,
          stato: QtCarburanteStatoVerifica.mancante,
          nota: 'Nessun rifornimento corrispondente (RCC MDO o Stradali)',
          assegnatario: assignee.responsabile,
          assegnatarioAttuale: assignee.assegnatarioAttuale,
          responsabileDaStorico: assignee.daStorico,
        ),
      );
    }
    final perScheda = _buildSchedaSummary(verifiche, multicardProfiles);
    final senzaFattura = _buildGiustificativiSenzaFattura(
      pool: pool,
      used: used,
      riferimentoAnno: riferimentoAnno,
      riferimentoMese: riferimentoMese,
    );
    final possibiliErrori = _buildPossibiliErroriBattitura(
      verifiche: verifiche,
      senzaFattura: senzaFattura,
    );
    return QtCarburanteVerificaResult(
      righe: verifiche,
      perScheda: perScheda,
      giustificativiSenzaFattura: senzaFattura,
      possibiliErroriBattitura: possibiliErrori,
      dataMin: dataMin,
      dataMax: dataMax,
    );
  }

  /// Verifica locale con pool RCC già caricati (RPC dipendente, bypass RLS QT).
  static QtCarburanteVerificaResult verificaWithLocalPools({
    required List<QtCarburanteTrxRow> transazioni,
    required List<Map<String, dynamic>> rccStradali,
    required List<Map<String, dynamic>> rccMdo,
    Map<String, String>? responsabiliByKey,
    int? riferimentoAnno,
    int? riferimentoMese,
  }) {
    if (transazioni.isEmpty) {
      throw ArgumentError('Nessuna transazione da verificare.');
    }

    var dataMin = transazioni.first.dataTransazione;
    var dataMax = transazioni.first.dataTransazione;
    for (final t in transazioni) {
      if (t.dataTransazione.isBefore(dataMin)) dataMin = t.dataTransazione;
      if (t.dataTransazione.isAfter(dataMax)) dataMax = t.dataTransazione;
    }

    final pool = <_RccPoolRow>[
      for (final e in rccMdo)
        _RccPoolRow.fromMap(
          e,
          fonte: QtCarburanteFonteGiustificativo.rccMdo,
        ),
      for (final e in rccStradali)
        _RccPoolRow.fromMap(
          e,
          fonte: QtCarburanteFonteGiustificativo.rccStradali,
        ),
    ];
    final used = <String>{};
    final resp = responsabiliByKey ?? const <String, String>{};

    final verifiche = <QtCarburanteVerificaRow>[];
    for (final trx in transazioni) {
      final key = QtCarburanteFatturazioneParser.dedupeKey(trx);
      final responsabile = resp[key];
      final match = _findMatch(trx: trx, pool: pool, used: used);
      if (match != null) {
        used.add(match.usedKey);
        verifiche.add(
          QtCarburanteVerificaRow(
            transazione: trx,
            stato: QtCarburanteStatoVerifica.giustificato,
            fonte: match.fonte,
            rccIdUuid: match.idUuid,
            assegnatario: responsabile,
            rccCommessa: match.cantiere,
            rccNomeCognome: match.nomeCognome,
          ),
        );
        continue;
      }
      verifiche.add(
        QtCarburanteVerificaRow(
          transazione: trx,
          stato: QtCarburanteStatoVerifica.mancante,
          nota: 'Nessun rifornimento corrispondente (RCC MDO o Stradali)',
          assegnatario: responsabile,
        ),
      );
    }

    final perScheda = _buildSchedaSummary(verifiche, const []);
    final senzaFattura = _buildGiustificativiSenzaFattura(
      pool: pool,
      used: used,
      riferimentoAnno: riferimentoAnno,
      riferimentoMese: riferimentoMese,
    );
    final possibiliErrori = _buildPossibiliErroriBattitura(
      verifiche: verifiche,
      senzaFattura: senzaFattura,
    );
    return QtCarburanteVerificaResult(
      righe: verifiche,
      perScheda: perScheda,
      giustificativiSenzaFattura: senzaFattura,
      possibiliErroriBattitura: possibiliErrori,
      dataMin: dataMin,
      dataMax: dataMax,
    );
  }

  static List<QtCarburantePossibileErroreBattitura> _buildPossibiliErroriBattitura({
    required List<QtCarburanteVerificaRow> verifiche,
    required List<QtCarburanteRccSenzaFatturaRow> senzaFattura,
  }) {
    final qtMancanti = verifiche
        .where((r) => r.stato == QtCarburanteStatoVerifica.mancante)
        .map((r) => r.transazione)
        .toList(growable: false);
    if (qtMancanti.isEmpty || senzaFattura.isEmpty) return const [];

    final candidati = <_NearMatchCandidate>[];
    for (final rcc in senzaFattura) {
      for (final qt in qtMancanti) {
        final differenze = <String>[];
        final score = _nearMatchScore(rcc: rcc, qt: qt, differenze: differenze);
        if (score == null || score < _minNearMatchScore) continue;
        candidati.add(
          _NearMatchCandidate(
            rcc: rcc,
            qt: qt,
            score: score,
            differenze: differenze,
          ),
        );
      }
    }

    candidati.sort((a, b) => b.score.compareTo(a.score));
    final usedRcc = <String>{};
    final usedQt = <String>{};
    final out = <QtCarburantePossibileErroreBattitura>[];

    for (final c in candidati) {
      final rccKey = '${c.rcc.fonte.name}:${c.rcc.idUuid}';
      final qtKey = QtCarburanteFatturazioneParser.dedupeKey(c.qt);
      if (usedRcc.contains(rccKey) || usedQt.contains(qtKey)) continue;
      usedRcc.add(rccKey);
      usedQt.add(qtKey);
      out.add(
        QtCarburantePossibileErroreBattitura(
          rcc: c.rcc,
          transazione: c.qt,
          punteggio: c.score,
          differenze: c.differenze,
        ),
      );
    }

    out.sort((a, b) {
      final d = a.rcc.dataRifornimento.compareTo(b.rcc.dataRifornimento);
      if (d != 0) return d;
      return b.punteggio.compareTo(a.punteggio);
    });
    return out;
  }

  @visibleForTesting
  static int? nearMatchScoreForTest({
    required QtCarburanteRccSenzaFatturaRow rcc,
    required QtCarburanteTrxRow qt,
    List<String>? differenze,
  }) =>
      _nearMatchScore(
        rcc: rcc,
        qt: qt,
        differenze: differenze ?? <String>[],
      );

  static int? _nearMatchScore({
    required QtCarburanteRccSenzaFatturaRow rcc,
    required QtCarburanteTrxRow qt,
    required List<String> differenze,
  }) {
    differenze.clear();
    if (!_carteMatch(qt.cartaNorm, rcc.numeroCarta)) return null;

    final poolRow = _rccPoolFromSenzaFattura(rcc);
    final daySkew = _dateSkewDays(qt.isoData, poolRow.isoData);
    if (daySkew > _maxNearDateSkewDays) return null;

    final litriStrict = _quantitaMatch(trx: qt, row: poolRow);
    final euroStrict = _euroMatch(qt.importo, rcc.euro);
    final litriNear = _nearVolumeMatch(qt.volume, rcc.litri);
    final euroNear = _nearEuroMatch(qt.importo, rcc.euro);
    final prodottoOk = rcc.tipoCarburante == null ||
        rcc.tipoCarburante!.trim().isEmpty ||
        _prodottiCompatibili(qt.prodotto, rcc.tipoCarburante!);

    if (daySkew <= _maxDateSkewDays &&
        litriStrict &&
        euroStrict &&
        prodottoOk) {
      return null;
    }

    var score = 0;
    var mismatchCount = 0;

    if (daySkew <= _maxDateSkewDays) {
      score += 30;
    } else {
      score += 18;
      mismatchCount++;
      differenze.add(
        'Data: RCC ${_fmtItDay(rcc.dataRifornimento)} · '
        'fattura ${_fmtItDay(qt.dataTransazione)} '
        '($daySkew gg di scarto)',
      );
    }

    if (litriStrict) {
      score += 35;
    } else if (litriNear) {
      score += 16;
      mismatchCount++;
      differenze.add(
        'Litri: RCC ${_fmtNum(rcc.litri)} L · '
        'fattura ${_fmtNum(qt.volume)} L',
      );
    } else {
      return null;
    }

    if (euroStrict) {
      score += 35;
    } else if (euroNear) {
      score += 16;
      mismatchCount++;
      differenze.add(
        'Euro: RCC ${_fmtEuro(rcc.euro)} · '
        'fattura ${_fmtEuro(qt.importo)}',
      );
    } else {
      return null;
    }

    if (!prodottoOk) {
      mismatchCount++;
      differenze.add(
        'Prodotto: RCC ${rcc.tipoCarburante ?? '—'} · '
        'fattura ${qt.prodotto}',
      );
      score -= 8;
    }

    if (mismatchCount == 0) return null;
    return score;
  }

  static _RccPoolRow _rccPoolFromSenzaFattura(QtCarburanteRccSenzaFatturaRow rcc) {
    return _RccPoolRow(
      idUuid: rcc.idUuid,
      cartaNorm: rcc.numeroCarta,
      isoData: _isoDay(rcc.dataRifornimento),
      litri: rcc.litri,
      euro: rcc.euro,
      fonte: rcc.fonte,
      tipoCarburante: rcc.tipoCarburante,
      nomeCognome: rcc.nomeCognome,
      cantiere: rcc.cantiere,
    );
  }

  static bool _nearVolumeMatch(double qt, double? rcc) {
    if (rcc == null) return false;
    final tol = (qt.abs() * _nearTolLitriPct).clamp(_nearTolLitriMin, 25.0);
    return (qt - rcc).abs() <= tol;
  }

  static bool _nearEuroMatch(double qt, double? rcc) {
    if (rcc == null) return false;
    final tol = (qt.abs() * _nearTolEuroPct).clamp(_nearTolEuroMin, 40.0);
    return (qt - rcc).abs() <= tol;
  }

  static String _fmtItDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  static String _fmtNum(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _fmtEuro(double? v) {
    if (v == null) return '—';
    return '€ ${_fmtNum(v)}';
  }

  static List<QtCarburanteRccSenzaFatturaRow> _buildGiustificativiSenzaFattura({
    required List<_RccPoolRow> pool,
    required Set<String> used,
    int? riferimentoAnno,
    int? riferimentoMese,
  }) {
    final out = <QtCarburanteRccSenzaFatturaRow>[];
    for (final row in pool) {
      if (used.contains(row.usedKey)) continue;
      final data = _parseIsoDay(row.isoData);
      if (data == null) continue;
      if (riferimentoAnno != null &&
          riferimentoMese != null &&
          (data.year != riferimentoAnno || data.month != riferimentoMese)) {
        continue;
      }
      out.add(
        QtCarburanteRccSenzaFatturaRow(
          fonte: row.fonte,
          idUuid: row.idUuid,
          numeroCarta: row.cartaNorm,
          dataRifornimento: data,
          litri: row.litri,
          euro: row.euro,
          tipoCarburante: row.tipoCarburante,
          nomeCognome: row.nomeCognome,
          cantiere: row.cantiere,
        ),
      );
    }
    out.sort((a, b) {
      final d = a.dataRifornimento.compareTo(b.dataRifornimento);
      if (d != 0) return d;
      return a.numeroCarta.compareTo(b.numeroCarta);
    });
    return out;
  }

  static Future<List<_RccPoolRow>> _loadMdo(
    SupabaseClient supa, {
    required String isoStart,
    required String isoEnd,
  }) async {
    try {
      final res = await supa
          .from('logistica_rcc_mdo_carburante')
          .select(
            'id_uuid,n_carta_carburante,data_rifornimento,litri,euro,tipo_carburante,nome_cognome,cantiere',
          )
          .gte('data_rifornimento', isoStart)
          .lte('data_rifornimento', isoEnd);
      return (res as List)
          .map(
            (e) => _RccPoolRow.fromMap(
              Map<String, dynamic>.from(e as Map),
              fonte: QtCarburanteFonteGiustificativo.rccMdo,
            ),
          )
          .toList();
    } catch (_) {
      return <_RccPoolRow>[];
    }
  }

  static Future<List<_RccPoolRow>> _loadStradali(
    SupabaseClient supa, {
    required String isoStart,
    required String isoEnd,
  }) async {
    try {
      final res = await supa
          .from('logistica_rcc_carburante')
          .select(
            'id_uuid,n_carta_carburante,data_rifornimento,litri,euro,tipo_carburante,nome_cognome,cantiere',
          )
          .gte('data_rifornimento', isoStart)
          .lte('data_rifornimento', isoEnd);
      return (res as List)
          .map(
            (e) => _RccPoolRow.fromMap(
              Map<String, dynamic>.from(e as Map),
              fonte: QtCarburanteFonteGiustificativo.rccStradali,
            ),
          )
          .toList();
    } catch (_) {
      return <_RccPoolRow>[];
    }
  }

  static bool _carteMatch(String a, String b) {
    final da = QtCarburanteTrxRow.normCarta(a);
    final db = QtCarburanteTrxRow.normCarta(b);
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    if (da.length > db.length && da.endsWith(db)) return true;
    if (db.length > da.length && db.endsWith(da)) return true;
    return false;
  }

  static Future<Map<String, String>> _loadMezziAssignees(
    SupabaseClient supa,
  ) async {
    try {
      final res = await supa
          .from('logistica_mezzi_stradali')
          .select('targa,assegnatario_attuale');
      final out = <String, String>{};
      for (final raw in res as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final targa = (row['targa'] ?? '').toString().trim().toLowerCase();
        final nome = (row['assegnatario_attuale'] ?? '').toString().trim();
        if (targa.isEmpty || nome.isEmpty) continue;
        out[targa] = nome;
      }
      return out;
    } catch (_) {
      return const <String, String>{};
    }
  }

  static QtMulticardAssigneeResolveResult _resolveAssigneeAtDate({
    required String cartaNorm,
    required DateTime data,
    required List<QtMulticardAssigneeProfile> profiles,
  }) {
    final profile = QtMulticardStoricoAssigneeLoader.findProfile(
      cartaNorm,
      profiles,
    );
    if (profile == null) {
      return const QtMulticardAssigneeResolveResult();
    }
    return profile.resolveAt(data);
  }

  static _RccPoolRow? _findMatch({
    required QtCarburanteTrxRow trx,
    required List<_RccPoolRow> pool,
    required Set<String> used,
  }) {
    _RccPoolRow? best;
    var bestScore = -1;

    for (final row in pool) {
      if (used.contains(row.usedKey)) continue;
      if (!_carteMatch(trx.cartaNorm, row.cartaNorm)) continue;

      final daySkew = _dateSkewDays(trx.isoData, row.isoData);
      if (daySkew > _maxDateSkewDays) continue;

      final litriOk = _quantitaMatch(trx: trx, row: row);
      final euroOk = _euroMatch(trx.importo, row.euro);
      if (!litriOk || !euroOk) continue;

      if (row.tipoCarburante != null &&
          row.tipoCarburante!.trim().isNotEmpty &&
          !_prodottiCompatibili(trx.prodotto, row.tipoCarburante!)) {
        continue;
      }

      var score = 0;
      score += daySkew == 0 ? 20 : 12 - (daySkew * 4);
      if (litriOk) score += 5;
      if (euroOk) score += 5;
      if (row.tipoCarburante != null &&
          _prodottiCompatibili(trx.prodotto, row.tipoCarburante!)) {
        score += 3;
      }

      if (score > bestScore) {
        bestScore = score;
        best = row;
      }
    }
    return best;
  }

  @visibleForTesting
  static bool quantitaMatchForTest({
    required String prodottoQt,
    required double volumeQt,
    required double importoQt,
    required double? litriRcc,
    required double? euroRcc,
    String? tipoRcc,
  }) =>
      _quantitaMatch(
        trx: QtCarburanteTrxRow(
          rigaExcel: 1,
          numeroCarta: '0',
          prodotto: prodottoQt,
          dataTransazione: DateTime(2026, 5, 19),
          volume: volumeQt,
          importo: importoQt,
        ),
        row: _RccPoolRow(
          idUuid: 'test',
          cartaNorm: '0',
          isoData: '2026-05-19',
          litri: litriRcc,
          euro: euroRcc,
          fonte: QtCarburanteFonteGiustificativo.rccMdo,
          tipoCarburante: tipoRcc,
        ),
      );

  static bool _quantitaMatch({
    required QtCarburanteTrxRow trx,
    required _RccPoolRow row,
  }) {
    if (_volumeMatch(trx.volume, row.litri)) return true;
    if (!_isAdBlueProdotto(trx.prodotto, row.tipoCarburante)) return false;
    if (!_euroMatch(trx.importo, row.euro)) return false;

    final rccLitri = row.litri;
    if (rccLitri == null) return false;

    // Fattura QT: 1 tanica (pezzi), RCC: litri contenuti (es. 10 L).
    if (trx.volume <= 3 &&
        rccLitri > trx.volume &&
        rccLitri <= 40 &&
        (row.tipoCarburante == null ||
            _normProdotto(row.tipoCarburante!) == 'ADBLUE')) {
      return true;
    }
    return false;
  }

  static bool _isAdBlueProdotto(String qt, String? rccTipo) {
    if (_normProdotto(qt) == 'ADBLUE') return true;
    if (rccTipo != null &&
        rccTipo.trim().isNotEmpty &&
        _normProdotto(rccTipo) == 'ADBLUE') {
      return true;
    }
    return false;
  }

  static bool _volumeMatch(double qt, double? rcc) {
    if (rcc == null) return false;
    final tol = (qt.abs() * _tolLitriPct).clamp(_tolLitriMin, 8.0);
    return (qt - rcc).abs() <= tol;
  }

  static bool _euroMatch(double qt, double? rcc) {
    if (rcc == null) return false;
    final tol = (qt.abs() * _tolEuroPct).clamp(_tolEuroMin, 5.0);
    return (qt - rcc).abs() <= tol;
  }

  static int _dateSkewDays(String qtIso, String rccIso) {
    final qt = _parseIsoDay(qtIso);
    final rcc = _parseIsoDay(rccIso);
    if (qt == null || rcc == null) return 999;
    return qt.difference(rcc).inDays.abs();
  }

  static DateTime? _parseIsoDay(String iso) {
    final part = iso.split('T').first.split(' ').first.trim();
    if (part.isEmpty) return null;
    final parsed = DateTime.tryParse(part);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _isoDayFromDb(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    return s.split('T').first.split(' ').first;
  }

  static bool _prodottiCompatibili(String qt, String rcc) {
    final a = _normProdotto(qt);
    final b = _normProdotto(rcc);
    if (a == b) return true;
    // HVO è sostituto renewable del gasolio/diesel.
    const dieselLike = {'GASOLIO', 'HVO'};
    return dieselLike.contains(a) && dieselLike.contains(b);
  }

  static String _normProdotto(String raw) {
    final u = raw.trim().toUpperCase();
    if (u.contains('HVO')) return 'HVO';
    if (u.contains('DIESEL') || u.contains('GASOLIO')) return 'GASOLIO';
    if (u.contains('ADBLUE') || u.contains('AD BLUE')) return 'ADBLUE';
    if (u.contains('BENZINA') ||
        u.contains('SENZA PIOMBO') ||
        u.contains('UNLEADED') ||
        u.contains('NORMALE')) {
      return 'BENZINA';
    }
    return u;
  }

  static String _isoDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<QtCarburanteSchedaRiepilogo> _buildSchedaSummary(
    List<QtCarburanteVerificaRow> righe,
    List<QtMulticardAssigneeProfile> multicardProfiles,
  ) {
    final byCarta = <String, List<QtCarburanteVerificaRow>>{};
    for (final r in righe) {
      final key = r.transazione.numeroCarta.trim();
      byCarta.putIfAbsent(key, () => <QtCarburanteVerificaRow>[]).add(r);
    }

    final out = <QtCarburanteSchedaRiepilogo>[];
    for (final entry in byCarta.entries) {
      final list = entry.value;
      final giust = list
          .where((r) => r.stato == QtCarburanteStatoVerifica.giustificato)
          .length;
      var impTot = 0.0;
      var impGiust = 0.0;
      for (final r in list) {
        impTot += r.transazione.importo;
        if (r.stato == QtCarburanteStatoVerifica.giustificato) {
          impGiust += r.transazione.importo;
        }
      }
      final responsabili = list
          .map((r) => r.assegnatario?.trim())
          .where((n) => n != null && n.isNotEmpty)
          .map((n) => n!)
          .toSet()
          .toList()
        ..sort();
      final assignee =
          responsabili.isEmpty ? null : responsabili.join(' · ');
      final profile = QtMulticardStoricoAssigneeLoader.findProfile(
        QtCarburanteTrxRow.normCarta(entry.key),
        multicardProfiles,
      );
      final attuale = profile?.assegnatarioAttuale?.trim();
      final daStorico = list.any((r) => r.responsabileDaStorico);
      final commesse = list
          .where(
            (r) =>
                r.stato == QtCarburanteStatoVerifica.giustificato &&
                r.rccCommessa?.trim().isNotEmpty == true,
          )
          .map((r) => r.rccCommessa!.trim())
          .toSet()
          .toList()
        ..sort();
      out.add(
        QtCarburanteSchedaRiepilogo(
          numeroCarta: entry.key,
          assegnatario: assignee,
          assegnatarioAttuale:
              attuale?.isNotEmpty == true ? attuale : null,
          responsabileDaStorico: daStorico,
          commessa: commesse.isEmpty ? null : commesse.join(' · '),
          totale: list.length,
          giustificati: giust,
          mancanti: list.length - giust,
          importoTotale: impTot,
          importoGiustificato: impGiust,
          importoMancante: impTot - impGiust,
        ),
      );
    }
    out.sort((a, b) {
      final na = (a.assegnatario ?? '').toLowerCase();
      final nb = (b.assegnatario ?? '').toLowerCase();
      if (na != nb) return na.compareTo(nb);
      return a.numeroCarta.compareTo(b.numeroCarta);
    });
    return out;
  }
}

class _RccPoolRow {
  final String idUuid;
  final String cartaNorm;
  final String isoData;
  final double? litri;
  final double? euro;
  final String? tipoCarburante;
  final String? nomeCognome;
  final String? cantiere;
  final QtCarburanteFonteGiustificativo fonte;

  const _RccPoolRow({
    required this.idUuid,
    required this.cartaNorm,
    required this.isoData,
    required this.litri,
    required this.euro,
    required this.fonte,
    this.tipoCarburante,
    this.nomeCognome,
    this.cantiere,
  });

  String get usedKey => '${fonte.name}:$idUuid';

  factory _RccPoolRow.fromMap(
    Map<String, dynamic> m, {
    required QtCarburanteFonteGiustificativo fonte,
  }) {
    return _RccPoolRow(
      idUuid: (m['id_uuid'] ?? '').toString(),
      cartaNorm: QtCarburanteTrxRow.normCarta(
        (m['n_carta_carburante'] ?? '').toString(),
      ),
      isoData: QtCarburanteVerificaService._isoDayFromDb(m['data_rifornimento']),
      litri: _asDouble(m['litri']),
      euro: _asDouble(m['euro']),
      fonte: fonte,
      tipoCarburante: (m['tipo_carburante'] ?? '').toString().trim().isEmpty
          ? null
          : (m['tipo_carburante'] ?? '').toString().trim(),
      nomeCognome: (m['nome_cognome'] ?? '').toString().trim().isEmpty
          ? null
          : (m['nome_cognome'] ?? '').toString().trim(),
      cantiere: (m['cantiere'] ?? '').toString().trim().isEmpty
          ? null
          : (m['cantiere'] ?? '').toString().trim(),
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}

class _NearMatchCandidate {
  const _NearMatchCandidate({
    required this.rcc,
    required this.qt,
    required this.score,
    required this.differenze,
  });

  final QtCarburanteRccSenzaFatturaRow rcc;
  final QtCarburanteTrxRow qt;
  final int score;
  final List<String> differenze;
}
