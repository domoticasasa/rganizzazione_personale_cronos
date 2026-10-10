import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_asset_storico_service.dart';
import 'logistica_multicard_mezzo_sync.dart';

const String kTelepassAssegnazioneNessuna = kMulticardAssegnazioneNessuna;

bool isTelepassVehicleAssignment(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  return t.isNotEmpty && t != kTelepassAssegnazioneNessuna;
}

String telepassAssegnazioneKeyFromTarga(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  if (t.isEmpty || t == kTelepassAssegnazioneNessuna) {
    return kTelepassAssegnazioneNessuna;
  }
  return t;
}

String mezzoTargaFromTelepassAssegnazioneKey(String key) {
  final k = key.trim();
  if (k.isEmpty || k == kTelepassAssegnazioneNessuna) return '';
  return k;
}

String labelTelepassAssegnazione(String? mezzoTarga) {
  final t = (mezzoTarga ?? '').trim();
  if (t.isEmpty || t == kTelepassAssegnazioneNessuna) {
    return 'Nessuna assegnazione';
  }
  return t;
}

/// Ricalcola `logistica_mezzi_stradali.telepass` dalle carte assegnate a quella targa.
Future<void> refreshMezzoTelepassField({
  required SupabaseClient supa,
  required String targa,
}) async {
  final t = targa.trim();
  if (!isTelepassVehicleAssignment(t)) return;
  final rows = await fetchTelepassRowsForTarga(supa, t);
  final nums = <String>[];
  for (final r in rows) {
    final n = (r['telepass'] ?? '').toString().trim();
    if (n.isNotEmpty && !isTelepassValueEmpty(n) && !nums.contains(n)) {
      nums.add(n);
    }
  }
  try {
    await supa.from('logistica_mezzi_stradali').update({
      'telepass': nums.isEmpty ? null : nums.join(' '),
    }).ilike('targa', t);
  } catch (_) {}
}

/// Chiave confronto Telepass (case-insensitive).
String normalizeTelepassKey(String value) => value.trim().toLowerCase();

bool telepassKeysEqual(String? a, String? b) =>
    normalizeTelepassKey(a ?? '') == normalizeTelepassKey(b ?? '');

bool isTelepassValueEmpty(String? raw) =>
    LogisticaAssetStoricoService.isTelepassVuoto(raw);

Map<String, dynamic>? findMezzoForTelepassKey(
  String telepassKey,
  Iterable<Map<String, dynamic>> mezzi, {
  String? fallbackTarga,
}) {
  final key = normalizeTelepassKey(telepassKey);
  if (key.isEmpty || isTelepassValueEmpty(telepassKey)) return null;

  for (final m in mezzi) {
    final tp = (m['telepass'] ?? '').toString().trim();
    if (!isTelepassValueEmpty(tp) &&
        normalizeTelepassKey(tp) == key) {
      return m;
    }
  }

  final t = (fallbackTarga ?? '').trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final m in mezzi) {
    if ((m['targa'] ?? '').toString().trim().toLowerCase() == t) return m;
  }
  return null;
}

Future<List<Map<String, dynamic>>> fetchTelepassRowsForTarga(
  SupabaseClient supa,
  String targa,
) async {
  final t = targa.trim();
  if (t.isEmpty) return const [];
  try {
    final rows = await supa
        .from('logistica_telepass')
        .select()
        .ilike('mezzo_targa', t);
    return List<Map<String, dynamic>>.from(
      (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  } catch (_) {
    return const [];
  }
}

Future<List<Map<String, dynamic>>> fetchTelepassRowsForKey(
  SupabaseClient supa,
  String telepassKey, {
  List<Map<String, dynamic>>? cachedRows,
}) async {
  final key = normalizeTelepassKey(telepassKey);
  if (key.isEmpty || isTelepassValueEmpty(telepassKey)) return const [];
  try {
    final rows = cachedRows ??
        List<Map<String, dynamic>>.from(
          ((await supa.from('logistica_telepass').select()) as List)
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
    return rows
        .where(
          (r) =>
              normalizeTelepassKey((r['telepass'] ?? '').toString()) == key,
        )
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<void> _archiveTelepassIfAssigneeChanges({
  required SupabaseClient supa,
  required Map<String, dynamic> previousRow,
  required LogisticaAssigneeSnapshot next,
  required String mezzoTarga,
  String? mezzoIdUuid,
  String? note,
}) async {
  final tp = (previousRow['telepass'] ?? '').toString().trim();
  if (tp.isEmpty || isTelepassValueEmpty(tp)) return;
  final prev = LogisticaAssigneeSnapshot.fromTelepassRow(previousRow);
  if (!LogisticaAssetStoricoService.assigneeChanged(prev, next)) return;
  if (!prev.hasAssignee) return;
  await LogisticaAssetStoricoService.archiveAssigneeChange(
    supa: supa,
    tipoAsset: LogisticaAssetStoricoService.tipoTelepass,
    identificativo: tp,
    previous: prev,
    mezzoTarga: mezzoTarga,
    mezzoIdUuid: mezzoIdUuid,
    note: note,
  );
}

Future<void> _applyAssigneeToTelepassRows({
  required SupabaseClient supa,
  required List<Map<String, dynamic>> rows,
  required Map<String, dynamic> assignee,
  required String mezzoTarga,
  required LogisticaAssigneeSnapshot nextSnap,
  String? mezzoIdUuid,
  String? note,
  String? telepassValue,
}) async {
  final targa = mezzoTarga.trim();
  if (rows.isEmpty || targa.isEmpty) return;

  final seen = <String>{};
  for (final row in rows) {
    final id = (row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty || seen.contains(id)) continue;
    seen.add(id);
    await _archiveTelepassIfAssigneeChanges(
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
  if ((telepassValue ?? '').trim().isNotEmpty &&
      !isTelepassValueEmpty(telepassValue)) {
    patch['telepass'] = telepassValue!.trim();
  }

  try {
    for (final id in seen) {
      await supa.from('logistica_telepass').update(patch).eq('id_uuid', id);
    }
  } catch (_) {}
}

/// Dopo salvataggio su Mezzi Stradali: crea o aggiorna riga Gestione Telepass.
Future<String?> syncTelepassFromMezzo({
  required SupabaseClient supa,
  String? targa,
  String? telepass,
  String? assegnatarioAttuale,
  String? assegnatarioUserUuid,
  String? periodoAssegnatarioAttuale,
  String? dataFineAssegnatarioAttuale,
  String? mezzoIdUuid,
  String? note,
}) async {
  final tpRaw = (telepass ?? '').trim();
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

  final allRowsCache = await supa.from('logistica_telepass').select();
  final cached = List<Map<String, dynamic>>.from(
    (allRowsCache as List).map((e) => Map<String, dynamic>.from(e as Map)),
  );

  String? firstId;
  if (!isTelepassValueEmpty(tpRaw)) {
    final byKey = await fetchTelepassRowsForKey(supa, tpRaw, cachedRows: cached);
    if (byKey.isNotEmpty) {
      await _applyAssigneeToTelepassRows(
        supa: supa,
        rows: byKey,
        assignee: assignee,
        mezzoTarga: t,
        nextSnap: nextSnap,
        mezzoIdUuid: mezzoIdUuid,
        note: note,
        telepassValue: tpRaw,
      );
      firstId = (byKey.first['id_uuid'] ?? '').toString().trim();
    }
  }

  final linkedByTarga = await fetchTelepassRowsForTarga(supa, t);
  if (linkedByTarga.isNotEmpty) {
    await _applyAssigneeToTelepassRows(
      supa: supa,
      rows: linkedByTarga,
      assignee: assignee,
      mezzoTarga: t,
      nextSnap: nextSnap,
      mezzoIdUuid: mezzoIdUuid,
      note: note,
      telepassValue: isTelepassValueEmpty(tpRaw) ? null : tpRaw,
    );
    firstId ??= (linkedByTarga.first['id_uuid'] ?? '').toString().trim();
  }

  if (isTelepassValueEmpty(tpRaw)) return firstId;

  final existing = await fetchTelepassRowsForKey(
    supa,
    tpRaw,
    cachedRows: cached,
  );
  if (existing.isNotEmpty) {
    return (existing.first['id_uuid'] ?? '').toString().trim();
  }

  final payload = <String, dynamic>{
    ...assignee,
    'telepass': tpRaw,
    'mezzo_targa': t,
  };

  try {
    final inserted = await supa
        .from('logistica_telepass')
        .insert(payload)
        .select('id_uuid')
        .single();
    return (inserted['id_uuid'] ?? '').toString().trim();
  } catch (_) {
    return firstId;
  }
}

/// Allinea telepass collegati ai mezzi (per codice e/o targa).
Future<int> syncTelepassAssigneesFromMezzi({
  required SupabaseClient supa,
  required List<Map<String, dynamic>> telepassRows,
  required Map<String, Map<String, dynamic>> mezzoByTargaLower,
}) async {
  final mezzi = mezzoByTargaLower.values.toList(growable: false);
  var updated = 0;

  for (final r in telepassRows) {
    final tpKey = normalizeTelepassKey((r['telepass'] ?? '').toString());
    if (tpKey.isEmpty || isTelepassValueEmpty(r['telepass'])) continue;

    final mezzo = findMezzoForTelepassKey(
      tpKey,
      mezzi,
      fallbackTarga: (r['mezzo_targa'] ?? '').toString(),
    );
    if (mezzo == null) continue;

    final mezzoSnap = LogisticaAssigneeSnapshot.fromMezzoRow(mezzo);
    if (!mezzoSnap.hasAssignee && isTelepassValueEmpty(mezzo['telepass'])) {
      continue;
    }

    final rowSnap = LogisticaAssigneeSnapshot.fromTelepassRow(r);
    final mezzoTarga = (mezzo['targa'] ?? '').toString().trim();
    final rowTarga = (r['mezzo_targa'] ?? '').toString().trim();
    final mezzoTp = (mezzo['telepass'] ?? '').toString().trim();
    final targaDiffers =
        mezzoTarga.toLowerCase() != rowTarga.toLowerCase();
    final telepassDiffers = !isTelepassValueEmpty(mezzoTp) &&
        !telepassKeysEqual(mezzoTp, r['telepass']);
    final assigneeDiffers =
        LogisticaAssetStoricoService.assigneeChanged(rowSnap, mezzoSnap);
    final periodDiffers =
        (rowSnap.dataInizioIso ?? '') != (mezzoSnap.dataInizioIso ?? '') ||
            (rowSnap.dataFineIso ?? '') != (mezzoSnap.dataFineIso ?? '');
    if (!assigneeDiffers && !periodDiffers && !targaDiffers && !telepassDiffers) {
      continue;
    }

    final patch = assigneePayloadFromMezzo(
      assegnatarioAttuale: mezzoSnap.name,
      assegnatarioUserUuid: mezzoSnap.userUuid,
      periodoAssegnatarioAttuale: mezzoSnap.dataInizioIso,
      dataFineAssegnatarioAttuale: mezzoSnap.dataFineIso,
    );
    if (mezzoTarga.isNotEmpty) patch['mezzo_targa'] = mezzoTarga;
    if (!isTelepassValueEmpty(mezzoTp)) patch['telepass'] = mezzoTp;

    try {
      await supa
          .from('logistica_telepass')
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
      if (patch.containsKey('telepass')) {
        r['telepass'] = patch['telepass'];
      }
      updated++;
    } catch (_) {}
  }
  return updated;
}

/// Dopo salvataggio Gestione Telepass: allinea mezzo stradale.
Future<void> syncMezzoFromTelepass({
  required SupabaseClient supa,
  required String targa,
  String? telepass,
  String? assegnatarioAttuale,
  String? assegnatarioUserUuid,
  String? periodoAssegnatarioAttuale,
  String? dataFineAssegnatarioAttuale,
}) async {
  final t = targa.trim();
  if (!isTelepassVehicleAssignment(t)) return;
  final payload = assigneePayloadFromMezzo(
    assegnatarioAttuale: assegnatarioAttuale,
    assegnatarioUserUuid: assegnatarioUserUuid,
    periodoAssegnatarioAttuale: periodoAssegnatarioAttuale,
    dataFineAssegnatarioAttuale: dataFineAssegnatarioAttuale,
  );
  final tp = (telepass ?? '').trim();
  if (!isTelepassValueEmpty(tp)) {
    payload['telepass'] = tp;
  } else {
    payload['telepass'] = null;
  }
  try {
    await supa.from('logistica_mezzi_stradali').update(payload).ilike('targa', t);
  } catch (_) {}
}
