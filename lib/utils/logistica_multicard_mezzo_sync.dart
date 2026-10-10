import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_asset_storico_service.dart';

final RegExp _multicardNumberRe = RegExp(r'710\d{12,16}');

/// Valore di `mezzo_targa` per carta del parco MDO (non legata a un mezzo).
const String kMulticardAssegnazioneMdo = 'MDO';

/// Chiave UI dropdown: nessuna assegnazione (non usare stringa vuota come value).
const String kMulticardAssegnazioneNessuna = '__none__';

bool isMulticardMdoAssignment(String? mezzoTarga) =>
    (mezzoTarga ?? '').trim().toUpperCase() == kMulticardAssegnazioneMdo;

bool isMulticardVehicleAssignment(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  return t.isNotEmpty &&
      t != kMulticardAssegnazioneNessuna &&
      !isMulticardMdoAssignment(t);
}

/// Targa confrontabile (HB696XG == hb 696 xg).
String normalizeMezzoTargaKey(String? targa) =>
    (targa ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

String multicardAssegnazioneKeyFromTarga(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  if (t.isEmpty || t == kMulticardAssegnazioneNessuna) {
    return kMulticardAssegnazioneNessuna;
  }
  if (isMulticardMdoAssignment(t)) return kMulticardAssegnazioneMdo;
  return t;
}

/// Valore da salvare in `logistica_multicard.mezzo_targa` (NOT NULL: mai `null`).
String mezzoTargaFromAssegnazioneKey(String key) {
  final k = key.trim();
  if (k.isEmpty || k == kMulticardAssegnazioneNessuna) return '';
  if (isMulticardMdoAssignment(k)) return kMulticardAssegnazioneMdo;
  return k;
}

String labelMulticardAssegnazione(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  if (t.isEmpty || t == kMulticardAssegnazioneNessuna) {
    return 'Nessuna assegnazione';
  }
  if (isMulticardMdoAssignment(t)) return 'MDO';
  return t;
}

/// Ricalcola `logistica_mezzi_stradali.multicard` dalle carte assegnate a quella targa.
Future<void> refreshMezzoMulticardField({
  required SupabaseClient supa,
  required String targa,
}) async {
  final t = targa.trim();
  if (!isMulticardVehicleAssignment(t)) return;
  final key = normalizeMezzoTargaKey(t);
  if (key.isEmpty) return;
  final rows = await fetchMulticardRowsForTarga(supa, t);
  final nums = <String>[];
  for (final r in rows) {
    final n = (r['multicard'] ?? '').toString().trim();
    if (n.isNotEmpty && !nums.contains(n)) nums.add(n);
  }
  final value = nums.isEmpty ? null : nums.join(' ');
  try {
    final mezzi = await supa
        .from('logistica_mezzi_stradali')
        .select('id_uuid,targa');
    for (final e in (mezzi as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      if (normalizeMezzoTargaKey((m['targa'] ?? '').toString()) != key) {
        continue;
      }
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      await supa
          .from('logistica_mezzi_stradali')
          .update({'multicard': value}).eq('id_uuid', id);
    }
  } catch (_) {}
}

/// Mostra in Mezzi stradali le carte assegnate in Gestione Multicard (fonte).
void applyGestioneMulticardOntoMezziRows({
  required List<Map<String, dynamic>> mezzi,
  required List<Map<String, dynamic>> multicardRows,
}) {
  final byTarga = <String, List<String>>{};
  for (final c in multicardRows) {
    final rawTarga = (c['mezzo_targa'] ?? '').toString();
    if (!isMulticardVehicleAssignment(rawTarga)) continue;
    final key = normalizeMezzoTargaKey(rawTarga);
    if (key.isEmpty) continue;
    final n = (c['multicard'] ?? '').toString().trim();
    if (n.isEmpty) continue;
    final list = byTarga.putIfAbsent(key, () => <String>[]);
    if (!list.contains(n)) list.add(n);
  }
  for (final m in mezzi) {
    final key = normalizeMezzoTargaKey((m['targa'] ?? '').toString());
    final nums = byTarga[key];
    m['multicard'] = (nums == null || nums.isEmpty) ? '' : nums.join(' ');
  }
}

/// Chiave confronto numero multicard (ignora spazi e punti finali).
String normalizeMulticardKey(String value) =>
    value.trim().replaceAll(RegExp(r'[.\s]+$'), '');

bool multicardKeysEqual(String? a, String? b) =>
    normalizeMulticardKey(a ?? '') == normalizeMulticardKey(b ?? '');

/// Estrae tutti i numeri multicard (710…) dal testo libero del campo mezzo.
List<String> extractMulticardNumbers(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const [];
  final out = <String>[];
  for (final m in _multicardNumberRe.allMatches(text)) {
    final k = m.group(0)!;
    if (!out.contains(k)) out.add(k);
  }
  return out;
}

/// Numero “attivo” nel campo mezzo (es. ultimo citato dopo note tipo smarrimento).
String? primaryMulticardNumber(String? raw) {
  final nums = extractMulticardNumbers(raw);
  if (nums.isEmpty) return null;
  final trimmed = (raw ?? '').trim();
  final normalized = normalizeMulticardKey(trimmed);
  if (nums.length == 1) return nums.first;
  if (nums.contains(normalized)) return normalized;
  return nums.last;
}

Map<String, dynamic> assigneePayloadFromMezzo({
  String? assegnatarioAttuale,
  String? assegnatarioUserUuid,
  String? periodoAssegnatarioAttuale,
  String? dataFineAssegnatarioAttuale,
}) {
  final name = (assegnatarioAttuale ?? '').trim();
  final uuid = (assegnatarioUserUuid ?? '').trim();
  final inizio = (periodoAssegnatarioAttuale ?? '').trim();
  final fine = (dataFineAssegnatarioAttuale ?? '').trim();
  return {
    'assegnatario_attuale': name.isEmpty ? null : name,
    'assegnatario_user_uuid': uuid.isEmpty ? null : uuid,
    'periodo_assegnatario_attuale': inizio.isEmpty ? null : inizio,
    'data_fine_assegnatario_attuale': fine.isEmpty ? null : fine,
  };
}

int _mezzoCardLinkScore(Map<String, dynamic> mezzo, String cardKey) {
  final raw = (mezzo['multicard'] ?? '').toString().trim();
  final nums = extractMulticardNumbers(raw);
  if (!nums.contains(cardKey)) return -1;
  final normalized = normalizeMulticardKey(raw);
  if (normalized == cardKey) return 10;
  if (primaryMulticardNumber(raw) == cardKey) return 5;
  return 1;
}

/// Mezzo che detiene la multicard (per numero carta, non solo targa salvata).
Map<String, dynamic>? findMezzoForMulticardKey(
  String cardKey,
  Iterable<Map<String, dynamic>> mezzi, {
  String? fallbackTarga,
}) {
  final key = normalizeMulticardKey(cardKey);
  if (key.isEmpty) return null;

  Map<String, dynamic>? best;
  var bestScore = -1;
  for (final m in mezzi) {
    final score = _mezzoCardLinkScore(m, key);
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  if (best != null) return best;

  final t = (fallbackTarga ?? '').trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final m in mezzi) {
    if ((m['targa'] ?? '').toString().trim().toLowerCase() == t) return m;
  }
  return null;
}

Future<List<Map<String, dynamic>>> fetchMulticardRowsForTarga(
  SupabaseClient supa,
  String targa,
) async {
  final key = normalizeMezzoTargaKey(targa);
  if (key.isEmpty) return const [];
  try {
    final rows = await supa.from('logistica_multicard').select();
    return List<Map<String, dynamic>>.from(
      (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
    )
        .where((r) {
          final mt = (r['mezzo_targa'] ?? '').toString();
          return isMulticardVehicleAssignment(mt) &&
              normalizeMezzoTargaKey(mt) == key;
        })
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<List<Map<String, dynamic>>> fetchMulticardRowsForKey(
  SupabaseClient supa,
  String cardKey, {
  List<Map<String, dynamic>>? cachedRows,
}) async {
  final key = normalizeMulticardKey(cardKey);
  if (key.isEmpty) return const [];
  try {
    final rows = cachedRows ??
        List<Map<String, dynamic>>.from(
          ((await supa.from('logistica_multicard').select()) as List)
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
    return rows
        .where(
          (r) => normalizeMulticardKey((r['multicard'] ?? '').toString()) == key,
        )
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<void> _archiveMulticardIfAssigneeChanges({
  required SupabaseClient supa,
  required Map<String, dynamic> previousRow,
  required LogisticaAssigneeSnapshot next,
  required String mezzoTarga,
  String? mezzoIdUuid,
  String? note,
}) async {
  final mc = (previousRow['multicard'] ?? '').toString().trim();
  if (mc.isEmpty) return;
  final prev = LogisticaAssigneeSnapshot.fromMulticardRow(previousRow);
  if (!LogisticaAssetStoricoService.assigneeChanged(prev, next)) return;
  if (!prev.hasAssignee) return;
  await LogisticaAssetStoricoService.archiveAssigneeChange(
    supa: supa,
    tipoAsset: LogisticaAssetStoricoService.tipoMulticard,
    identificativo: mc,
    previous: prev,
    mezzoTarga: mezzoTarga,
    mezzoIdUuid: mezzoIdUuid,
    note: note,
  );
}

Future<void> _applyAssigneeToMulticardRows({
  required SupabaseClient supa,
  required List<Map<String, dynamic>> rows,
  required Map<String, dynamic> assignee,
  required String mezzoTarga,
  required LogisticaAssigneeSnapshot nextSnap,
  String? mezzoIdUuid,
  String? note,
}) async {
  final targa = mezzoTarga.trim();
  if (rows.isEmpty || targa.isEmpty) return;

  final seen = <String>{};
  for (final row in rows) {
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty || seen.contains(id)) continue;
    seen.add(id);
    await _archiveMulticardIfAssigneeChanges(
      supa: supa,
      previousRow: row,
      next: nextSnap,
      mezzoTarga: targa,
      mezzoIdUuid: mezzoIdUuid,
      note: note,
    );
  }

  final patch = <String, dynamic>{
    ...assignee,
    'mezzo_targa': targa,
  };
  try {
    for (final id in seen) {
      await supa.from('logistica_multicard').update(patch).eq('id_uuid', id);
    }
  } catch (_) {}
}

/// Dopo salvataggio su Mezzi Stradali: crea o aggiorna riga in Gestione Multicard.
/// Restituisce `id_uuid` della multicard sincronizzata, se disponibile.
Future<String?> syncMulticardFromMezzo({
  required SupabaseClient supa,
  String? targa,
  String? multicard,
  String? assegnatarioAttuale,
  String? assegnatarioUserUuid,
  String? periodoAssegnatarioAttuale,
  String? dataFineAssegnatarioAttuale,
  String? mezzoIdUuid,
  String? note,
}) async {
  final mcRaw = (multicard ?? '').trim();
  final t = (targa ?? '').trim();
  if (t.isEmpty) return null;

  final nextSnap = LogisticaAssigneeSnapshot(
    name: (assegnatarioAttuale ?? '').trim().isEmpty
        ? null
        : (assegnatarioAttuale ?? '').trim(),
    userUuid: (assegnatarioUserUuid ?? '').trim().isEmpty
        ? null
        : (assegnatarioUserUuid ?? '').trim(),
    dataInizioIso: (periodoAssegnatarioAttuale ?? '').trim().isEmpty
        ? null
        : (periodoAssegnatarioAttuale ?? '').trim(),
    dataFineIso: (dataFineAssegnatarioAttuale ?? '').trim().isEmpty
        ? null
        : (dataFineAssegnatarioAttuale ?? '').trim(),
  );
  final assignee = assigneePayloadFromMezzo(
    assegnatarioAttuale: assegnatarioAttuale,
    assegnatarioUserUuid: assegnatarioUserUuid,
    periodoAssegnatarioAttuale: periodoAssegnatarioAttuale,
    dataFineAssegnatarioAttuale: dataFineAssegnatarioAttuale,
  );

  final cardKeys = <String>[...extractMulticardNumbers(mcRaw)];
  final primary = primaryMulticardNumber(mcRaw);
  if (primary != null && !cardKeys.contains(primary)) {
    cardKeys.add(primary);
  }
  if (cardKeys.isEmpty) {
    final solo = normalizeMulticardKey(mcRaw);
    if (_multicardNumberRe.hasMatch(solo)) cardKeys.add(solo);
  }

  String? firstId;
  final allRowsCache = await supa.from('logistica_multicard').select();
  final cached = List<Map<String, dynamic>>.from(
    (allRowsCache as List).map((e) => Map<String, dynamic>.from(e as Map)),
  );

  if (cardKeys.isNotEmpty) {
    final byId = <String, Map<String, dynamic>>{};
    for (final key in cardKeys) {
      for (final row in await fetchMulticardRowsForKey(
        supa,
        key,
        cachedRows: cached,
      )) {
        final id = (row['id_uuid'] ?? '').toString().trim();
        if (id.isNotEmpty) byId[id] = row;
      }
    }
    if (byId.isNotEmpty) {
      await _applyAssigneeToMulticardRows(
        supa: supa,
        rows: byId.values.toList(growable: false),
        assignee: assignee,
        mezzoTarga: t,
        nextSnap: nextSnap,
        mezzoIdUuid: mezzoIdUuid,
        note: note,
      );
      firstId = byId.keys.first;
    }
  }

  final linkedByTarga = await fetchMulticardRowsForTarga(supa, t);
  if (linkedByTarga.isNotEmpty) {
    await _applyAssigneeToMulticardRows(
      supa: supa,
      rows: linkedByTarga,
      assignee: assignee,
      mezzoTarga: t,
      nextSnap: nextSnap,
      mezzoIdUuid: mezzoIdUuid,
      note: note,
    );
    firstId ??= (linkedByTarga.first['id_uuid'] ?? '').toString().trim();
  }

  if (cardKeys.isEmpty) return firstId;

  final primaryKey = primary ?? cardKeys.last;
  final existing = await fetchMulticardRowsForKey(
    supa,
    primaryKey,
    cachedRows: cached,
  );
  if (existing.isNotEmpty) {
    return (existing.first['id_uuid'] ?? '').toString().trim();
  }

  final payload = <String, dynamic>{
    ...assignee,
    'multicard': mcRaw.contains('710') && primaryKey.isNotEmpty
        ? '$primaryKey.'
        : (mcRaw.isEmpty ? '$primaryKey.' : mcRaw),
    'mezzo_targa': t,
  };

  try {
    final inserted = await supa
        .from('logistica_multicard')
        .insert(payload)
        .select('id_uuid')
        .single();
    return (inserted['id_uuid'] ?? '').toString().trim();
  } catch (_) {
    return firstId;
  }
}

/// Allinea multicard collegate ai mezzi (per numero carta e/o targa).
Future<int> syncMulticardAssigneesFromMezzi({
  required SupabaseClient supa,
  required List<Map<String, dynamic>> multicardRows,
  required Map<String, Map<String, dynamic>> mezzoByTargaLower,
}) async {
  final mezzi = mezzoByTargaLower.values.toList(growable: false);
  var updated = 0;

  for (final r in multicardRows) {
    final cardKey =
        normalizeMulticardKey((r['multicard'] ?? '').toString());
    if (cardKey.isEmpty) continue;

    final mezzo = findMezzoForMulticardKey(
      cardKey,
      mezzi,
      fallbackTarga: (r['mezzo_targa'] ?? '').toString(),
    );
    if (mezzo == null) continue;

    final mezzoSnap = LogisticaAssigneeSnapshot.fromMezzoRow(mezzo);
    if (!mezzoSnap.hasAssignee) continue;

    final cardSnap = LogisticaAssigneeSnapshot.fromMulticardRow(r);
    final mezzoTarga = (mezzo['targa'] ?? '').toString().trim();
    final cardTarga = (r['mezzo_targa'] ?? '').toString().trim();
    final targaDiffers = mezzoTarga.toLowerCase() != cardTarga.toLowerCase();
    final assigneeDiffers =
        LogisticaAssetStoricoService.assigneeChanged(cardSnap, mezzoSnap);
    final periodDiffers =
        (cardSnap.dataInizioIso ?? '') != (mezzoSnap.dataInizioIso ?? '') ||
            (cardSnap.dataFineIso ?? '') != (mezzoSnap.dataFineIso ?? '');
    if (!assigneeDiffers && !periodDiffers && !targaDiffers) continue;

    final patch = assigneePayloadFromMezzo(
      assegnatarioAttuale: mezzoSnap.name,
      assegnatarioUserUuid: mezzoSnap.userUuid,
      periodoAssegnatarioAttuale: mezzoSnap.dataInizioIso,
      dataFineAssegnatarioAttuale: mezzoSnap.dataFineIso,
    );
    if (mezzoTarga.isNotEmpty) patch['mezzo_targa'] = mezzoTarga;

    try {
      await supa
          .from('logistica_multicard')
          .update(patch)
          .eq('id_uuid', r['id_uuid']);
      r
        ..['assegnatario_attuale'] = patch['assegnatario_attuale']
        ..['assegnatario_user_uuid'] = patch['assegnatario_user_uuid']
        ..['periodo_assegnatario_attuale'] = patch['periodo_assegnatario_attuale']
        ..['data_fine_assegnatario_attuale'] =
            patch['data_fine_assegnatario_attuale'];
      if (patch.containsKey('mezzo_targa')) {
        r['mezzo_targa'] = patch['mezzo_targa'];
      }
      updated++;
    } catch (_) {}
  }
  return updated;
}

/// Dopo salvataggio su Gestione Multicard: allinea mezzo (targa) con multicard.
Future<void> syncMezzoFromMulticard({
  required SupabaseClient supa,
  required String targa,
  String? multicard,
  String? assegnatarioAttuale,
  String? assegnatarioUserUuid,
  String? periodoAssegnatarioAttuale,
  String? dataFineAssegnatarioAttuale,
}) async {
  final t = targa.trim();
  if (!isMulticardVehicleAssignment(t)) return;
  final payload = assigneePayloadFromMezzo(
    assegnatarioAttuale: assegnatarioAttuale,
    assegnatarioUserUuid: assegnatarioUserUuid,
    periodoAssegnatarioAttuale: periodoAssegnatarioAttuale,
    dataFineAssegnatarioAttuale: dataFineAssegnatarioAttuale,
  );
  final mc = primaryMulticardNumber(multicard) ?? normalizeMulticardKey(multicard ?? '');
  if (mc.isNotEmpty) payload['multicard'] = '$mc.';
  try {
    await supa
        .from('logistica_mezzi_stradali')
        .update(payload)
        .ilike('targa', t);
  } catch (_) {
    try {
      final mezzi = await supa
          .from('logistica_mezzi_stradali')
          .select('id_uuid,targa');
      final key = normalizeMezzoTargaKey(t);
      for (final e in (mezzi as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        if (normalizeMezzoTargaKey((m['targa'] ?? '').toString()) != key) {
          continue;
        }
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        await supa
            .from('logistica_mezzi_stradali')
            .update(payload)
            .eq('id_uuid', id);
      }
    } catch (_) {}
  }
}
