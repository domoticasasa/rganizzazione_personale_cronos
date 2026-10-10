import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/commessa_linked_assets.dart';
import '../utils/date_formatters.dart';
import '../utils/logistica_ubicazione_ref.dart';
import '../utils/mdo_gps_coords.dart';

enum MapPointKind { mdo, commessa, box, estintore, casettaPs, struttura, officina }

/// Punto sulla mappa: MDO tipo A o commessa con GPS.
class MdoMapPosition {
  const MdoMapPosition({
    required this.idUuid,
    required this.sigla,
    required this.lat,
    required this.lon,
    required this.kind,
    this.targaRfi,
    this.descrizioneMezzo,
    this.cantiere,
    this.commessa,
    this.lastDetectedAt,
    this.commessaIdUuid,
    this.tipologia,
  });

  final String idUuid;
  final String sigla;
  final double lat;
  final double lon;
  final MapPointKind kind;
  final String? targaRfi;
  final String? descrizioneMezzo;
  final String? cantiere;
  final String? commessa;
  final DateTime? lastDetectedAt;
  final String? commessaIdUuid;

  /// Tipologia struttura (es. "Hotel", "Ristorante", "Hotel · Ristorante").
  final String? tipologia;

  bool get isMdo => kind == MapPointKind.mdo;
  bool get isCommessa => kind == MapPointKind.commessa;
  bool get isBox => kind == MapPointKind.box;
  bool get isEstintore => kind == MapPointKind.estintore;
  bool get isCasettaPs => kind == MapPointKind.casettaPs;
  bool get isStruttura => kind == MapPointKind.struttura;
  bool get isOfficina => kind == MapPointKind.officina;

  String get mapMarkerKind => switch (kind) {
        MapPointKind.commessa => 'commessa',
        MapPointKind.box => 'box',
        MapPointKind.estintore => 'estintore',
        MapPointKind.casettaPs => 'casetta_ps',
        MapPointKind.struttura => 'struttura',
        MapPointKind.officina => 'officina',
        MapPointKind.mdo => 'mdo',
      };

  String get kindLabel {
    if (isCommessa) return 'Commessa';
    if (isBox) return 'BOX';
    if (isEstintore) return 'Estintore';
    if (isCasettaPs) return 'Cassetta P.S.';
    if (isStruttura) return 'Struttura';
    if (isOfficina) return 'Officina';
    return 'MDO tipo A';
  }

  String get coordsLabel => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

  String get lastDetectedLabel {
    if (isCommessa) return 'Coordinate da anagrafica commesse';
    if (isBox) return 'Coordinate da anagrafica BOX';
    if (isEstintore) return 'Coordinate da anagrafica estintori';
    if (isCasettaPs) return 'Coordinate da anagrafica cassette P.S.';
    if (isStruttura) return 'Coordinate da link Maps anagrafica strutture';
    if (isOfficina) return 'Coordinate da anagrafica officine convenzionate';
    if (lastDetectedAt == null) return '—';
    return formatDateTimeItFromSupabase(lastDetectedAt!.toUtc().toIso8601String());
  }
}

class LogisticaMdoMapService {
  LogisticaMdoMapService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<MdoMapPosition>> fetchTipoAWithGps() async {
    final res = await _client
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid, matricola_interna, codice_identificativo_targa_rfi, '
          'descrizione_mezzo, cantiere_attuale, commessa, posizione_gps, '
          'latitudine, longitudine, updated_at, active',
        )
        .eq('active', true)
        .order('matricola_interna', ascending: true);

    final out = <MdoMapPosition>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (!isMdoTipoA(row)) continue;
      final coords = mdoGpsCoordsFromRow(row);
      if (coords == null) continue;
      final (lat, lon) = coords;
      final sigla = (row['matricola_interna'] ?? '').toString().trim();
      if (sigla.isEmpty) continue;
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: sigla,
          lat: lat,
          lon: lon,
          kind: MapPointKind.mdo,
          targaRfi: _optStr(row['codice_identificativo_targa_rfi']),
          descrizioneMezzo: _optStr(row['descrizione_mezzo']),
          cantiere: _optStr(row['cantiere_attuale']),
          commessa: _optStr(row['commessa']),
          lastDetectedAt: _parseGpsLastDetected(row),
        ),
      );
    }
    return out;
  }

  Future<List<MdoMapPosition>> fetchCommesseWithGps() async {
    final res = await _client
        .from('commesse')
        .select('id_uuid, nome, latitudine, longitudine, active, pm, dt')
        .eq('active', true)
        .order('nome');

    final out = <MdoMapPosition>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final coords = mdoGpsCoordsFromRow(row);
      if (coords == null) continue;
      final (lat, lon) = coords;
      final nome = (row['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: nome,
          lat: lat,
          lon: lon,
          kind: MapPointKind.commessa,
          commessaIdUuid: (row['id_uuid'] ?? '').toString(),
          commessa: nome,
        ),
      );
    }
    return out;
  }

  Future<List<MdoMapPosition>> fetchAllMapPoints() async {
    final mdo = await fetchTipoAWithGps();
    final commesse = await fetchCommesseWithGps();
    return [...commesse, ...mdo];
  }

  Future<List<CommessaOption>> fetchCommesseOptions() async {
    final res = await _client
        .from('commesse')
        .select('id_uuid, nome')
        .eq('active', true)
        .order('nome');
    return (res as List)
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = (row['id_uuid'] ?? '').toString().trim();
          final nome = (row['nome'] ?? '').toString().trim();
          if (id.isEmpty || nome.isEmpty) return null;
          return CommessaOption(idUuid: id, nome: nome);
        })
        .whereType<CommessaOption>()
        .toList(growable: false);
  }

  /// Tutte le risorse abbinatе a una commessa (MDO per nome, altri per commessa_id).
  Future<CommessaLinkedAssets> fetchLinkedAssetsForCommessa({
    required String commessaIdUuid,
    required String commessaNome,
  }) async {
    final commRow = await _client
        .from('commesse')
        .select('id_uuid, nome, latitudine, longitudine')
        .eq('id_uuid', commessaIdUuid)
        .maybeSingle();
    double? commLat;
    double? commLon;
    if (commRow != null) {
      final coords = mdoGpsCoordsFromRow(Map<String, dynamic>.from(commRow));
      if (coords != null) {
        commLat = coords.$1;
        commLon = coords.$2;
      }
    }

    final nomeNorm = commessaNome.trim().toLowerCase();

    final mdoRes = await _client
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid, matricola_interna, descrizione_mezzo, cantiere_attuale, '
          'commessa, latitudine, longitudine, posizione_gps, active',
        )
        .eq('active', true)
        .order('matricola_interna');

    final mdoRowsAll = (mdoRes as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final mdoGpsByRef = mdoGpsLookupFromRows(mdoRowsAll);

    final mdo = <CommessaLinkedItem>[];
    for (final row in mdoRowsAll) {
      final c = (row['commessa'] ?? '').toString().trim().toLowerCase();
      if (c.isEmpty || c != nomeNorm) continue;
      final coords = mdoGpsCoordsFromRow(row);
      mdo.add(
        CommessaLinkedItem(
          assetType: 'mdo',
          idUuid: (row['id_uuid'] ?? '').toString(),
          label: (row['matricola_interna'] ?? '').toString().trim(),
          subtitle: _optStr(row['descrizione_mezzo']) ??
              _optStr(row['cantiere_attuale']),
          lat: coords?.$1,
          lon: coords?.$2,
        ),
      );
    }

    final boxRes = await _client
        .from('logistica_box')
        .select(
          'id_uuid, numero_interno, codice_box, nome_box, ubicazione, '
          'latitudine, longitudine, posizione_gps, active',
        )
        .eq('active', true)
        .eq('commessa_id', commessaIdUuid)
        .order('numero_interno');

    final boxRows = (boxRes as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final boxGpsByRef = boxGpsLookupFromRows(boxRows);

    final box = <CommessaLinkedItem>[];
    for (final row in boxRows) {
      final coords = mdoGpsCoordsFromRow(row);
      final codice = (row['codice_box'] ?? '').toString().trim();
      final numero = (row['numero_interno'] ?? '').toString().trim();
      final nome = (row['nome_box'] ?? '').toString().trim();
      box.add(
        CommessaLinkedItem(
          assetType: 'box',
          idUuid: (row['id_uuid'] ?? '').toString(),
          label: codice.isNotEmpty
              ? codice
              : (numero.isNotEmpty ? numero : nome),
          subtitle: _optStr(row['ubicazione']) ?? nome,
          lat: coords?.$1,
          lon: coords?.$2,
        ),
      );
    }

    final estRes = await _client
        .from('estintori')
        .select(
          'id_uuid, codice_interno, numero_estintore, ubicazione, '
          'posizione_gps, latitudine, longitudine, tipo, active',
        )
        .eq('commessa_id', commessaIdUuid)
        .order('codice_interno');

    final estintori = <CommessaLinkedItem>[];
    for (final raw in estRes as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final codice = (row['codice_interno'] ?? '').toString().trim();
      final numero = (row['numero_estintore'] ?? '').toString().trim();
      final gps = resolveLogisticaItemGps(
        row,
        boxGpsByRef,
        mdoGpsByRef: mdoGpsByRef,
      );
      final subtitleParts = <String>[
        if (_optStr(row['tipo']) != null) _optStr(row['tipo'])!,
        if (_optStr(row['ubicazione']) != null) _optStr(row['ubicazione'])!,
        if (gps.isInherited) 'GPS da ${gps.inheritedFrom}',
      ];
      estintori.add(
        CommessaLinkedItem(
          assetType: 'estintore',
          idUuid: (row['id_uuid'] ?? '').toString(),
          label: codice.isNotEmpty ? codice : numero,
          subtitle: subtitleParts.join(' · '),
          lat: gps.coords?.$1,
          lon: gps.coords?.$2,
        ),
      );
    }

    final attRes = await _client
        .from('logistica_attrezzature')
        .select(
          'id_uuid, codice_cronos, descrizione_articolo, posizione, commessa_id, active',
        )
        .eq('active', true)
        .eq('commessa_id', commessaIdUuid)
        .order('codice_cronos');

    final attrezzature = <CommessaLinkedItem>[];
    for (final raw in attRes as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      attrezzature.add(
        CommessaLinkedItem(
          assetType: 'attrezzatura',
          idUuid: (row['id_uuid'] ?? '').toString(),
          label: (row['codice_cronos'] ?? '').toString().trim(),
          subtitle: _optStr(row['descrizione_articolo']) ??
              _optStr(row['posizione']),
        ),
      );
    }

    final casRes = await _client
        .from('logistica_casette_ps')
        .select(
          'id_uuid, codice_interno, tipo_cassetta, ubicazione, commessa_id, '
          'latitudine, longitudine, posizione_gps, active',
        )
        .eq('active', true)
        .eq('commessa_id', commessaIdUuid)
        .order('codice_interno');

    final casettePs = <CommessaLinkedItem>[];
    for (final raw in casRes as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final gps = resolveLogisticaItemGps(
        row,
        boxGpsByRef,
        mdoGpsByRef: mdoGpsByRef,
      );
      final subtitleParts = <String>[
        if (_optStr(row['tipo_cassetta']) != null) _optStr(row['tipo_cassetta'])!,
        if (_optStr(row['ubicazione']) != null) _optStr(row['ubicazione'])!,
        if (gps.isInherited) 'GPS da ${gps.inheritedFrom}',
      ];
      casettePs.add(
        CommessaLinkedItem(
          assetType: 'casetta_ps',
          idUuid: (row['id_uuid'] ?? '').toString(),
          label: (row['codice_interno'] ?? '').toString().trim(),
          subtitle: subtitleParts.join(' · '),
          lat: gps.coords?.$1,
          lon: gps.coords?.$2,
        ),
      );
    }

    return CommessaLinkedAssets(
      commessaIdUuid: commessaIdUuid,
      commessaNome: commessaNome,
      commessaLat: commLat,
      commessaLon: commLon,
      mdo: mdo,
      box: box,
      estintori: estintori,
      attrezzature: attrezzature,
      casettePs: casettePs,
    );
  }

  Future<List<MdoMapPosition>> fetchBoxesWithGps() async {
    final res = await _client
        .from('logistica_box')
        .select(
          'id_uuid, numero_interno, codice_box, nome_box, ubicazione, '
          'posizione_gps, latitudine, longitudine, active',
        )
        .eq('active', true)
        .order('numero_interno', ascending: true);

    final out = <MdoMapPosition>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final coords = mdoGpsCoordsFromRow(row);
      if (coords == null) continue;
      final (lat, lon) = coords;
      final numero = (row['numero_interno'] ?? '').toString().trim();
      final codice = (row['codice_box'] ?? '').toString().trim();
      final nome = (row['nome_box'] ?? '').toString().trim();
      final sigla = codice.isNotEmpty
          ? codice
          : (numero.isNotEmpty ? numero : nome);
      if (sigla.isEmpty) continue;
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: sigla,
          lat: lat,
          lon: lon,
          kind: MapPointKind.box,
          descrizioneMezzo: _optStr(row['ubicazione']),
        ),
      );
    }
    return out;
  }

  Future<Map<String, String>> _fetchCommesseNameById() async {
    final res = await _client
        .from('commesse')
        .select('id_uuid, nome, active')
        .eq('active', true);
    final map = <String, String>{};
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = (row['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      map[id] = (row['nome'] ?? '').toString();
    }
    return map;
  }

  Future<
      ({
        Map<String, (double, double)> boxGps,
        Map<String, (double, double)> mdoGps,
      })> _fetchGpsLookups() async {
    final boxRes = await _client
        .from('logistica_box')
        .select(
          'numero_interno, codice_box, nome_box, latitudine, longitudine, '
          'posizione_gps, active',
        )
        .eq('active', true);
    final mdoRes = await _client
        .from('logistica_mdo_ferroviari')
        .select(
          'matricola_interna, descrizione_mezzo, latitudine, longitudine, '
          'posizione_gps, active',
        )
        .eq('active', true);
    return (
      boxGps: boxGpsLookupFromRows(
        (boxRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
      mdoGps: mdoGpsLookupFromRows(
        (mdoRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
    );
  }

  Future<List<MdoMapPosition>> fetchEstintoriWithGps() async {
    final lookups = await _fetchGpsLookups();
    final commesse = await _fetchCommesseNameById();
    final res = await _client
        .from('estintori')
        .select(
          'id_uuid, codice_interno, numero_estintore, ubicazione, commessa_id, '
          'posizione_gps, latitudine, longitudine, tipo, active',
        )
        .eq('active', true)
        .order('codice_interno');

    final out = <MdoMapPosition>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final gps = resolveLogisticaItemGps(
        row,
        lookups.boxGps,
        mdoGpsByRef: lookups.mdoGps,
      );
      if (gps.coords == null) continue;
      final codice = (row['codice_interno'] ?? '').toString().trim();
      final numero = (row['numero_estintore'] ?? '').toString().trim();
      final sigla = codice.isNotEmpty ? codice : numero;
      if (sigla.isEmpty) continue;
      final commessaId = (row['commessa_id'] ?? '').toString().trim();
      final subtitleParts = <String>[
        if (_optStr(row['tipo']) != null) _optStr(row['tipo'])!,
        if (_optStr(row['ubicazione']) != null) _optStr(row['ubicazione'])!,
        if (gps.isInherited) 'GPS da ${gps.inheritedFrom}',
      ];
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: sigla,
          lat: gps.coords!.$1,
          lon: gps.coords!.$2,
          kind: MapPointKind.estintore,
          descrizioneMezzo: subtitleParts.join(' · '),
          commessa: commessaId.isEmpty ? null : commesse[commessaId],
          commessaIdUuid: commessaId.isEmpty ? null : commessaId,
        ),
      );
    }
    return out;
  }

  Future<List<MdoMapPosition>> fetchCasettePsWithGps() async {
    final lookups = await _fetchGpsLookups();
    final commesse = await _fetchCommesseNameById();
    final res = await _client
        .from('logistica_casette_ps')
        .select(
          'id_uuid, codice_interno, tipo_cassetta, ubicazione, commessa_id, '
          'latitudine, longitudine, posizione_gps, active',
        )
        .eq('active', true)
        .order('codice_interno');

    final out = <MdoMapPosition>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final gps = resolveLogisticaItemGps(
        row,
        lookups.boxGps,
        mdoGpsByRef: lookups.mdoGps,
      );
      if (gps.coords == null) continue;
      final sigla = (row['codice_interno'] ?? '').toString().trim();
      if (sigla.isEmpty) continue;
      final commessaId = (row['commessa_id'] ?? '').toString().trim();
      final subtitleParts = <String>[
        if (_optStr(row['tipo_cassetta']) != null) _optStr(row['tipo_cassetta'])!,
        if (_optStr(row['ubicazione']) != null) _optStr(row['ubicazione'])!,
        if (gps.isInherited) 'GPS da ${gps.inheritedFrom}',
      ];
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: sigla,
          lat: gps.coords!.$1,
          lon: gps.coords!.$2,
          kind: MapPointKind.casettaPs,
          descrizioneMezzo: subtitleParts.join(' · '),
          commessa: commessaId.isEmpty ? null : commesse[commessaId],
          commessaIdUuid: commessaId.isEmpty ? null : commessaId,
        ),
      );
    }
    return out;
  }

  Future<List<MdoMapPosition>> fetchStruttureWithGps() async {
    final res = await _client
        .from('structures')
        .select(
          'id_uuid, name, address, maps_link, posizione_gps, '
          'is_hotel, is_ristorante, active',
        )
        .eq('active', true)
        .order('name');

    // Risolve in parallelo i link (anche short link goo.gl) -> coordinate.
    final rows = (res as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((row) => (row['name'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);

    final resolvedCoords = await Future.wait(
      rows.map((row) async {
        // Le coordinate GPS inserite manualmente hanno priorità sul link.
        final manual =
            mdoGpsCoordsFromText((row['posizione_gps'] ?? '').toString());
        if (manual != null) return manual;
        return mdoResolveGpsFromMapsLink((row['maps_link'] ?? '').toString());
      }),
    );

    final out = <MdoMapPosition>[];
    for (var i = 0; i < rows.length; i++) {
      final coords = resolvedCoords[i];
      if (coords == null) continue;
      final row = rows[i];
      final (lat, lon) = coords;
      final tipologiaParts = <String>[
        if (row['is_hotel'] == true) 'Hotel',
        if (row['is_ristorante'] == true) 'Ristorante',
      ];
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: (row['name'] ?? '').toString().trim(),
          lat: lat,
          lon: lon,
          kind: MapPointKind.struttura,
          descrizioneMezzo: _optStr(row['address']),
          tipologia:
              tipologiaParts.isEmpty ? null : tipologiaParts.join(' · '),
        ),
      );
    }
    return out;
  }

  Future<List<MdoMapPosition>> fetchOfficineWithGps() async {
    final res = await _client
        .from('logistica_officine_convenzionate')
        .select(
          'id_uuid, fornitore, marchio, tipologia, citta, via, provincia, '
          'telefono, latitudine, longitudine, maps_url, attivo',
        )
        .eq('attivo', true)
        .order('fornitore');

    final rows = (res as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((row) => (row['fornitore'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);

    final resolvedCoords = await Future.wait(
      rows.map((row) async {
        final manual = mdoGpsCoordsFromRow(row);
        if (manual != null) return manual;
        return mdoResolveGpsFromMapsLink((row['maps_url'] ?? '').toString());
      }),
    );

    final out = <MdoMapPosition>[];
    for (var i = 0; i < rows.length; i++) {
      final coords = resolvedCoords[i];
      if (coords == null) continue;
      final row = rows[i];
      final (lat, lon) = coords;
      final luogo = [
        (row['citta'] ?? '').toString().trim(),
        (row['provincia'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty).join(' · ');
      final subtitle = [
        if (luogo.isNotEmpty) luogo,
        _optStr(row['via']),
        _optStr(row['telefono']),
      ].whereType<String>().join(' · ');
      final tipoParts = [
        _optStr(row['marchio']),
        _optStr(row['tipologia']),
      ].whereType<String>().toList();
      out.add(
        MdoMapPosition(
          idUuid: (row['id_uuid'] ?? '').toString(),
          sigla: (row['fornitore'] ?? '').toString().trim(),
          lat: lat,
          lon: lon,
          kind: MapPointKind.officina,
          descrizioneMezzo: subtitle.isEmpty ? null : subtitle,
          tipologia: tipoParts.isEmpty ? null : tipoParts.join(' · '),
        ),
      );
    }
    return out;
  }

  static String? _optStr(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseGpsLastDetected(Map<String, dynamic> row) {
    return parseSupabaseTimestampToItaly(row['updated_at']);
  }
}
