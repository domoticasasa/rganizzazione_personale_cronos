import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logistica_ubicazione_ref.dart';
import '../utils/mdo_gps_coords.dart';

/// Ref ubicazione collegata a BOX/CON (tabella logistica_box) o MDO Axx.
bool isUbicazioneLinkedRef(String ref) {
  final u = ref.trim().toUpperCase();
  if (u.isEmpty) return false;
  return RegExp(r'^(BOX|CON)\d+$').hasMatch(u) ||
      RegExp(r'^A\d+$').hasMatch(u);
}

/// Solo BOX numerico (retrocompatibilità test).
bool isBoxUbicazioneRef(String ref) {
  final u = ref.trim().toUpperCase();
  return RegExp(r'^BOX\d+$').hasMatch(u);
}

bool isLogisticaBoxTableRef(String ref) {
  final u = ref.trim().toUpperCase();
  return RegExp(r'^(BOX|CON)\d+$').hasMatch(u);
}

bool isMdoUbicazioneRef(String ref) {
  final u = ref.trim().toUpperCase();
  return RegExp(r'^A\d+$').hasMatch(u);
}

String normalizeCommessaLookupKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Risolve `commessa_id` da testo commessa/cantiere (come nelle pagine admin).
String? findCommessaIdByText(
  String rawValue,
  Map<String, String> commesseById,
) {
  final raw = rawValue.trim();
  if (raw.isEmpty) return null;
  final target = normalizeCommessaLookupKey(raw);
  if (target.isEmpty) return null;

  String? containsMatch;
  for (final entry in commesseById.entries) {
    final normalizedName = normalizeCommessaLookupKey(entry.value);
    if (normalizedName.isEmpty) continue;
    if (normalizedName == target) return entry.key;
    if (normalizedName.contains(target) || target.contains(normalizedName)) {
      containsMatch ??= entry.key;
    }
  }
  if (containsMatch != null) return containsMatch;

  final firstToken = raw.split(RegExp(r'[\s\-/]+')).first.trim();
  if (firstToken.isEmpty) return null;
  final token = normalizeCommessaLookupKey(firstToken);
  if (token.isEmpty) return null;
  for (final entry in commesseById.entries) {
    final normalizedName = normalizeCommessaLookupKey(entry.value);
    if (normalizedName.startsWith(token) || normalizedName.contains(token)) {
      return entry.key;
    }
  }
  return null;
}

Future<Map<String, String>> loadActiveCommesseById(SupabaseClient supa) async {
  final res = await supa
      .from('commesse')
      .select('id_uuid,nome,active')
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

Set<String> logisticaBoxRefsFromRow(Map<String, dynamic> boxRow) {
  final refs = <String>{};
  for (final key in ['numero_interno', 'codice_box', 'nome_box']) {
    final ref = extractLogisticaUbicazioneRef((boxRow[key] ?? '').toString());
    if (ref.isNotEmpty && isLogisticaBoxTableRef(ref)) refs.add(ref);
  }
  return refs;
}

@Deprecated('Usa logisticaBoxRefsFromRow')
Set<String> boxUbicazioneRefsFromRow(Map<String, dynamic> boxRow) =>
    logisticaBoxRefsFromRow(boxRow);

Set<String> mdoUbicazioneRefsFromRow(Map<String, dynamic> mdoRow) {
  final refs = <String>{};
  for (final key in ['matricola_interna', 'descrizione_mezzo']) {
    final ref = extractLogisticaUbicazioneRef((mdoRow[key] ?? '').toString());
    if (ref.isNotEmpty && isMdoUbicazioneRef(ref)) refs.add(ref);
  }
  return refs;
}

/// Ref per abbinare estintori/cassette al mezzo (targa / numerazione).
Set<String> mezziStradaliUbicazioneRefsFromRow(Map<String, dynamic> row) {
  final refs = <String>{};
  void addRaw(String raw) {
    final compact =
        raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.isNotEmpty) refs.add(compact);
    final token = extractLogisticaUbicazioneRef(raw);
    if (token.isNotEmpty) refs.add(token);
  }

  addRaw((row['targa'] ?? '').toString());
  addRaw((row['numerazione'] ?? '').toString());
  return refs;
}

Map<String, dynamic> _gpsFieldsFromRow(Map<String, dynamic> row) {
  final payload = <String, dynamic>{};
  final coords = mdoGpsCoordsFromRow(row);
  if (coords != null) {
    payload['latitudine'] = coords.$1;
    payload['longitudine'] = coords.$2;
    final gpsText = (row['posizione_gps'] ?? '').toString().trim();
    payload['posizione_gps'] = gpsText.isNotEmpty
        ? gpsText
        : formatGpsCoordsText(coords.$1, coords.$2);
  } else {
    final gpsText = (row['posizione_gps'] ?? '').toString().trim();
    if (gpsText.isNotEmpty) payload['posizione_gps'] = gpsText;
    payload['latitudine'] = null;
    payload['longitudine'] = null;
  }
  return payload;
}

Map<String, dynamic> linkedAssetFieldsFromLogisticaBoxRow(
  Map<String, dynamic> boxRow,
) {
  final payload = _gpsFieldsFromRow(boxRow);
  final commessaId = (boxRow['commessa_id'] ?? '').toString().trim();
  if (commessaId.isNotEmpty) payload['commessa_id'] = commessaId;
  return payload;
}

@Deprecated('Usa linkedAssetFieldsFromLogisticaBoxRow')
Map<String, dynamic> linkedAssetFieldsFromBox(Map<String, dynamic> boxRow) =>
    linkedAssetFieldsFromLogisticaBoxRow(boxRow);

Map<String, dynamic> linkedAssetFieldsFromMdoRow(
  Map<String, dynamic> mdoRow,
  Map<String, String> commesseById,
) {
  final payload = _gpsFieldsFromRow(mdoRow);
  final commessaRaw = (mdoRow['commessa'] ?? '').toString().trim();
  final commessaId = commessaRaw.isNotEmpty
      ? findCommessaIdByText(commessaRaw, commesseById)
      : null;
  final resolved = commessaId ??
      findCommessaIdByText(
        (mdoRow['cantiere_attuale'] ?? '').toString(),
        commesseById,
      );
  if (resolved != null && resolved.isNotEmpty) {
    payload['commessa_id'] = resolved;
  }
  return payload;
}

Map<String, Map<String, dynamic>> logisticaBoxRefLinkedFieldsIndex(
  Iterable<Map<String, dynamic>> boxRows,
) {
  final map = <String, Map<String, dynamic>>{};
  for (final box in boxRows) {
    final fields = linkedAssetFieldsFromLogisticaBoxRow(box);
    if (fields.isEmpty) continue;
    for (final ref in logisticaBoxRefsFromRow(box)) {
      map[ref] = fields;
    }
  }
  return map;
}

@Deprecated('Usa logisticaBoxRefLinkedFieldsIndex')
Map<String, Map<String, dynamic>> boxRefLinkedFieldsIndex(
  Iterable<Map<String, dynamic>> boxRows,
) =>
    logisticaBoxRefLinkedFieldsIndex(boxRows);

Map<String, Map<String, dynamic>> mdoRefLinkedFieldsIndex(
  Iterable<Map<String, dynamic>> mdoRows,
  Map<String, String> commesseById,
) {
  final map = <String, Map<String, dynamic>>{};
  for (final mdo in mdoRows) {
    final fields = linkedAssetFieldsFromMdoRow(mdo, commesseById);
    if (fields.isEmpty) continue;
    for (final ref in mdoUbicazioneRefsFromRow(mdo)) {
      map[ref] = fields;
    }
  }
  return map;
}

Map<String, Map<String, dynamic>> buildUbicazioneRefLinkedFieldsIndex({
  required Iterable<Map<String, dynamic>> boxRows,
  required Iterable<Map<String, dynamic>> mdoRows,
  required Map<String, String> commesseById,
}) {
  return <String, Map<String, dynamic>>{
    ...logisticaBoxRefLinkedFieldsIndex(boxRows),
    ...mdoRefLinkedFieldsIndex(mdoRows, commesseById),
  };
}

bool linkedAssetRowNeedsUbicazioneSync(
  Map<String, dynamic> row,
  Map<String, dynamic> targetFields,
) {
  for (final entry in targetFields.entries) {
    final current = row[entry.key];
    final next = entry.value;
    if (current == null && next == null) continue;
    if (current is num && next is num && current == next) continue;
    if ('$current'.trim() != '$next'.trim()) return true;
  }
  return false;
}

@Deprecated('Usa linkedAssetRowNeedsUbicazioneSync')
bool linkedAssetRowNeedsBoxSync(
  Map<String, dynamic> row,
  Map<String, dynamic> targetFields,
) =>
    linkedAssetRowNeedsUbicazioneSync(row, targetFields);

Future<Map<String, dynamic>?> fetchLogisticaBoxForUbicazione(
  SupabaseClient supa,
  String ubicazioneRaw,
) async {
  final ref = extractLogisticaUbicazioneRef(ubicazioneRaw);
  if (!isLogisticaBoxTableRef(ref)) return null;

  final boxRes = await supa
      .from('logistica_box')
      .select(
        'id_uuid,numero_interno,codice_box,nome_box,commessa_id,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('active', true);

  for (final e in boxRes as List) {
    final m = Map<String, dynamic>.from(e as Map);
    if (logisticaBoxRefsFromRow(m).contains(ref)) return m;
  }
  return null;
}

@Deprecated('Usa fetchLogisticaBoxForUbicazione')
Future<Map<String, dynamic>?> fetchActiveBoxForUbicazione(
  SupabaseClient supa,
  String ubicazioneRaw,
) =>
    fetchLogisticaBoxForUbicazione(supa, ubicazioneRaw);

Future<Map<String, dynamic>?> fetchMdoForUbicazione(
  SupabaseClient supa,
  String ubicazioneRaw,
) async {
  final ref = extractLogisticaUbicazioneRef(ubicazioneRaw);
  if (!isMdoUbicazioneRef(ref)) return null;

  final mdoRes = await supa
      .from('logistica_mdo_ferroviari')
      .select(
        'id_uuid,matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('active', true);

  for (final e in mdoRes as List) {
    final m = Map<String, dynamic>.from(e as Map);
    if (mdoUbicazioneRefsFromRow(m).contains(ref)) return m;
  }
  return null;
}

Future<Map<String, dynamic>> mergeUbicazioneSyncIntoPayload(
  SupabaseClient supa,
  String ubicazioneRaw,
  Map<String, dynamic> payload, {
  Map<String, String>? commesseById,
}) async {
  final ref = extractLogisticaUbicazioneRef(ubicazioneRaw);
  if (!isUbicazioneLinkedRef(ref)) return payload;

  if (isLogisticaBoxTableRef(ref)) {
    final box = await fetchLogisticaBoxForUbicazione(supa, ubicazioneRaw);
    if (box == null) return payload;
    return <String, dynamic>{
      ...payload,
      ...linkedAssetFieldsFromLogisticaBoxRow(box),
    };
  }

  final mdo = await fetchMdoForUbicazione(supa, ubicazioneRaw);
  if (mdo == null) return payload;
  final commesse =
      commesseById ?? await loadActiveCommesseById(supa);
  return <String, dynamic>{
    ...payload,
    ...linkedAssetFieldsFromMdoRow(mdo, commesse),
  };
}

@Deprecated('Usa mergeUbicazioneSyncIntoPayload')
Future<Map<String, dynamic>> mergeBoxSyncIntoPayload(
  SupabaseClient supa,
  String ubicazioneRaw,
  Map<String, dynamic> payload,
) =>
    mergeUbicazioneSyncIntoPayload(supa, ubicazioneRaw, payload);

class UbicazioneLinkedPropagationResult {
  const UbicazioneLinkedPropagationResult({
    this.estintoriUpdated = 0,
    this.casetteUpdated = 0,
    this.errors = 0,
  });

  final int estintoriUpdated;
  final int casetteUpdated;
  final int errors;

  int get totalUpdated => estintoriUpdated + casetteUpdated;
}

@Deprecated('Usa UbicazioneLinkedPropagationResult')
typedef BoxLinkedPropagationResult = UbicazioneLinkedPropagationResult;

Future<UbicazioneLinkedPropagationResult> _propagateByRefs(
  SupabaseClient supa, {
  required Set<String> sourceRefs,
  required Map<String, dynamic> syncPayload,
}) async {
  if (sourceRefs.isEmpty || syncPayload.isEmpty) {
    return const UbicazioneLinkedPropagationResult();
  }

  var est = 0;
  var cas = 0;
  var err = 0;

  Future<void> syncTable(String table, void Function() onSuccess) async {
    final rows = await supa
        .from(table)
        .select(
          'id_uuid,ubicazione,commessa_id,latitudine,longitudine,posizione_gps',
        )
        .eq('active', true);
    for (final raw in rows as List) {
      final r = Map<String, dynamic>.from(raw as Map);
      final id = (r['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final ref = extractLogisticaUbicazioneRef(
        (r['ubicazione'] ?? '').toString(),
      );
      if (!sourceRefs.contains(ref)) continue;
      if (!linkedAssetRowNeedsUbicazioneSync(r, syncPayload)) continue;
      try {
        await supa.from(table).update(syncPayload).eq('id_uuid', id);
        onSuccess();
      } catch (_) {
        err++;
      }
    }
  }

  await syncTable('estintori', () => est++);
  await syncTable('logistica_casette_ps', () => cas++);

  return UbicazioneLinkedPropagationResult(
    estintoriUpdated: est,
    casetteUpdated: cas,
    errors: err,
  );
}

Future<UbicazioneLinkedPropagationResult> propagateLogisticaBoxUpdateToLinkedAssets(
  SupabaseClient supa,
  Map<String, dynamic> boxRow,
) {
  final refs = logisticaBoxRefsFromRow(boxRow);
  final syncPayload = linkedAssetFieldsFromLogisticaBoxRow(boxRow);
  return _propagateByRefs(supa, sourceRefs: refs, syncPayload: syncPayload);
}

@Deprecated('Usa propagateLogisticaBoxUpdateToLinkedAssets')
Future<UbicazioneLinkedPropagationResult> propagateBoxUpdateToLinkedAssets(
  SupabaseClient supa,
  Map<String, dynamic> boxRow,
) =>
    propagateLogisticaBoxUpdateToLinkedAssets(supa, boxRow);

Future<UbicazioneLinkedPropagationResult> propagateMdoUpdateToLinkedAssets(
  SupabaseClient supa,
  Map<String, dynamic> mdoRow, {
  Map<String, String>? commesseById,
}) async {
  final refs = mdoUbicazioneRefsFromRow(mdoRow);
  final commesse =
      commesseById ?? await loadActiveCommesseById(supa);
  final syncPayload = linkedAssetFieldsFromMdoRow(mdoRow, commesse);
  return _propagateByRefs(supa, sourceRefs: refs, syncPayload: syncPayload);
}

Future<Map<String, dynamic>?> fetchLogisticaBoxRowById(
  SupabaseClient supa,
  String idUuid,
) async {
  if (idUuid.trim().isEmpty) return null;
  final row = await supa
      .from('logistica_box')
      .select(
        'id_uuid,numero_interno,codice_box,nome_box,commessa_id,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('id_uuid', idUuid)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
}

Future<Map<String, dynamic>?> fetchMdoRowById(
  SupabaseClient supa,
  String idUuid,
) async {
  if (idUuid.trim().isEmpty) return null;
  final row = await supa
      .from('logistica_mdo_ferroviari')
      .select(
        'id_uuid,matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('id_uuid', idUuid)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
}

/// Allinea estintori/casette alle sorgenti BOX/CON/MDO (es. all'apertura pagina).
Future<UbicazioneLinkedPropagationResult> syncAllLinkedAssetsFromUbicazioneSources(
  SupabaseClient supa, {
  Map<String, String>? commesseById,
}) async {
  final commesse =
      commesseById ?? await loadActiveCommesseById(supa);

  final boxRes = await supa
      .from('logistica_box')
      .select(
        'numero_interno,codice_box,nome_box,commessa_id,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('active', true);
  final mdoRes = await supa
      .from('logistica_mdo_ferroviari')
      .select(
        'matricola_interna,descrizione_mezzo,cantiere_attuale,commessa,'
        'latitudine,longitudine,posizione_gps,active',
      )
      .eq('active', true);

  final refIndex = buildUbicazioneRefLinkedFieldsIndex(
    boxRows: (boxRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
    mdoRows: (mdoRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
    commesseById: commesse,
  );

  var est = 0;
  var cas = 0;
  var err = 0;

  Future<void> syncTable(String table, void Function() onSuccess) async {
    final rows = await supa
        .from(table)
        .select(
          'id_uuid,ubicazione,commessa_id,latitudine,longitudine,posizione_gps',
        )
        .eq('active', true);
    for (final raw in rows as List) {
      final r = Map<String, dynamic>.from(raw as Map);
      final id = (r['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final ref = extractLogisticaUbicazioneRef(
        (r['ubicazione'] ?? '').toString(),
      );
      if (!isUbicazioneLinkedRef(ref)) continue;
      final target = refIndex[ref];
      if (target == null || target.isEmpty) continue;
      if (!linkedAssetRowNeedsUbicazioneSync(r, target)) continue;
      try {
        await supa.from(table).update(target).eq('id_uuid', id);
        onSuccess();
      } catch (_) {
        err++;
      }
    }
  }

  await syncTable('estintori', () => est++);
  await syncTable('logistica_casette_ps', () => cas++);

  return UbicazioneLinkedPropagationResult(
    estintoriUpdated: est,
    casetteUpdated: cas,
    errors: err,
  );
}

Future<UbicazioneLinkedPropagationResult> propagateLogisticaBoxUpdateById(
  SupabaseClient supa,
  String idUuid,
) async {
  final row = await fetchLogisticaBoxRowById(supa, idUuid);
  if (row == null) return const UbicazioneLinkedPropagationResult();
  return propagateLogisticaBoxUpdateToLinkedAssets(supa, row);
}

Future<UbicazioneLinkedPropagationResult> propagateMdoUpdateById(
  SupabaseClient supa,
  String idUuid, {
  Map<String, String>? commesseById,
}) async {
  final row = await fetchMdoRowById(supa, idUuid);
  if (row == null) return const UbicazioneLinkedPropagationResult();
  return propagateMdoUpdateToLinkedAssets(
    supa,
    row,
    commesseById: commesseById,
  );
}
