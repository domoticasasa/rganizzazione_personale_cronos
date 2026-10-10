import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'roles.dart';
import 'users_directory.dart';

/// Utente selezionabile come DT: ruolo primario o secondario DT / Assistente DT.
bool userIsDtSelectable(Map<String, dynamic> row) {
  final primary = normalizeRole((row['role'] ?? '').toString());
  final secondaryRaw = (row['secondary_role'] ?? '').toString().trim();
  final secondary =
      secondaryRaw.isEmpty ? '' : normalizeRole(secondaryRaw);
  if (primary == 'dt' || primary == 'assistente_dt') return true;
  if (secondary == 'dt' || secondary == 'assistente_dt') return true;
  return false;
}

String dtUserDisplayLabel(Map<String, dynamic> row) {
  final fn = (row['full_name'] ?? '').toString().trim();
  final un = (row['username'] ?? '').toString().trim();
  final em = (row['email'] ?? '').toString().trim();
  if (fn.isNotEmpty) return fn;
  if (un.isNotEmpty) return un;
  if (em.isNotEmpty) return em;
  final uuid = (row['id_uuid'] ?? '').toString().trim();
  if (uuid.isNotEmpty) return uuid;
  return (row['id'] ?? '').toString().trim();
}

/// Righe `users` per elenchi DT (attivi).
/// Usa RPC security definer così dipendente/user vede anche chi ha DT
/// solo come ruolo secondario (dopo RLS su `users`).
Future<List<Map<String, dynamic>>> loadDtSelectableUserRows({
  bool activeOnly = true,
}) async {
  const selectCols =
      'id, id_uuid, auth_id, full_name, username, email, role, secondary_role, active, hidden_from_directory';

  try {
    final res = await SupabaseService.client.rpc(
      'list_dt_selectable_users',
      params: {'p_active_only': activeOnly},
    );
    final rows = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    return UsersDirectory.onlyVisible(rows.where(userIsDtSelectable));
  } catch (_) {
    // Fallback: select diretto (staff / policy DT directory).
  }

  Future<List<Map<String, dynamic>>> queryWithOr(String orExpr) async {
    var q = SupabaseService.client.from('users').select(selectCols).or(orExpr);
    if (activeOnly) {
      q = q.eq('active', true);
    }
    final res = await q.order('full_name', ascending: true);
    return UsersDirectory.onlyVisible(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  try {
    return await queryWithOr(
      'role.eq.dt,role.eq.assistente_dt,secondary_role.eq.dt,secondary_role.eq.assistente_dt',
    );
  } on PostgrestException catch (e) {
    if (e.code != '42703') rethrow;
    // Schema senza secondary_role / hidden_from_directory: filtra in app.
    var q = SupabaseService.client
        .from('users')
        .select('id, id_uuid, auth_id, full_name, username, email, role, active');
    if (activeOnly) {
      q = q.eq('active', true);
    }
    final res = await q.order('full_name', ascending: true);
    final all = List<Map<String, dynamic>>.from(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return UsersDirectory.onlyVisible(all.where(userIsDtSelectable));
  }
}

/// `id_uuid` → etichetta (elenchi dropdown assistente / richieste).
Future<Map<String, String>> loadDtOptionsByUuid({
  bool activeOnly = true,
}) async {
  final rows = await loadDtSelectableUserRows(activeOnly: activeOnly);
  final map = <String, String>{};
  for (final row in rows) {
    final idUuid = (row['id_uuid'] ?? '').toString().trim();
    if (idUuid.isEmpty) continue;
    final label = dtUserDisplayLabel(row);
    map[idUuid] = label.isNotEmpty ? label : idUuid;
  }
  return map;
}

/// `id_uuid` / `id` / `auth_id` → etichetta (ordinata per nome).
Future<Map<String, String>> loadDtUserLabelMap({
  bool activeOnly = true,
}) async {
  final rows = await loadDtSelectableUserRows(activeOnly: activeOnly);
  final map = <String, String>{};
  for (final row in rows) {
    final label = dtUserDisplayLabel(row);
    if (label.isEmpty) continue;
    final idUuid = (row['id_uuid'] ?? '').toString().trim();
    final id = (row['id'] ?? '').toString().trim();
    final authId = (row['auth_id'] ?? '').toString().trim();
    if (idUuid.isNotEmpty) map[idUuid] = label;
    if (id.length >= 32) map[id] = label;
    if (authId.isNotEmpty) map[authId] = label;
  }
  return map;
}

/// Nomi da mostrare in autocomplete (es. logistica noleggio / MDO).
Future<List<String>> loadDtDisplayNameList({
  bool activeOnly = true,
}) async {
  final rows = await loadDtSelectableUserRows(activeOnly: activeOnly);
  final names = <String>{};
  for (final row in rows) {
    final label = dtUserDisplayLabel(row);
    if (label.isNotEmpty) names.add(label);
  }
  final list = names.toList(growable: false)
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Opzioni dropdown `{id, label}` con `id` = id_uuid se presente, altrimenti id.
Future<List<Map<String, String>>> loadDtDropdownOptions({
  bool activeOnly = true,
}) async {
  final rows = await loadDtSelectableUserRows(activeOnly: activeOnly);
  final out = <Map<String, String>>[];
  for (final row in rows) {
    final idUuid = (row['id_uuid'] ?? '').toString().trim();
    final id = (row['id'] ?? '').toString().trim();
    final key = idUuid.isNotEmpty
        ? idUuid
        : (id.length >= 32 ? id : '');
    if (key.isEmpty) continue;
    out.add({
      'id': key,
      'label': dtUserDisplayLabel(row),
    });
  }
  out.sort(
    (a, b) => (a['label'] ?? '')
        .toLowerCase()
        .compareTo((b['label'] ?? '').toLowerCase()),
  );
  return out;
}
