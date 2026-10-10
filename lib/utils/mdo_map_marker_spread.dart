import 'dart:math' as math;

import '../services/logistica_mdo_map_service.dart';

/// Posizione e rotazione marker (spiderfy: punta sul GPS, etichetta ruotata).
class MdoMapMarkerCoords {
  const MdoMapMarkerCoords({
    required this.lat,
    required this.lon,
    this.rotationDeg = 0,
  });

  final double lat;
  final double lon;
  /// Rotazione icona (gradi): punta fissa sul punto, etichetta a ventaglio.
  final double rotationDeg;
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

int _find(List<int> parent, int x) {
  while (parent[x] != x) {
    parent[x] = parent[parent[x]];
    x = parent[x];
  }
  return x;
}

void _unite(List<int> parent, int a, int b) {
  final ra = _find(parent, a);
  final rb = _find(parent, b);
  if (ra != rb) parent[rb] = ra;
}

String _gpsKey(MdoMapPosition p) =>
    '${p.lat.toStringAsFixed(5)}|${p.lon.toStringAsFixed(5)}';

/// Raggruppa marker sullo stesso punto e assegna rotazioni a cerchio (punte coincidenti).
Map<String, MdoMapMarkerCoords> spreadMdoMapMarkerCoords(
  List<MdoMapPosition> positions, {
  double samePlaceMeters = 12,
}) {
  if (positions.isEmpty) return {};

  final n = positions.length;
  final parent = List<int>.generate(n, (i) => i);

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final sameKey = _gpsKey(positions[i]) == _gpsKey(positions[j]);
      final close = _haversineMeters(
            positions[i].lat,
            positions[i].lon,
            positions[j].lat,
            positions[j].lon,
          ) <=
          samePlaceMeters;
      if (sameKey || close) {
        _unite(parent, i, j);
      }
    }
  }

  final groups = <int, List<MdoMapPosition>>{};
  for (var i = 0; i < n; i++) {
    final root = _find(parent, i);
    groups.putIfAbsent(root, () => []).add(positions[i]);
  }

  final out = <String, MdoMapMarkerCoords>{};
  for (final group in groups.values) {
    if (group.length == 1) {
      final p = group.first;
      out[p.idUuid] = MdoMapMarkerCoords(lat: p.lat, lon: p.lon);
      continue;
    }

    group.sort((a, b) {
      int rank(MdoMapPosition p) {
        if (p.isCommessa) return 0;
        if (p.isMdo) return 1;
        return 2;
      }
      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return a.sigla.compareTo(b.sigla);
    });

    var centerLat = 0.0;
    var centerLon = 0.0;
    for (final p in group) {
      centerLat += p.lat;
      centerLon += p.lon;
    }
    centerLat /= group.length;
    centerLon /= group.length;

    final count = group.length;
    for (var i = 0; i < count; i++) {
      final p = group[i];
      out[p.idUuid] = MdoMapMarkerCoords(
        lat: centerLat,
        lon: centerLon,
        rotationDeg: -90 + 360 * i / count,
      );
    }
  }

  return out;
}
