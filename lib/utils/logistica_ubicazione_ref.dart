import 'mdo_gps_coords.dart';

/// Normalizza riferimento ubicazione (es. «BOX03 - magazzino» → `BOX03`).
String extractLogisticaUbicazioneRef(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.isEmpty) return '';
  if (s.contains('-')) s = s.split('-').first.trim();

  final normalizedSpaces = s.replaceAll(RegExp(r'\s+'), ' ');

  final boxSpaced = RegExp(r'^BOX\s*N?\s*(\d+)\s*$', caseSensitive: false)
      .firstMatch(normalizedSpaces);
  if (boxSpaced != null) {
    return 'BOX${boxSpaced.group(1)!}';
  }

  final uffSpaced = RegExp(r'^UFF\s*N?\s*(\d+)\s*$', caseSensitive: false)
      .firstMatch(normalizedSpaces);
  if (uffSpaced != null) {
    return 'UFF${uffSpaced.group(1)!}';
  }

  s = normalizedSpaces.split(RegExp(r'\s+')).first.trim();
  return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

/// Indice ref BOX → coordinate GPS (numero_interno, codice_box, nome_box).
Map<String, (double, double)> boxGpsLookupFromRows(
  Iterable<Map<String, dynamic>> boxRows,
) {
  final map = <String, (double, double)>{};

  void register(String raw, (double, double) coords) {
    final ref = extractLogisticaUbicazioneRef(raw);
    if (ref.isNotEmpty) map[ref] = coords;
    final digits = ref.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      map.putIfAbsent('BOX$digits', () => coords);
      map.putIfAbsent(digits, () => coords);
    }
  }

  for (final row in boxRows) {
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) continue;
    register((row['numero_interno'] ?? '').toString(), coords);
    register((row['codice_box'] ?? '').toString(), coords);
    register((row['nome_box'] ?? '').toString(), coords);
  }
  return map;
}

/// Indice ref MDO → coordinate GPS (matricola_interna, descrizione_mezzo).
Map<String, (double, double)> mdoGpsLookupFromRows(
  Iterable<Map<String, dynamic>> mdoRows,
) {
  final map = <String, (double, double)>{};

  void register(String raw, (double, double) coords) {
    final ref = extractLogisticaUbicazioneRef(raw);
    if (ref.isNotEmpty) map[ref] = coords;
  }

  for (final row in mdoRows) {
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) continue;
    register((row['matricola_interna'] ?? '').toString(), coords);
    register((row['descrizione_mezzo'] ?? '').toString(), coords);
  }
  return map;
}

/// Risultato risoluzione GPS da anagrafica o ubicazione collegata.
class LogisticaGpsResolution {
  const LogisticaGpsResolution({this.coords, this.inheritedFrom = ''});

  final (double, double)? coords;
  /// es. «BOX03», «A76» — vuoto se coordinate proprie o assenti.
  final String inheritedFrom;

  bool get isInherited => inheritedFrom.isNotEmpty;
}

(double, double)? _lookupBoxGpsRef(
  String ref,
  Map<String, (double, double)> boxGpsByRef,
) {
  final hit = boxGpsByRef[ref];
  if (hit != null) return hit;

  if (RegExp(r'^\d+$').hasMatch(ref)) {
    return boxGpsByRef['BOX$ref'];
  }

  final uff = RegExp(r'^UFF(\d+)$', caseSensitive: false).firstMatch(ref);
  if (uff != null) {
    final digits = uff.group(1)!;
    return boxGpsByRef['BOX$digits'] ?? boxGpsByRef[digits];
  }

  return null;
}

String _inheritanceLabelForRef(
  String ref,
  Map<String, (double, double)> boxGpsByRef,
) {
  if (_lookupBoxGpsRef(ref, boxGpsByRef) == null) return ref;

  final uff = RegExp(r'^UFF(\d+)$', caseSensitive: false).firstMatch(ref);
  if (uff != null) return 'BOX${uff.group(1)!}';

  if (RegExp(r'^\d+$').hasMatch(ref)) return 'BOX$ref';
  return ref;
}

(double, double)? _lookupMdoGpsRef(
  String ref,
  Map<String, (double, double)> mdoGpsByRef,
) {
  final hit = mdoGpsByRef[ref];
  if (hit != null) return hit;

  if (RegExp(r'^A\d+$', caseSensitive: false).hasMatch(ref)) {
    return mdoGpsByRef[ref.toUpperCase()];
  }
  return null;
}

/// Coordinate proprie, oppure ereditate da BOX/UFF o MDO in ubicazione.
LogisticaGpsResolution resolveLogisticaItemGps(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) {
  final own = mdoGpsCoordsFromRow(row);
  if (own != null) {
    return LogisticaGpsResolution(coords: own);
  }

  final ref =
      extractLogisticaUbicazioneRef((row['ubicazione'] ?? '').toString());
  if (ref.isEmpty) return const LogisticaGpsResolution();

  final boxHit = _lookupBoxGpsRef(ref, boxGpsByRef);
  if (boxHit != null) {
    return LogisticaGpsResolution(
      coords: boxHit,
      inheritedFrom: _inheritanceLabelForRef(ref, boxGpsByRef),
    );
  }

  final mdoHit = _lookupMdoGpsRef(ref, mdoGpsByRef);
  if (mdoHit != null) {
    return LogisticaGpsResolution(coords: mdoHit, inheritedFrom: ref);
  }

  return const LogisticaGpsResolution();
}

/// Coordinate proprie dell'estintore/casetta, oppure ereditate da ubicazione.
(double, double)? logisticaItemGpsCoords(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) =>
    resolveLogisticaItemGps(
      row,
      boxGpsByRef,
      mdoGpsByRef: mdoGpsByRef,
    ).coords;

/// Coordinate proprie dell'estintore, oppure ereditate dal BOX/MDO in ubicazione.
(double, double)? estintoreGpsCoords(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) =>
    logisticaItemGpsCoords(
      row,
      boxGpsByRef,
      mdoGpsByRef: mdoGpsByRef,
    );

/// Coordinate proprie della casetta P.S., oppure ereditate da BOX/UFF/MDO.
(double, double)? casettaPsGpsCoords(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) =>
    logisticaItemGpsCoords(
      row,
      boxGpsByRef,
      mdoGpsByRef: mdoGpsByRef,
    );

bool estintoreGpsInheritedFromBox(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) {
  return resolveLogisticaItemGps(
    row,
    boxGpsByRef,
    mdoGpsByRef: mdoGpsByRef,
  ).isInherited;
}

bool casettaPsGpsInherited(
  Map<String, dynamic> row,
  Map<String, (double, double)> boxGpsByRef, {
  Map<String, (double, double)> mdoGpsByRef = const {},
}) {
  return resolveLogisticaItemGps(
    row,
    boxGpsByRef,
    mdoGpsByRef: mdoGpsByRef,
  ).isInherited;
}
