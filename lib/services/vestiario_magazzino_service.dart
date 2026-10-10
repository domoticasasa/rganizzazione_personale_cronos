import '../utils/vestiario_catalog.dart';
import 'supabase_service.dart';
import 'vestiario_fabbisogno_service.dart';

class VestiarioMagazzinoRecord {
  final int magazzino;
  final int ordinato;
  final int arrivatoTotale;
  final String marca;

  const VestiarioMagazzinoRecord({
    this.magazzino = 0,
    this.ordinato = 0,
    this.arrivatoTotale = 0,
    this.marca = '',
  });

  static const empty = VestiarioMagazzinoRecord();
}

class VestiarioInventarioRiga {
  final String stagione;
  final String articolo;
  final String taglia;
  final int magazzino;
  final int fabbisogno;
  final int ordinato;
  final int arrivatoTotale;
  final String marca;

  const VestiarioInventarioRiga({
    required this.stagione,
    required this.articolo,
    required this.taglia,
    required this.magazzino,
    required this.fabbisogno,
    this.ordinato = 0,
    this.arrivatoTotale = 0,
    this.marca = '',
  });

  int get daOrdinare {
    final diff = fabbisogno - magazzino;
    return diff > 0 ? diff : 0;
  }

  /// Quantità ordinata ancora in attesa di consegna.
  int get inAttesaArrivo => ordinato;
}

class VestiarioArrivoStorico {
  final String articolo;
  final String taglia;
  final int quantita;
  final DateTime arrivatoAt;

  const VestiarioArrivoStorico({
    required this.articolo,
    required this.taglia,
    required this.quantita,
    required this.arrivatoAt,
  });
}

class VestiarioScaricoRisultato {
  final String articolo;
  final String taglia;
  final int richiesto;
  final int residuo;
  final bool insufficiente;

  const VestiarioScaricoRisultato({
    required this.articolo,
    required this.taglia,
    required this.richiesto,
    required this.residuo,
    required this.insufficiente,
  });
}

abstract final class VestiarioMagazzinoService {
  VestiarioMagazzinoService._();

  static String stockKey(String stagione, String articolo, String taglia) =>
      '$stagione|$articolo|$taglia';

  /// Giacenza canonica (estivo unificato, guanti → invernale) + fallback stagione legacy.
  static VestiarioMagazzinoRecord lookupRecord(
    Map<String, VestiarioMagazzinoRecord> records, {
    required String articolo,
    required String taglia,
  }) {
    final art = articolo.trim();
    final t = taglia.trim();
    if (art.isEmpty || t.isEmpty) return VestiarioMagazzinoRecord.empty;

    final canonStag = VestiarioCatalog.stagioneRegistrazioneMagazzino(art);
    final primary = records[stockKey(canonStag, art, t)];
    if (primary != null &&
        (primary.magazzino > 0 ||
            primary.ordinato > 0 ||
            primary.arrivatoTotale > 0)) {
      return primary;
    }

    final altStag = canonStag == 'estivo' ? 'invernale' : 'estivo';
    final legacy = records[stockKey(altStag, art, t)];
    if (legacy != null &&
        (legacy.magazzino > 0 ||
            legacy.ordinato > 0 ||
            legacy.arrivatoTotale > 0)) {
      return legacy;
    }

    return primary ?? legacy ?? VestiarioMagazzinoRecord.empty;
  }

  static int _nonNeg(dynamic v) {
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    if (n == null || n < 0) return 0;
    return n;
  }

  static Future<Map<String, VestiarioMagazzinoRecord>> loadRecordsMap() async {
    final rows = await SupabaseService.client
        .from('vestiario_magazzino')
        .select(
          'stagione, articolo, taglia, quantita, quantita_ordinata, quantita_arrivata_totale, marca',
        );
    final out = <String, VestiarioMagazzinoRecord>{};
    for (final raw in (rows as List)) {
      final r = Map<String, dynamic>.from(raw as Map);
      final stagione = (r['stagione'] ?? '').toString().trim();
      final articolo = (r['articolo'] ?? '').toString().trim();
      final taglia = (r['taglia'] ?? '').toString().trim();
      if (stagione.isEmpty || articolo.isEmpty || taglia.isEmpty) continue;
      out[stockKey(stagione, articolo, taglia)] = VestiarioMagazzinoRecord(
        magazzino: _nonNeg(r['quantita']),
        ordinato: _nonNeg(r['quantita_ordinata']),
        arrivatoTotale: _nonNeg(r['quantita_arrivata_totale']),
        marca: (r['marca'] ?? '').toString().trim(),
      );
    }
    return out;
  }

  static Future<Map<String, int>> loadStockMap() async {
    final records = await loadRecordsMap();
    return {
      for (final e in records.entries) e.key: e.value.magazzino,
    };
  }

  static Future<List<VestiarioInventarioRiga>> buildInventario({
    required String stagione,
    required List<VestiarioFabbisognoRow> fabbisognoRows,
    required Map<String, int> multiplierByItem,
    Map<String, VestiarioMagazzinoRecord>? recordsMap,
  }) async {
    final records = recordsMap ?? await loadRecordsMap();
    final out = <VestiarioInventarioRiga>[];
    final seen = <String>{};

    VestiarioInventarioRiga rowFrom({
      required String articolo,
      required String taglia,
      required int fabbisogno,
    }) {
      final rec = lookupRecord(
        records,
        articolo: articolo,
        taglia: taglia,
      );
      return VestiarioInventarioRiga(
        stagione: stagione,
        articolo: articolo,
        taglia: taglia,
        magazzino: rec.magazzino,
        fabbisogno: fabbisogno,
        ordinato: rec.ordinato,
        arrivatoTotale: rec.arrivatoTotale,
        marca: rec.marca,
      );
    }

    for (final row in fabbisognoRows) {
      if (!VestiarioCatalog.articoliMagazzino.contains(row.item)) continue;
      if (!VestiarioCatalog.magazzinoStagioneValida(row.item, stagione)) continue;
      final need = row.annualNeed(multiplierByItem);
      final key = '${row.item}|${row.size}';
      final rec = lookupRecord(
        records,
        articolo: row.item,
        taglia: row.size,
      );
      if (need <= 0 &&
          rec.magazzino <= 0 &&
          rec.ordinato <= 0 &&
          rec.arrivatoTotale <= 0) {
        continue;
      }
      seen.add(key);
      out.add(rowFrom(articolo: row.item, taglia: row.size, fabbisogno: need));
    }

    for (final entry in records.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      final articolo = parts[1];
      final taglia = parts[2];
      if (!VestiarioCatalog.magazzinoStagioneValida(articolo, stagione)) continue;
      final key = '$articolo|$taglia';
      if (seen.contains(key)) continue;
      final rec = lookupRecord(records, articolo: articolo, taglia: taglia);
      if (rec.magazzino <= 0 && rec.ordinato <= 0 && rec.arrivatoTotale <= 0) continue;
      seen.add(key);
      out.add(rowFrom(articolo: articolo, taglia: taglia, fabbisogno: 0));
    }

    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.articolo).compareTo(VestiarioCatalog.label(b.articolo));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.taglia, b.taglia);
    });
    return out;
  }

  /// Aggiunge tutte le taglie standard (es. 4XL) anche senza fabbisogno o giacenza.
  static List<VestiarioInventarioRiga> espandiGrigliaTaglie({
    required List<VestiarioInventarioRiga> righe,
    required String stagione,
  }) {
    final index = <String, VestiarioInventarioRiga>{
      for (final r in righe) '${r.articolo}|${r.taglia}': r,
    };
    final out = <VestiarioInventarioRiga>[];
    final keysInGrid = <String>{};

    for (final articolo in VestiarioCatalog.articoliMagazzino) {
      if (!VestiarioCatalog.magazzinoStagioneValida(articolo, stagione)) continue;
      for (final taglia in VestiarioCatalog.tagliePerArticolo(articolo)) {
        final key = '$articolo|$taglia';
        keysInGrid.add(key);
        out.add(
          index[key] ??
              VestiarioInventarioRiga(
                stagione: stagione,
                articolo: articolo,
                taglia: taglia,
                magazzino: 0,
                fabbisogno: 0,
              ),
        );
      }
    }

    for (final r in righe) {
      final key = '${r.articolo}|${r.taglia}';
      if (keysInGrid.contains(key)) continue;
      out.add(r);
    }

    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.articolo).compareTo(VestiarioCatalog.label(b.articolo));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.taglia, b.taglia);
    });
    return out;
  }

  /// Giacenza unica per articolo+taglia; fabbisogno resta per stagione nelle liste estivo/invernale.
  static List<VestiarioInventarioRiga> mergeStockUnificato({
    required List<VestiarioInventarioRiga> estivo,
    required List<VestiarioInventarioRiga> invernale,
  }) {
    final est = <String, VestiarioInventarioRiga>{};
    final inv = <String, VestiarioInventarioRiga>{};
    for (final r in estivo) {
      est['${r.articolo}|${r.taglia}'] = r;
    }
    for (final r in invernale) {
      inv['${r.articolo}|${r.taglia}'] = r;
    }

    final out = <VestiarioInventarioRiga>[];
    for (final key in {...est.keys, ...inv.keys}) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      final articolo = parts[0];
      final taglia = parts[1];
      final canon = VestiarioCatalog.stagioneRegistrazioneMagazzino(articolo);
      final re = est[key];
      final ri = inv[key];
      final primary = canon == 'invernale' ? ri : re;
      final fallback = canon == 'invernale' ? re : ri;

      int pickInt(int? a, int? b) => a ?? b ?? 0;

      out.add(
        VestiarioInventarioRiga(
          stagione: canon,
          articolo: articolo,
          taglia: taglia,
          magazzino: pickInt(primary?.magazzino, fallback?.magazzino),
          ordinato: pickInt(primary?.ordinato, fallback?.ordinato),
          arrivatoTotale: pickInt(primary?.arrivatoTotale, fallback?.arrivatoTotale),
          marca: (primary?.marca ?? fallback?.marca ?? '').trim(),
          fabbisogno: 0,
        ),
      );
    }

    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.articolo).compareTo(VestiarioCatalog.label(b.articolo));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.taglia, b.taglia);
    });
    return out;
  }

  static Future<void> upsertQuantita({
    required String stagione,
    required String articolo,
    required String taglia,
    required int quantita,
  }) async {
    final stagioneEff = VestiarioCatalog.magazzinoStagioneEffettiva(articolo, stagione);
    await SupabaseService.client.from('vestiario_magazzino').upsert(
      {
        'stagione': stagioneEff,
        'articolo': articolo,
        'taglia': taglia,
        'quantita': quantita < 0 ? 0 : quantita,
      },
      onConflict: 'stagione,articolo,taglia',
    );
  }

  /// Righe da persistere (stagione canonica DB, indipendente da fabbisogno estivo/invernale).
  static List<Map<String, dynamic>> righePerSalvataggio(
    Iterable<VestiarioInventarioRiga> righe,
  ) =>
      righe
          .where((r) => VestiarioCatalog.articoliMagazzino.contains(r.articolo))
          .map(
            (r) => {
              'stagione':
                  VestiarioCatalog.magazzinoStagioneEffettiva(r.articolo, r.stagione),
              'articolo': r.articolo,
              'taglia': r.taglia,
              'quantita': r.magazzino < 0 ? 0 : r.magazzino,
              'quantita_ordinata': r.ordinato < 0 ? 0 : r.ordinato,
              'quantita_arrivata_totale':
                  r.arrivatoTotale < 0 ? 0 : r.arrivatoTotale,
              'marca': r.marca.trim().isEmpty ? null : r.marca.trim(),
            },
          )
          .toList(growable: false);

  static Future<void> saveRighe(Iterable<VestiarioInventarioRiga> righe) async {
    final batch = righePerSalvataggio(righe);
    if (batch.isEmpty) return;
    await SupabaseService.client.from('vestiario_magazzino').upsert(
      batch,
      onConflict: 'stagione,articolo,taglia',
    );
  }

  static Future<void> deleteRiga({
    required String articolo,
    required String taglia,
  }) async {
    final stagione = VestiarioCatalog.magazzinoStagioneEffettiva(articolo, 'estivo');
    await SupabaseService.client.from('vestiario_magazzino').delete().match({
      'stagione': stagione,
      'articolo': articolo,
      'taglia': taglia,
    });
  }

  static Future<int> registraArrivo({
    required String stagione,
    required String articolo,
    required String taglia,
    required int quantita,
  }) async {
    if (quantita < 1) return 0;
    final stagioneEff = VestiarioCatalog.magazzinoStagioneEffettiva(articolo, stagione);
    try {
      final res = await SupabaseService.client.rpc(
        'vestiario_magazzino_registra_arrivo',
        params: {
          'p_stagione': stagioneEff,
          'p_articolo': articolo,
          'p_taglia': taglia.trim(),
          'p_quantita': quantita,
        },
      );
      if (res is List && res.isNotEmpty) {
        final row = Map<String, dynamic>.from(res.first as Map);
        return _nonNeg(row['quantita_magazzino']);
      }
    } catch (_) {
      // Fallback se RPC non migrata.
      final records = await loadRecordsMap();
      final key = stockKey(stagioneEff, articolo, taglia.trim());
      final old = records[key] ?? VestiarioMagazzinoRecord.empty;
      final nuovoMag = old.magazzino + quantita;
      final nuovoArr = old.arrivatoTotale + quantita;
      final nuovoOrd = old.ordinato - quantita;
      await SupabaseService.client.from('vestiario_magazzino').upsert(
        {
          'stagione': stagioneEff,
          'articolo': articolo,
          'taglia': taglia.trim(),
          'quantita': nuovoMag,
          'quantita_ordinata': nuovoOrd < 0 ? 0 : nuovoOrd,
          'quantita_arrivata_totale': nuovoArr,
        },
        onConflict: 'stagione,articolo,taglia',
      );
      return nuovoMag;
    }
    return 0;
  }

  static Future<int> registraArrivi(
    Iterable<({String stagione, String articolo, String taglia, int quantita})> righe,
  ) async {
    var count = 0;
    for (final r in righe) {
      if (r.quantita < 1) continue;
      await registraArrivo(
        stagione: r.stagione,
        articolo: r.articolo,
        taglia: r.taglia,
        quantita: r.quantita,
      );
      count++;
    }
    return count;
  }

  static Future<List<VestiarioArrivoStorico>> loadStoricoArrivi({
    String? articolo,
    String? taglia,
    int limit = 200,
  }) async {
    var query = SupabaseService.client
        .from('vestiario_magazzino_arrivi')
        .select('articolo, taglia, quantita, arrivato_at');
    if (articolo != null && articolo.trim().isNotEmpty) {
      query = query.eq('articolo', articolo.trim());
    }
    if (taglia != null && taglia.trim().isNotEmpty) {
      query = query.eq('taglia', taglia.trim());
    }
    final rows = await query.order('arrivato_at', ascending: false).limit(limit);
    final out = <VestiarioArrivoStorico>[];
    for (final raw in (rows as List)) {
      final r = Map<String, dynamic>.from(raw as Map);
      final atRaw = r['arrivato_at']?.toString();
      final at = atRaw == null ? DateTime.now() : DateTime.tryParse(atRaw) ?? DateTime.now();
      out.add(
        VestiarioArrivoStorico(
          articolo: (r['articolo'] ?? '').toString(),
          taglia: (r['taglia'] ?? '').toString(),
          quantita: _nonNeg(r['quantita']),
          arrivatoAt: at.toLocal(),
        ),
      );
    }
    return out;
  }

  /// Verifica giacenza senza scaricare (somma richieste per articolo+taglia).
  static Future<List<VestiarioScaricoRisultato>> verificaDisponibilita({
    required Iterable<({String articolo, String taglia, int quantita})> righe,
  }) async {
    final records = await loadRecordsMap();
    final richieste = <String, ({String articolo, String taglia, int quantita})>{};
    for (final r in righe) {
      final art =
          VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione(r.articolo);
      if (art == null) continue;
      final taglia = r.taglia.trim();
      if (taglia.isEmpty || r.quantita < 1) continue;
      final k = '$art|$taglia';
      final prev = richieste[k];
      richieste[k] = (
        articolo: art,
        taglia: taglia,
        quantita: (prev?.quantita ?? 0) + r.quantita,
      );
    }

    final out = <VestiarioScaricoRisultato>[];
    for (final r in richieste.values) {
      final rec = lookupRecord(records, articolo: r.articolo, taglia: r.taglia);
      final residuo = rec.magazzino - r.quantita;
      out.add(
        VestiarioScaricoRisultato(
          articolo: r.articolo,
          taglia: r.taglia,
          richiesto: r.quantita,
          residuo: residuo < 0 ? 0 : residuo,
          insufficiente: rec.magazzino < r.quantita,
        ),
      );
    }
    return out;
  }

  static Future<List<VestiarioScaricoRisultato>> scaricaAssegnazione({
    required String stagione,
    required Iterable<({String articolo, String taglia, int quantita})> righe,
  }) async {
    final out = <VestiarioScaricoRisultato>[];
    for (final r in righe) {
      final art =
          VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione(r.articolo);
      if (art == null) continue;
      if (r.taglia.trim().isEmpty || r.quantita < 1) continue;
      final stagioneEff = VestiarioCatalog.magazzinoStagioneEffettiva(art, stagione);
      final taglia = r.taglia.trim();
      try {
        final res = await SupabaseService.client.rpc(
          'vestiario_magazzino_scarica',
          params: {
            'p_stagione': stagioneEff,
            'p_articolo': art,
            'p_taglia': taglia,
            'p_quantita': r.quantita,
          },
        );
        if (res is List && res.isNotEmpty) {
          final row = Map<String, dynamic>.from(res.first as Map);
          out.add(
            VestiarioScaricoRisultato(
              articolo: art,
              taglia: taglia,
              richiesto: r.quantita,
              residuo: _nonNeg(row['quantita_residua']),
              insufficiente: row['insufficiente'] == true,
            ),
          );
          continue;
        }
      } catch (_) {
        // Fallback locale sotto.
      }

      final records = await loadRecordsMap();
      final rec = lookupRecord(records, articolo: art, taglia: taglia);
      final old = rec.magazzino;
      final residuo = old - r.quantita;
      final nuovo = residuo < 0 ? 0 : residuo;
      await upsertQuantita(
        stagione: stagioneEff,
        articolo: art,
        taglia: taglia,
        quantita: nuovo,
      );
      out.add(
        VestiarioScaricoRisultato(
          articolo: art,
          taglia: taglia,
          richiesto: r.quantita,
          residuo: nuovo,
          insufficiente: old < r.quantita,
        ),
      );
    }
    return out;
  }
}
