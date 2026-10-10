import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/date_formatters.dart';
import 'mezzi_km_service.dart';

enum CarburanteTipo { benzina, gasolio, hvo, adBlue }

class CarburanteTipoTotals {
  const CarburanteTipoTotals({
    this.count = 0,
    this.litri = 0,
    this.euro = 0,
  });

  final int count;
  final double litri;
  final double euro;

  CarburanteTipoTotals add({
    required double litri,
    required double euro,
  }) {
    return CarburanteTipoTotals(
      count: count + 1,
      litri: this.litri + litri,
      euro: this.euro + euro,
    );
  }
}

class CarburantePerTipoStats {
  const CarburantePerTipoStats({
    this.benzina = const CarburanteTipoTotals(),
    this.gasolio = const CarburanteTipoTotals(),
    this.hvo = const CarburanteTipoTotals(),
    this.adBlue = const CarburanteTipoTotals(),
  });

  final CarburanteTipoTotals benzina;
  final CarburanteTipoTotals gasolio;
  final CarburanteTipoTotals hvo;
  final CarburanteTipoTotals adBlue;

  CarburantePerTipoStats addRow({
    required CarburanteTipo tipo,
    required double litri,
    required double euro,
  }) {
    switch (tipo) {
      case CarburanteTipo.benzina:
        return CarburantePerTipoStats(
          benzina: benzina.add(litri: litri, euro: euro),
          gasolio: gasolio,
          hvo: hvo,
          adBlue: adBlue,
        );
      case CarburanteTipo.gasolio:
        return CarburantePerTipoStats(
          benzina: benzina,
          gasolio: gasolio.add(litri: litri, euro: euro),
          hvo: hvo,
          adBlue: adBlue,
        );
      case CarburanteTipo.hvo:
        return CarburantePerTipoStats(
          benzina: benzina,
          gasolio: gasolio,
          hvo: hvo.add(litri: litri, euro: euro),
          adBlue: adBlue,
        );
      case CarburanteTipo.adBlue:
        return CarburantePerTipoStats(
          benzina: benzina,
          gasolio: gasolio,
          hvo: hvo,
          adBlue: adBlue.add(litri: litri, euro: euro),
        );
    }
  }
}

class CarburanteGiustificativiStats {
  const CarburanteGiustificativiStats({
    this.rccCount = 0,
    this.mdoCount = 0,
    this.rccLitri = 0,
    this.mdoLitri = 0,
    this.rccEuro = 0,
    this.mdoEuro = 0,
    this.perTipo = const CarburantePerTipoStats(),
  });

  final int rccCount;
  final int mdoCount;
  final double rccLitri;
  final double mdoLitri;
  final double rccEuro;
  final double mdoEuro;
  final CarburantePerTipoStats perTipo;

  int get totalCount => rccCount + mdoCount;
  double get totalLitri => rccLitri + mdoLitri;
  double get totalEuro => rccEuro + mdoEuro;
}

class CarburanteGiustificativiMonthBucket {
  const CarburanteGiustificativiMonthBucket({
    required this.year,
    required this.month,
    required this.stats,
  });

  final int year;
  final int month;
  final CarburanteGiustificativiStats stats;

  String get monthKey =>
      '$year-${month.toString().padLeft(2, '0')}';
}

class CarburanteGiustificativiReport {
  const CarburanteGiustificativiReport({
    required this.totals,
    required this.months,
  });

  final CarburanteGiustificativiStats totals;
  final List<CarburanteGiustificativiMonthBucket> months;
}

class CarburanteGiustificativiStatsService {
  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  static DateTime? _parseRifornimentoDate(dynamic v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    final iso = parseFlexibleDateToIsoDate(raw);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  static CarburanteTipo _classifyTipoCarburante(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return CarburanteTipo.gasolio;
    if (t.contains('benz')) return CarburanteTipo.benzina;
    if (t.contains('adblue') ||
        t.contains('ad blue') ||
        t.contains('ad-blue') ||
        t.contains('adblu')) {
      return CarburanteTipo.adBlue;
    }
    if (t.contains('hvo')) return CarburanteTipo.hvo;
    if (t.contains('gasol') ||
        t.contains('diesel') ||
        t.contains('gasolio')) {
      return CarburanteTipo.gasolio;
    }
    return CarburanteTipo.gasolio;
  }

  /// RCC: tipo assente → gasolio. MDO: tipo assente → non ripartire per categoria.
  static CarburanteTipo? resolveTipoForRow(
    Map<String, dynamic> row, {
    required bool isRcc,
  }) {
    final raw = (row['tipo_carburante'] ?? '').toString().trim();
    if (raw.isEmpty) {
      return isRcc ? CarburanteTipo.gasolio : null;
    }
    return _classifyTipoCarburante(raw);
  }

  static String tipoCarburanteLabel(Map<String, dynamic> row) {
    final raw = (row['tipo_carburante'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return '';
  }

  static CarburanteGiustificativiStats _addRowToStats({
    required CarburanteGiustificativiStats prev,
    required bool isRcc,
    required double litri,
    required double euro,
    CarburanteTipo? tipo,
  }) {
    return CarburanteGiustificativiStats(
      rccCount: isRcc ? prev.rccCount + 1 : prev.rccCount,
      mdoCount: isRcc ? prev.mdoCount : prev.mdoCount + 1,
      rccLitri: isRcc ? prev.rccLitri + litri : prev.rccLitri,
      mdoLitri: isRcc ? prev.mdoLitri : prev.mdoLitri + litri,
      rccEuro: isRcc ? prev.rccEuro + euro : prev.rccEuro,
      mdoEuro: isRcc ? prev.mdoEuro : prev.mdoEuro + euro,
      perTipo: tipo == null
          ? prev.perTipo
          : prev.perTipo.addRow(tipo: tipo, litri: litri, euro: euro),
    );
  }

  static CarburanteGiustificativiReport buildReport({
    required List<Map<String, dynamic>> rccRows,
    required List<Map<String, dynamic>> mdoRows,
  }) {
    final byMonth = <String, CarburanteGiustificativiStats>{};
    var totals = const CarburanteGiustificativiStats();

    void addRow({
      required Map<String, dynamic> row,
      required bool isRcc,
    }) {
      final date = _parseRifornimentoDate(row['data_rifornimento']);
      if (date == null) return;
      final litri = _toDouble(row['litri']);
      final euro = _toDouble(row['euro']);
      final tipo = resolveTipoForRow(row, isRcc: isRcc);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final prev = byMonth[key] ?? const CarburanteGiustificativiStats();
      final next = _addRowToStats(
        prev: prev,
        isRcc: isRcc,
        litri: litri,
        euro: euro,
        tipo: tipo,
      );
      byMonth[key] = next;
      totals = _addRowToStats(
        prev: totals,
        isRcc: isRcc,
        litri: litri,
        euro: euro,
        tipo: tipo,
      );
    }

    for (final row in rccRows) {
      addRow(row: row, isRcc: true);
    }
    for (final row in mdoRows) {
      addRow(row: row, isRcc: false);
    }

    final months = byMonth.entries.map((e) {
      final parts = e.key.split('-');
      return CarburanteGiustificativiMonthBucket(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        stats: e.value,
      );
    }).toList(growable: false)
      ..sort((a, b) {
        if (a.year != b.year) return b.year.compareTo(a.year);
        return b.month.compareTo(a.month);
      });

    return CarburanteGiustificativiReport(totals: totals, months: months);
  }

  static Future<List<Map<String, dynamic>>> _fetchAllRows({
    required SupabaseClient client,
    required String table,
    required String columns,
  }) async {
    // PostgREST default ~1000: senza paginazione i mesi recenti RCC spariscono.
    const pageSize = 1000;
    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final res = await client
          .from(table)
          .select(columns)
          .order('data_rifornimento', ascending: false)
          .range(from, from + pageSize - 1);
      final batch = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      out.addAll(batch);
      if (batch.length < pageSize) break;
      from += pageSize;
    }
    return out;
  }

  static Future<CarburanteGiustificativiReport> load({SupabaseClient? supa}) async {
    final client = supa ?? Supabase.instance.client;
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _fetchAllRows(
        client: client,
        table: 'logistica_rcc_carburante',
        columns: 'data_rifornimento,litri,euro,tipo_carburante',
      ),
      _fetchAllRows(
        client: client,
        table: 'logistica_rcc_mdo_carburante',
        columns: 'data_rifornimento,litri,euro,tipo_carburante',
      ),
    ]);
    return buildReport(rccRows: results[0], mdoRows: results[1]);
  }

  static bool rowMatchesMonth(
    Map<String, dynamic> row,
    int year,
    int month,
  ) {
    final date = _parseRifornimentoDate(row['data_rifornimento']);
    return date != null && date.year == year && date.month == month;
  }

  static List<Map<String, dynamic>> filterRowsForMonth(
    List<Map<String, dynamic>> rows,
    int year,
    int month,
  ) {
    return rows
        .where((r) => rowMatchesMonth(r, year, month))
        .toList(growable: false);
  }

  /// Consumo L/100km da tratti tra letture km sullo stesso mezzo (solo RCC).
  ///
  /// Tra due km validi somma **tutti** i litri benzina/gasolio intermedi
  /// (anche rifornimenti senza km). I modelli si unificano ignorando
  /// maiuscole/minuscole e spazi multipli.
  static List<CarburanteConsumoModelloStats> buildConsumoPerModello({
    required List<Map<String, dynamic>> rccRows,
    required Map<String, Map<String, dynamic>> mezziById,
    Map<String, Map<String, dynamic>> mezziByTarga = const {},
    int? year,
    int? month,
  }) {
    // Max km tra due letture consecutive: oltre = tipicamente km errato.
    const maxDeltaKm = 2500;
    const minDeltaKm = 5;

    final byVehicle = <String, List<Map<String, dynamic>>>{};
    for (final row in rccRows) {
      final date = _parseRifornimentoDate(row['data_rifornimento']);
      if (date == null) continue;
      final vehicleKey = _vehicleKeyForRow(row);
      if (vehicleKey == null) continue;
      byVehicle.putIfAbsent(vehicleKey, () => <Map<String, dynamic>>[]).add(row);
    }

    final agg = <String, _ConsumoModelloAgg>{};
    // Per-mezzo L/100 (per min/max sul modello).
    final perMezzoL100 = <String, List<double>>{};

    for (final entry in byVehicle.entries) {
      final rows = List<Map<String, dynamic>>.from(entry.value)
        ..sort((a, b) {
          final da = _parseRifornimentoDate(a['data_rifornimento'])!;
          final db = _parseRifornimentoDate(b['data_rifornimento'])!;
          final c = da.compareTo(db);
          if (c != 0) return c;
          return (a['id_uuid'] ?? '')
              .toString()
              .compareTo((b['id_uuid'] ?? '').toString());
        });

      final modelInfo = _modelInfoForVehicle(
        vehicleKey: entry.key,
        sampleRow: rows.first,
        mezziById: mezziById,
        mezziByTarga: mezziByTarga,
      );

      var lastKmIdx = -1;
      int? lastKm;
      double mezzoLitri = 0;
      double mezzoKm = 0;

      for (var i = 0; i < rows.length; i++) {
        final curKm = MezziKmService.parseKmOreValue(rows[i]['km_ore']);
        if (curKm == null) continue;

        if (lastKm != null && lastKmIdx >= 0) {
          final deltaKm = curKm - lastKm;
          if (deltaKm >= minDeltaKm && deltaKm <= maxDeltaKm) {
            var litri = 0.0;
            var euro = 0.0;
            var rifornimenti = 0;
            for (var j = lastKmIdx + 1; j <= i; j++) {
              final tipo = resolveTipoForRow(rows[j], isRcc: true);
              if (tipo == CarburanteTipo.adBlue) continue;
              final l = _toDouble(rows[j]['litri']);
              if (l <= 0) continue;
              litri += l;
              euro += _toDouble(rows[j]['euro']);
              rifornimenti += 1;
            }
            if (litri > 0) {
              final l100 = (litri / deltaKm) * 100;
              // Fuori range realistico auto/furgoni → tratto scartato.
              if (l100 >= 1.5 && l100 <= 40) {
                final curDate =
                    _parseRifornimentoDate(rows[i]['data_rifornimento'])!;
                final inMonth = year == null ||
                    month == null ||
                    (curDate.year == year && curDate.month == month);
                if (inMonth) {
                  final bucket = agg.putIfAbsent(
                    modelInfo.key,
                    () => _ConsumoModelloAgg(modello: modelInfo.label),
                  );
                  // Preferisci label con casing “normale” se arriva dopo ALL CAPS.
                  if (_preferModelLabel(modelInfo.label, bucket.modello)) {
                    bucket.modello = modelInfo.label;
                  }
                  bucket.litri += litri;
                  bucket.euro += euro;
                  bucket.km += deltaKm;
                  bucket.segmenti += 1;
                  bucket.rifornimenti += rifornimenti;
                  bucket.mezziIds.add(entry.key);
                  mezzoLitri += litri;
                  mezzoKm += deltaKm;
                }
              }
            }
          }
        }
        lastKm = curKm;
        lastKmIdx = i;
      }

      if (mezzoKm >= minDeltaKm && mezzoLitri > 0) {
        perMezzoL100
            .putIfAbsent(modelInfo.key, () => <double>[])
            .add((mezzoLitri / mezzoKm) * 100);
      }
    }

    final list = agg.entries.map((e) {
      final a = e.value;
      final l100 = a.km > 0 ? (a.litri / a.km) * 100 : 0.0;
      final samples = perMezzoL100[e.key] ?? const <double>[];
      double? minL;
      double? maxL;
      if (samples.isNotEmpty) {
        minL = samples.reduce((x, y) => x < y ? x : y);
        maxL = samples.reduce((x, y) => x > y ? x : y);
      }
      return CarburanteConsumoModelloStats(
        modello: a.modello,
        mezziCount: a.mezziIds.length,
        segmenti: a.segmenti,
        rifornimenti: a.rifornimenti,
        km: a.km,
        litri: a.litri,
        euro: a.euro,
        litriPer100Km: l100,
        euroPer100Km: a.km > 0 ? (a.euro / a.km) * 100 : 0,
        minLitriPer100Km: minL,
        maxLitriPer100Km: maxL,
      );
    }).toList(growable: false)
      ..sort((a, b) => a.modello.toLowerCase().compareTo(b.modello.toLowerCase()));
    return list;
  }

  static bool _preferModelLabel(String candidate, String current) {
    if (current.isEmpty) return true;
    final cAllCaps = candidate == candidate.toUpperCase() &&
        candidate != candidate.toLowerCase();
    final curAllCaps = current == current.toUpperCase() &&
        current != current.toLowerCase();
    if (curAllCaps && !cAllCaps) return true;
    if (!curAllCaps && cAllCaps) return false;
    // Preferisci più lettere minuscole “parola” (Title Case).
    return candidate.length >= current.length;
  }

  static String? _vehicleKeyForRow(Map<String, dynamic> row) {
    final mezzoId = (row['mezzo_stradale_id_uuid'] ?? '').toString().trim();
    if (mezzoId.isNotEmpty) return 'id:$mezzoId';
    final targa = (row['targa_matricola'] ?? '').toString().trim().toUpperCase();
    if (targa.isNotEmpty) return 'targa:$targa';
    return null;
  }

  static ({String key, String label}) _modelInfoForVehicle({
    required String vehicleKey,
    required Map<String, dynamic> sampleRow,
    required Map<String, Map<String, dynamic>> mezziById,
    required Map<String, Map<String, dynamic>> mezziByTarga,
  }) {
    Map<String, dynamic>? mezzo;
    if (vehicleKey.startsWith('id:')) {
      mezzo = mezziById[vehicleKey.substring(3)];
    } else if (vehicleKey.startsWith('targa:')) {
      mezzo = mezziByTarga[vehicleKey.substring(6)];
    }
    mezzo ??= () {
      final id = (sampleRow['mezzo_stradale_id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) return mezziById[id];
      final t =
          (sampleRow['targa_matricola'] ?? '').toString().trim().toUpperCase();
      if (t.isNotEmpty) return mezziByTarga[t];
      return null;
    }();

    final marca = _collapseSpaces((mezzo?['marca'] ?? '').toString());
    final modello = _collapseSpaces((mezzo?['modello'] ?? '').toString());
    if (marca.isNotEmpty && modello.isNotEmpty) {
      final label = '$marca $modello';
      return (key: label.toLowerCase(), label: _titleCaseWords(label));
    }
    if (modello.isNotEmpty) {
      return (key: modello.toLowerCase(), label: _titleCaseWords(modello));
    }
    if (marca.isNotEmpty) {
      return (key: marca.toLowerCase(), label: _titleCaseWords(marca));
    }
    final targa = (mezzo?['targa'] ?? sampleRow['targa_matricola'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (targa.isNotEmpty) {
      return (key: 'targa:$targa', label: 'Targa $targa');
    }
    return (key: 'senza-modello', label: 'Senza modello');
  }

  static String _collapseSpaces(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _titleCaseWords(String raw) {
    final s = _collapseSpaces(raw);
    if (s.isEmpty) return s;
    // Se già mixed-case (non tutto maiuscolo), mantieni così com’è.
    final lower = s.toLowerCase();
    final upper = s.toUpperCase();
    if (s != upper && s != lower) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      if (w.length == 1) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static Future<
      ({
        CarburanteGiustificativiReport report,
        List<Map<String, dynamic>> rccRows,
        List<Map<String, dynamic>> mdoRows,
        Map<String, Map<String, dynamic>> mezziById,
        Map<String, Map<String, dynamic>> mezziByTarga,
      })> loadWithRows({SupabaseClient? supa}) async {
    final client = supa ?? Supabase.instance.client;
    final results = await Future.wait<dynamic>([
      _fetchAllRows(
        client: client,
        table: 'logistica_rcc_carburante',
        columns:
            'id_uuid,data_rifornimento,litri,euro,tipo_carburante,n_carta_carburante,'
            'nome_cognome,cantiere,km_ore,mezzo_stradale_id_uuid,targa_matricola',
      ),
      _fetchAllRows(
        client: client,
        table: 'logistica_rcc_mdo_carburante',
        columns:
            'id_uuid,data_rifornimento,litri,euro,tipo_carburante,nome_cognome,automezzo_mdo,cantiere',
      ),
      client.from('logistica_mezzi_stradali').select(
          'id_uuid,targa,marca,modello'),
    ]);
    final rccRows = results[0] as List<Map<String, dynamic>>;
    final mdoRows = results[1] as List<Map<String, dynamic>>;
    final mezziById = <String, Map<String, dynamic>>{};
    final mezziByTarga = <String, Map<String, dynamic>>{};
    for (final raw in (results[2] as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) mezziById[id] = m;
      final targa = (m['targa'] ?? '').toString().trim().toUpperCase();
      if (targa.isNotEmpty) mezziByTarga.putIfAbsent(targa, () => m);
    }
    final report = buildReport(rccRows: rccRows, mdoRows: mdoRows);
    return (
      report: report,
      rccRows: rccRows,
      mdoRows: mdoRows,
      mezziById: mezziById,
      mezziByTarga: mezziByTarga,
    );
  }

  static double? euroLitroRiga(Map<String, dynamic> row) {
    final litri = _toDouble(row['litri']);
    final euro = _toDouble(row['euro']);
    if (litri <= 0) return null;
    return euro / litri;
  }

  static List<CarburanteRifornimentoSogliaVoce> findRifornimentiOltreSoglia({
    required List<Map<String, dynamic>> rccRows,
    required List<Map<String, dynamic>> mdoRows,
    required int year,
    required int month,
    required double sogliaEuroLitro,
  }) {
    final out = <CarburanteRifornimentoSogliaVoce>[];

    void addRcc(Map<String, dynamic> row) {
      final euroLitro = euroLitroRiga(row);
      if (euroLitro == null || euroLitro <= sogliaEuroLitro) return;
      out.add(
        CarburanteRifornimentoSogliaVoce(
          fonte: CarburanteRifornimentoFonte.rcc,
          idUuid: (row['id_uuid'] ?? '').toString().trim(),
          dataRifornimento: (row['data_rifornimento'] ?? '').toString(),
          litri: _toDouble(row['litri']),
          euro: _toDouble(row['euro']),
          euroLitro: euroLitro,
          tipoCarburante: tipoCarburanteLabel(row).isEmpty
              ? null
              : tipoCarburanteLabel(row),
          nomeCognome: (row['nome_cognome'] ?? '').toString(),
          cantiere: (row['cantiere'] ?? '').toString(),
          dettaglio: (row['n_carta_carburante'] ?? '').toString(),
        ),
      );
    }

    void addMdo(Map<String, dynamic> row) {
      final euroLitro = euroLitroRiga(row);
      if (euroLitro == null || euroLitro <= sogliaEuroLitro) return;
      out.add(
        CarburanteRifornimentoSogliaVoce(
          fonte: CarburanteRifornimentoFonte.mdo,
          idUuid: (row['id_uuid'] ?? '').toString().trim(),
          dataRifornimento: (row['data_rifornimento'] ?? '').toString(),
          litri: _toDouble(row['litri']),
          euro: _toDouble(row['euro']),
          euroLitro: euroLitro,
          tipoCarburante: tipoCarburanteLabel(row).isEmpty
              ? null
              : tipoCarburanteLabel(row),
          nomeCognome: (row['nome_cognome'] ?? '').toString(),
          cantiere: (row['cantiere'] ?? '').toString(),
          dettaglio: (row['automezzo_mdo'] ?? '').toString(),
        ),
      );
    }

    for (final row in filterRowsForMonth(rccRows, year, month)) {
      addRcc(row);
    }
    for (final row in filterRowsForMonth(mdoRows, year, month)) {
      addMdo(row);
    }

    out.sort((a, b) => b.euroLitro.compareTo(a.euroLitro));
    return out;
  }
}

enum CarburanteRifornimentoFonte { rcc, mdo }

class CarburanteConsumoModelloStats {
  const CarburanteConsumoModelloStats({
    required this.modello,
    required this.mezziCount,
    required this.segmenti,
    required this.rifornimenti,
    required this.km,
    required this.litri,
    required this.euro,
    required this.litriPer100Km,
    required this.euroPer100Km,
    this.minLitriPer100Km,
    this.maxLitriPer100Km,
  });

  final String modello;
  final int mezziCount;
  final int segmenti;
  final int rifornimenti;
  final double km;
  final double litri;
  final double euro;
  final double litriPer100Km;
  final double euroPer100Km;
  final double? minLitriPer100Km;
  final double? maxLitriPer100Km;
}

class _ConsumoModelloAgg {
  _ConsumoModelloAgg({required this.modello});

  String modello;
  double litri = 0;
  double euro = 0;
  double km = 0;
  int segmenti = 0;
  int rifornimenti = 0;
  final Set<String> mezziIds = <String>{};
}

class CarburanteRifornimentoSogliaVoce {
  const CarburanteRifornimentoSogliaVoce({
    required this.fonte,
    required this.idUuid,
    required this.dataRifornimento,
    required this.litri,
    required this.euro,
    required this.euroLitro,
    this.tipoCarburante,
    this.nomeCognome,
    this.cantiere,
    this.dettaglio,
  });

  final CarburanteRifornimentoFonte fonte;
  final String idUuid;
  final String dataRifornimento;
  final double litri;
  final double euro;
  final double euroLitro;
  final String? tipoCarburante;
  final String? nomeCognome;
  final String? cantiere;
  final String? dettaglio;

  String get fonteLabel =>
      fonte == CarburanteRifornimentoFonte.rcc ? 'RCC Stradali' : 'MDO';
}
