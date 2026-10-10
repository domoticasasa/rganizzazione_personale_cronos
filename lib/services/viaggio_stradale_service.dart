import 'dart:convert';

import 'package:http/http.dart' as http;

import 'carburante_giustificativi_stats_service.dart';
import 'supabase_service.dart';

/// Impostazioni globali per stima costo viaggio stradale.
class ViaggioStradaleSettings {
  const ViaggioStradaleSettings({
    required this.costoOrarioEur,
    required this.prezzoCarburanteEurLitro,
    required this.tollEurPerKmEstimate,
  });

  final double costoOrarioEur;
  final double prezzoCarburanteEurLitro;
  final double tollEurPerKmEstimate;

  factory ViaggioStradaleSettings.fromJson(Map<String, dynamic> m) {
    return ViaggioStradaleSettings(
      costoOrarioEur: _num(m['costo_orario_eur'], 25),
      prezzoCarburanteEurLitro: _num(m['prezzo_carburante_eur_litro'], 1.8),
      tollEurPerKmEstimate: _num(m['toll_eur_per_km_estimate'], 0.08),
    );
  }

  static double _num(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }
}

/// Tratta salvata (origine → destinazione).
class ViaggioStradaleTratta {
  const ViaggioStradaleTratta({
    required this.idUuid,
    required this.origineTipo,
    required this.origineNome,
    required this.destinazioneTipo,
    required this.destinazioneNome,
    required this.kmStradali,
    required this.pedaggioEur,
    required this.pedaggioFonte,
    this.origineRefId,
    this.destinazioneRefId,
    this.durataMinuti,
    this.origineLat,
    this.origineLon,
    this.destinazioneLat,
    this.destinazioneLon,
    this.note,
    this.lastPriceCheckAt,
    this.active = true,
  });

  final String idUuid;
  final String origineTipo;
  final String? origineRefId;
  final String origineNome;
  final String destinazioneTipo;
  final String? destinazioneRefId;
  final String destinazioneNome;
  final double kmStradali;
  final double pedaggioEur;
  final String pedaggioFonte;
  final int? durataMinuti;
  final double? origineLat;
  final double? origineLon;
  final double? destinazioneLat;
  final double? destinazioneLon;
  final String? note;
  final DateTime? lastPriceCheckAt;
  final bool active;

  String get label =>
      '${_tipoLabel(origineTipo)} $origineNome → '
      '${_tipoLabel(destinazioneTipo)} $destinazioneNome';

  static String _tipoLabel(String t) {
    switch (t) {
      case 'aeroporto':
        return 'Aeroporto';
      case 'stazione':
        return 'Stazione';
      default:
        return '';
    }
  }

  factory ViaggioStradaleTratta.fromJson(Map<String, dynamic> m) {
    DateTime? last;
    final raw = m['last_price_check_at'];
    if (raw != null) last = DateTime.tryParse(raw.toString());
    return ViaggioStradaleTratta(
      idUuid: (m['id_uuid'] ?? '').toString(),
      origineTipo: (m['origine_tipo'] ?? 'stazione').toString(),
      origineRefId: m['origine_ref_id']?.toString(),
      origineNome: (m['origine_nome'] ?? '').toString(),
      destinazioneTipo: (m['destinazione_tipo'] ?? 'stazione').toString(),
      destinazioneRefId: m['destinazione_ref_id']?.toString(),
      destinazioneNome: (m['destinazione_nome'] ?? '').toString(),
      kmStradali: ViaggioStradaleSettings._num(m['km_stradali'], 0),
      pedaggioEur: ViaggioStradaleSettings._num(m['pedaggio_eur'], 0),
      pedaggioFonte: (m['pedaggio_fonte'] ?? 'manuale').toString(),
      durataMinuti: m['durata_minuti'] is int
          ? m['durata_minuti'] as int
          : int.tryParse('${m['durata_minuti'] ?? ''}'),
      origineLat: _optDouble(m['origine_lat']),
      origineLon: _optDouble(m['origine_lon']),
      destinazioneLat: _optDouble(m['destinazione_lat']),
      destinazioneLon: _optDouble(m['destinazione_lon']),
      note: m['note']?.toString(),
      lastPriceCheckAt: last,
      active: m['active'] != false,
    );
  }

  static double? _optDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Map<String, dynamic> toInsertRow() => {
        'origine_tipo': origineTipo,
        'origine_ref_id': origineRefId,
        'origine_nome': origineNome.trim(),
        'destinazione_tipo': destinazioneTipo,
        'destinazione_ref_id': destinazioneRefId,
        'destinazione_nome': destinazioneNome.trim(),
        'km_stradali': kmStradali,
        'pedaggio_eur': pedaggioEur,
        'pedaggio_fonte': pedaggioFonte,
        'durata_minuti': durataMinuti,
        'origine_lat': origineLat,
        'origine_lon': origineLon,
        'destinazione_lat': destinazioneLat,
        'destinazione_lon': destinazioneLon,
        'note': note,
        'last_price_check_at': lastPriceCheckAt?.toUtc().toIso8601String(),
        'active': active,
      };
}

/// Risultato calcolo costo viaggio stradale.
class ViaggioStradaleCosto {
  const ViaggioStradaleCosto({
    required this.km,
    required this.litriPer100Km,
    required this.prezzoCarburante,
    required this.costoCarburante,
    required this.pedaggio,
    required this.durataMinuti,
    required this.costoOrario,
    required this.costoTempo,
    required this.totale,
  });

  final double km;
  final double litriPer100Km;
  final double prezzoCarburante;
  final double costoCarburante;
  final double pedaggio;
  final int durataMinuti;
  final double costoOrario;
  final double costoTempo;
  final double totale;
}

/// Luogo selezionabile (stazione / aeroporto / altro).
class ViaggioStradaleLuogo {
  const ViaggioStradaleLuogo({
    required this.tipo,
    required this.nome,
    this.refId,
    this.lat,
    this.lon,
  });

  final String tipo;
  final String nome;
  final String? refId;
  final double? lat;
  final double? lon;

  String get key => '$tipo|${refId ?? ''}|$nome';

  bool get hasCoords => lat != null && lon != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViaggioStradaleLuogo && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

  /// Mezzo/modello con consumo stimato L/100km.
class ViaggioStradaleMezzoOpzione {
  const ViaggioStradaleMezzoOpzione({
    required this.id,
    required this.label,
    required this.modello,
    required this.litriPer100Km,
    this.targa,
    this.consumoDaRcc = false,
  });

  final String id;
  final String label;
  final String modello;
  final double litriPer100Km;
  final String? targa;
  final bool consumoDaRcc;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViaggioStradaleMezzoOpzione && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

abstract final class ViaggioStradaleService {
  ViaggioStradaleService._();

  static final _supa = SupabaseService.client;

  static Future<ViaggioStradaleSettings> loadSettings() async {
    final row = await _supa
        .from('viaggio_stradale_settings')
        .select()
        .eq('id', 1)
        .maybeSingle();
    if (row == null) {
      return const ViaggioStradaleSettings(
        costoOrarioEur: 25,
        prezzoCarburanteEurLitro: 1.8,
        tollEurPerKmEstimate: 0.08,
      );
    }
    return ViaggioStradaleSettings.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  static Future<void> saveSettings(ViaggioStradaleSettings s) async {
    await _supa.from('viaggio_stradale_settings').upsert({
      'id': 1,
      'costo_orario_eur': s.costoOrarioEur,
      'prezzo_carburante_eur_litro': s.prezzoCarburanteEurLitro,
      'toll_eur_per_km_estimate': s.tollEurPerKmEstimate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<ViaggioStradaleTratta>> listTratte({
    bool onlyActive = true,
  }) async {
    var q = _supa.from('viaggio_stradale_tratte').select();
    if (onlyActive) q = q.eq('active', true);
    final res = await q.order('origine_nome').order('destinazione_nome');
    return (res as List)
        .map((e) => ViaggioStradaleTratta.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList(growable: false);
  }

  static Future<ViaggioStradaleTratta?> findTratta({
    required String origineTipo,
    required String origineNome,
    required String destinazioneTipo,
    required String destinazioneNome,
  }) async {
    final o = origineNome.trim().toLowerCase();
    final d = destinazioneNome.trim().toLowerCase();
    final rows = await listTratte();
    for (final t in rows) {
      if (t.origineTipo == origineTipo &&
          t.destinazioneTipo == destinazioneTipo &&
          t.origineNome.trim().toLowerCase() == o &&
          t.destinazioneNome.trim().toLowerCase() == d) {
        return t;
      }
    }
    // Match inverso (A→B = B→A stessi km)
    for (final t in rows) {
      if (t.origineTipo == destinazioneTipo &&
          t.destinazioneTipo == origineTipo &&
          t.origineNome.trim().toLowerCase() == d &&
          t.destinazioneNome.trim().toLowerCase() == o) {
        return t;
      }
    }
    return null;
  }

  static Future<ViaggioStradaleTratta> upsertTratta(
    ViaggioStradaleTratta t, {
    String? existingId,
  }) async {
    final row = t.toInsertRow();
    if (existingId != null && existingId.isNotEmpty) {
      final updated = await _supa
          .from('viaggio_stradale_tratte')
          .update(row)
          .eq('id_uuid', existingId)
          .select()
          .single();
      return ViaggioStradaleTratta.fromJson(
        Map<String, dynamic>.from(updated as Map),
      );
    }
    final inserted = await _supa
        .from('viaggio_stradale_tratte')
        .insert(row)
        .select()
        .single();
    return ViaggioStradaleTratta.fromJson(
      Map<String, dynamic>.from(inserted as Map),
    );
  }

  static Future<void> deactivateTratta(String idUuid) async {
    await _supa
        .from('viaggio_stradale_tratte')
        .update({'active': false})
        .eq('id_uuid', idUuid);
  }

  static ViaggioStradaleCosto calcolaCosto({
    required double km,
    required double litriPer100Km,
    required ViaggioStradaleSettings settings,
    required double pedaggioEur,
    int? durataMinuti,
  }) {
    final litri = (km / 100.0) * litriPer100Km;
    final costoCarb = litri * settings.prezzoCarburanteEurLitro;
    final minutes = durataMinuti ??
        (km > 0 ? ((km / 80.0) * 60).round() : 0); // ~80 km/h media
    final ore = minutes / 60.0;
    final costoTempo = ore * settings.costoOrarioEur;
    final totale = costoCarb + pedaggioEur + costoTempo;
    return ViaggioStradaleCosto(
      km: km,
      litriPer100Km: litriPer100Km,
      prezzoCarburante: settings.prezzoCarburanteEurLitro,
      costoCarburante: costoCarb,
      pedaggio: pedaggioEur,
      durataMinuti: minutes,
      costoOrario: settings.costoOrarioEur,
      costoTempo: costoTempo,
      totale: totale,
    );
  }

  /// Luoghi da master data stazioni + aeroporti.
  static Future<List<ViaggioStradaleLuogo>> loadLuoghi() async {
    final out = <ViaggioStradaleLuogo>[];
    try {
      final st = await _supa
          .from('stazioni')
          .select('id,nome,attiva,latitudine,longitudine')
          .order('nome');
      for (final r in st as List) {
        final m = Map<String, dynamic>.from(r as Map);
        if (m['attiva'] == false) continue;
        final nome = (m['nome'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        out.add(ViaggioStradaleLuogo(
          tipo: 'stazione',
          nome: nome,
          refId: '${m['id']}',
          lat: ViaggioStradaleTratta._optDouble(m['latitudine']),
          lon: ViaggioStradaleTratta._optDouble(m['longitudine']),
        ));
      }
    } catch (_) {
      // Fallback se colonne GPS non ancora migrate.
      try {
        final st = await _supa
            .from('stazioni')
            .select('id,nome,attiva')
            .order('nome');
        for (final r in st as List) {
          final m = Map<String, dynamic>.from(r as Map);
          if (m['attiva'] == false) continue;
          final nome = (m['nome'] ?? '').toString().trim();
          if (nome.isEmpty) continue;
          out.add(ViaggioStradaleLuogo(
            tipo: 'stazione',
            nome: nome,
            refId: '${m['id']}',
          ));
        }
      } catch (_) {}
    }
    try {
      final ae = await _supa
          .from('aeroporti')
          .select('id,nome,attiva,latitudine,longitudine')
          .order('nome');
      for (final r in ae as List) {
        final m = Map<String, dynamic>.from(r as Map);
        if (m['attiva'] == false) continue;
        final nome = (m['nome'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        out.add(ViaggioStradaleLuogo(
          tipo: 'aeroporto',
          nome: nome,
          refId: '${m['id']}',
          lat: ViaggioStradaleTratta._optDouble(m['latitudine']),
          lon: ViaggioStradaleTratta._optDouble(m['longitudine']),
        ));
      }
    } catch (_) {
      try {
        final ae = await _supa
            .from('aeroporti')
            .select('id,nome,attiva')
            .order('nome');
        for (final r in ae as List) {
          final m = Map<String, dynamic>.from(r as Map);
          if (m['attiva'] == false) continue;
          final nome = (m['nome'] ?? '').toString().trim();
          if (nome.isEmpty) continue;
          out.add(ViaggioStradaleLuogo(
            tipo: 'aeroporto',
            nome: nome,
            refId: '${m['id']}',
          ));
        }
      } catch (_) {}
    }
    return out;
  }

  /// Mezzi stradali + consumo L/100 da RCC (stesso calcolo del riepilogo carburante).
  static Future<List<ViaggioStradaleMezzoOpzione>> loadMezziConConsumo() async {
    final data = await CarburanteGiustificativiStatsService.loadWithRows();
    final mezziById = data.mezziById;
    final rcc = data.rccRows;

    final consumo = CarburanteGiustificativiStatsService.buildConsumoPerModello(
      rccRows: rcc,
      mezziById: mezziById,
      mezziByTarga: data.mezziByTarga,
    );
    // Chiave come nel riepilogo: "marca modello".toLowerCase()
    final byModello = <String, double>{
      for (final c in consumo)
        if (c.litriPer100Km > 0 && c.litriPer100Km < 40)
          c.modello.trim().toLowerCase(): c.litriPer100Km,
    };

    String modelKey(Map<String, dynamic> m) {
      final marca = (m['marca'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
      final modello = (m['modello'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
      if (marca.isNotEmpty && modello.isNotEmpty) {
        return '$marca $modello'.toLowerCase();
      }
      if (modello.isNotEmpty) return modello.toLowerCase();
      if (marca.isNotEmpty) return marca.toLowerCase();
      return '';
    }

    double? lookupL100(Map<String, dynamic> m) {
      final key = modelKey(m);
      if (key.isNotEmpty && byModello.containsKey(key)) return byModello[key];
      // Match soft: solo modello contenuto nella chiave stats.
      final modello = (m['modello'] ?? '').toString().trim().toLowerCase();
      if (modello.isEmpty) return null;
      for (final e in byModello.entries) {
        if (e.key == modello || e.key.endsWith(' $modello') || e.key.contains(modello)) {
          return e.value;
        }
      }
      return null;
    }

    final out = <ViaggioStradaleMezzoOpzione>[];
    final seenIds = <String>{};

    for (final m in mezziById.values) {
      final id = (m['id_uuid'] ?? '').toString();
      if (id.isEmpty || !seenIds.add(id)) continue;
      final targa = (m['targa'] ?? '').toString();
      final marca = (m['marca'] ?? '').toString().trim();
      final modello = (m['modello'] ?? '').toString().trim();
      final l100 = lookupL100(m);
      final fromRcc = l100 != null;
      final value = l100 ?? 0;
      final label = [
        if (targa.isNotEmpty) targa,
        if (marca.isNotEmpty || modello.isNotEmpty) '$marca $modello'.trim(),
        if (fromRcc)
          '(${value.toStringAsFixed(1)} L/100km da RCC)'
        else
          '(inserisci consumo)',
      ].where((e) => e.isNotEmpty).join(' · ');
      out.add(ViaggioStradaleMezzoOpzione(
        id: id,
        label: label,
        modello: modello.isEmpty ? 'n/d' : modello,
        litriPer100Km: value,
        targa: targa.isEmpty ? null : targa,
        consumoDaRcc: fromRcc,
      ));
    }

    // Opzioni solo-modello da stats (se non c'è mezzo in flotta).
    final modelliInFlotta = <String>{
      for (final m in mezziById.values) modelKey(m),
    };
    for (final e in byModello.entries) {
      if (modelliInFlotta.contains(e.key)) continue;
      out.add(ViaggioStradaleMezzoOpzione(
        id: 'modello:${e.key}',
        label: '${e.key} · (${e.value.toStringAsFixed(1)} L/100km da RCC)',
        modello: e.key,
        litriPer100Km: e.value,
        consumoDaRcc: true,
      ));
    }

    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  /// Geocoding Nominatim (Italia) + routing OSRM → aggiorna km/durata/pedaggio stimato.
  static Future<ViaggioStradaleTratta> aggiornaPrezzoTratta(
    ViaggioStradaleTratta tratta, {
    required ViaggioStradaleSettings settings,
    bool forceTollEstimate = false,
  }) async {
    final from = await _geocodeItalia(
      tratta.origineNome,
      tipo: tratta.origineTipo,
      lat: tratta.origineLat,
      lon: tratta.origineLon,
    );
    final to = await _geocodeItalia(
      tratta.destinazioneNome,
      tipo: tratta.destinazioneTipo,
      lat: tratta.destinazioneLat,
      lon: tratta.destinazioneLon,
    );
    if (from == null || to == null) {
      throw StateError(
        'Impossibile geolocalizzare '
        '${from == null ? tratta.origineNome : tratta.destinazioneNome}. '
        'Inserisci km manualmente o specifica meglio il nome.',
      );
    }

    final route = await _osrmRoute(from, to);
    final km = route.$1;
    final minutes = route.$2;
    final estimatedToll = km * settings.tollEurPerKmEstimate;

    final keepManualToll =
        tratta.pedaggioFonte == 'manuale' && !forceTollEstimate;
    final pedaggio = keepManualToll ? tratta.pedaggioEur : estimatedToll;
    final fonte = keepManualToll ? 'manuale' : 'aggiornato';

    final updated = ViaggioStradaleTratta(
      idUuid: tratta.idUuid,
      origineTipo: tratta.origineTipo,
      origineRefId: tratta.origineRefId,
      origineNome: tratta.origineNome,
      destinazioneTipo: tratta.destinazioneTipo,
      destinazioneRefId: tratta.destinazioneRefId,
      destinazioneNome: tratta.destinazioneNome,
      kmStradali: double.parse(km.toStringAsFixed(1)),
      pedaggioEur: double.parse(pedaggio.toStringAsFixed(2)),
      pedaggioFonte: fonte,
      durataMinuti: minutes,
      origineLat: from.$1,
      origineLon: from.$2,
      destinazioneLat: to.$1,
      destinazioneLon: to.$2,
      note: tratta.note,
      lastPriceCheckAt: DateTime.now().toUtc(),
      active: tratta.active,
    );

    return upsertTratta(updated, existingId: tratta.idUuid);
  }

  /// Crea o aggiorna tratta cercando km online (per nuova verifica).
  static Future<ViaggioStradaleTratta> resolveOrCreateTratta({
    required ViaggioStradaleLuogo origine,
    required ViaggioStradaleLuogo destinazione,
    required ViaggioStradaleSettings settings,
  }) async {
    final existing = await findTratta(
      origineTipo: origine.tipo,
      origineNome: origine.nome,
      destinazioneTipo: destinazione.tipo,
      destinazioneNome: destinazione.nome,
    );
    if (existing != null) {
      final needGeo = existing.origineLat == null ||
          existing.origineLon == null ||
          existing.destinazioneLat == null ||
          existing.destinazioneLon == null ||
          existing.kmStradali <= 0;
      if (!needGeo) return existing;
      final withCoords = ViaggioStradaleTratta(
        idUuid: existing.idUuid,
        origineTipo: existing.origineTipo,
        origineRefId: existing.origineRefId,
        origineNome: existing.origineNome,
        destinazioneTipo: existing.destinazioneTipo,
        destinazioneRefId: existing.destinazioneRefId,
        destinazioneNome: existing.destinazioneNome,
        kmStradali: existing.kmStradali,
        pedaggioEur: existing.pedaggioEur,
        pedaggioFonte: existing.pedaggioFonte,
        durataMinuti: existing.durataMinuti,
        origineLat: existing.origineLat ?? origine.lat,
        origineLon: existing.origineLon ?? origine.lon,
        destinazioneLat: existing.destinazioneLat ?? destinazione.lat,
        destinazioneLon: existing.destinazioneLon ?? destinazione.lon,
        note: existing.note,
        lastPriceCheckAt: existing.lastPriceCheckAt,
        active: existing.active,
      );
      return aggiornaPrezzoTratta(withCoords, settings: settings);
    }

    final draft = ViaggioStradaleTratta(
      idUuid: '',
      origineTipo: origine.tipo,
      origineRefId: origine.refId,
      origineNome: origine.nome,
      destinazioneTipo: destinazione.tipo,
      destinazioneRefId: destinazione.refId,
      destinazioneNome: destinazione.nome,
      kmStradali: 0,
      pedaggioEur: 0,
      pedaggioFonte: 'stima',
      origineLat: origine.lat,
      origineLon: origine.lon,
      destinazioneLat: destinazione.lat,
      destinazioneLon: destinazione.lon,
    );
    final created = await upsertTratta(draft);
    return aggiornaPrezzoTratta(created, settings: settings);
  }

  static Future<(double, double)?> _geocodeItalia(
    String nome, {
    required String tipo,
    double? lat,
    double? lon,
  }) async {
    if (lat != null && lon != null) return (lat, lon);
    final kind = tipo == 'aeroporto' ? 'aeroporto' : 'stazione';
    final q = '$nome $kind Italia';
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '1',
      'countrycodes': 'it',
    });
    final res = await http.get(
      uri,
      headers: const {
        'User-Agent': 'GESTOPRO360-Cronos/1.0 (viaggio-stradale)',
        'Accept-Language': 'it',
      },
    );
    if (res.statusCode != 200) return null;
    final list = jsonDecode(res.body);
    if (list is! List || list.isEmpty) return null;
    final first = list.first as Map;
    final la = double.tryParse('${first['lat']}');
    final lo = double.tryParse('${first['lon']}');
    if (la == null || lo == null) return null;
    return (la, lo);
  }

  /// Returns (km, minutes).
  static Future<(double, int)> _osrmRoute(
    (double, double) from,
    (double, double) to,
  ) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.$2},${from.$1};${to.$2},${to.$1}'
      '?overview=false',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw StateError('Routing OSRM non disponibile (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) {
      throw StateError('Nessun percorso stradale trovato');
    }
    final r0 = routes.first as Map;
    final meters = (r0['distance'] as num).toDouble();
    final seconds = (r0['duration'] as num).toDouble();
    return (meters / 1000.0, (seconds / 60.0).round());
  }
}
