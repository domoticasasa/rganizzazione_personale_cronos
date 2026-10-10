import 'dart:convert';

import '../services/supabase_service.dart';
import 'date_formatters.dart';

Map<String, dynamic> _toTimestampMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
  }
  return const <String, dynamic>{};
}

DateTime? _instantFromFieldTimestampValue(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    final at = raw['at'] ?? raw['updated_at'] ?? raw['created_at'];
    return _instantFromFieldTimestampValue(at);
  }
  return parseSupabaseTimestampToItaly(raw);
}

String? _byUuidFromFieldTimestampValue(dynamic raw) {
  if (raw is! Map) return null;
  final by = (raw['by'] ??
          raw['user_uuid'] ??
          raw['updated_by_user_uuid'] ??
          '')
      .toString()
      .trim();
  return by.isEmpty ? null : by;
}

String? _rowAuditUserUuid(Map<String, dynamic> row) {
  final updated = (row['updated_by_user_uuid'] ?? '').toString().trim();
  if (updated.isNotEmpty) return updated;
  final created = (row['created_by_user_uuid'] ?? '').toString().trim();
  if (created.isNotEmpty) return created;
  final updatedBy = (row['updated_by'] ?? '').toString().trim();
  if (updatedBy.isNotEmpty) return updatedBy;
  final createdBy = (row['created_by'] ?? '').toString().trim();
  if (createdBy.isNotEmpty) return createdBy;
  return null;
}

String _userLabel(String? uuid, Map<String, String> userNamesByUuid) {
  if (uuid == null || uuid.isEmpty) return '—';
  return userNamesByUuid[uuid] ?? uuid;
}

/// Nome completo per tooltip audit (es. «Alexandru Cibuc»).
String userDisplayLabelForAudit(
  String? uuid,
  Map<String, String> userNamesByUuid,
) {
  return _userLabel(uuid, userNamesByUuid);
}

String _formatAuditHoverMessage({
  required String by,
  required DateTime? dt,
  String actionLabel = 'Ultimo aggiornamento',
}) {
  if (dt == null) {
    return '$actionLabel da: $by\nData: —\nOra: —';
  }
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$actionLabel da: $by\nData: ${formatDateDdMmYyyyFromDate(dt)}\nOra: $hh:$mm';
}

/// Converte `field_timestamps` legacy (solo data ISO) in `{at, by}` usando audit di riga.
Map<String, dynamic> normalizeFieldTimestampsForRow(Map<String, dynamic> row) {
  final ts = _toTimestampMap(row['field_timestamps']);
  if (ts.isEmpty) return const <String, dynamic>{};

  final byText = _rowAuditUserUuid(row) ?? '';
  final out = <String, dynamic>{};

  for (final entry in ts.entries) {
    final k = entry.key;
    if (k == '_initialized') continue;
    final v = entry.value;

    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) continue;
      out[k] = <String, dynamic>{'at': s, 'by': byText};
      continue;
    }

    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final by = (m['by'] ??
              m['user_uuid'] ??
              m['updated_by_user_uuid'] ??
              '')
          .toString()
          .trim();
      if (by.isEmpty && byText.isNotEmpty) {
        m['by'] = byText;
      }
      out[k] = m;
    }
  }

  return out;
}

/// Nomi utenti per tooltip audit (`field_timestamps` → `by`).
Future<Map<String, String>> loadUserNamesByUuid(Set<String> uuids) async {
  final ids = uuids.where((u) => u.trim().isNotEmpty).toList();
  if (ids.isEmpty) return {};
  final out = <String, String>{};
  for (var i = 0; i < ids.length; i += 80) {
    final end = i + 80 > ids.length ? ids.length : i + 80;
    final chunk = ids.sublist(i, end);
    final res = await SupabaseService.client
        .from('users')
        .select('id_uuid, full_name, username')
        .inFilter('id_uuid', chunk);
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final full = (m['full_name'] ?? '').toString().trim();
      final user = (m['username'] ?? '').toString().trim();
      out[id] = full.isNotEmpty ? full : (user.isNotEmpty ? user : id);
    }
  }
  return out;
}

/// Chiave audit per cella RFI (`formazione_rfi_records`).
String rfiRecordAuditFieldKey(Map<String, dynamic> row) {
  final dateRaw = (row['value_date'] ?? '').toString().trim();
  if (dateRaw.isNotEmpty) return 'value_date';
  return 'value_text';
}

/// Raccoglie gli UUID autore presenti in `field_timestamps` (formato `{"at","by"}`).
void mergeFieldTimestampActorUuids(
  Map<String, dynamic> row,
  Set<String> ids,
) {
  final timestamps = _toTimestampMap(row['field_timestamps']);
  for (final v in timestamps.values) {
    final uuid = _byUuidFromFieldTimestampValue(v);
    if (uuid != null && uuid.isNotEmpty) ids.add(uuid);
  }
  final rowUuid = _rowAuditUserUuid(row);
  if (rowUuid != null && rowUuid.isNotEmpty) ids.add(rowUuid);
}

DateTime? fieldInsertedAtInstant(
  Map<String, dynamic> row,
  String fieldKey, {
  String fallbackField = 'created_at',
}) {
  final timestamps = normalizeFieldTimestampsForRow(row);
  final dynamic raw = timestamps[fieldKey] ?? row[fallbackField];
  return _instantFromFieldTimestampValue(raw);
}

String fieldInsertedAtLabel(
  Map<String, dynamic> row,
  String fieldKey, {
  String fallbackField = 'created_at',
}) {
  final dt = fieldInsertedAtInstant(row, fieldKey, fallbackField: fallbackField);
  if (dt == null) return '—';
  return formatDateTimeItFromSupabase(dt);
}

String _rowAuditFallbackHoverMessage(
  Map<String, dynamic> row,
  Map<String, String> userNamesByUuid,
) {
  DateTime? dt;
  for (final fb in [row['updated_at'], row['created_at']]) {
    dt = _instantFromFieldTimestampValue(fb);
    if (dt != null) break;
  }
  final by = userDisplayLabelForAudit(_rowAuditUserUuid(row), userNamesByUuid);
  return _formatAuditHoverMessage(by: by, dt: dt);
}

/// Tooltip audit per cella da `field_timestamps[fieldKey]` (legacy ISO o `{"at","by"}`).
///
/// Se il campo non ha storico proprio, usa l'audit di riga ([rowAuditWhenFieldMissing]).
String fieldAuditHoverMessage(
  Map<String, dynamic> row,
  String fieldKey,
  Map<String, String> userNamesByUuid, {
  bool rowAuditWhenFieldMissing = true,
  String? fieldLabel,
}) {
  final timestamps = normalizeFieldTimestampsForRow(row);
  final title = (fieldLabel ?? '').trim().isEmpty ? '' : '$fieldLabel\n';

  if (!timestamps.containsKey(fieldKey)) {
    if (rowAuditWhenFieldMissing) {
      return '$title${_rowAuditFallbackHoverMessage(row, userNamesByUuid)}\n(Storico generale riga)';
    }
    return '${title}Nessuna traccia per questo campo.\n'
        'Modifica e salva il BOX per registrare autore, data e ora.';
  }

  final dynamic entry = timestamps[fieldKey];
  if (entry == null) {
    if (rowAuditWhenFieldMissing) {
      return '$title${_rowAuditFallbackHoverMessage(row, userNamesByUuid)}\n(Storico generale riga)';
    }
    return '${title}Nessuna traccia per questo campo.\n'
        'Modifica e salva il BOX per registrare autore, data e ora.';
  }

  final DateTime? dt = _instantFromFieldTimestampValue(entry);
  final String? fieldByUuid = _byUuidFromFieldTimestampValue(entry);
  final by = fieldByUuid != null && fieldByUuid.isNotEmpty
      ? userDisplayLabelForAudit(fieldByUuid, userNamesByUuid)
      : userDisplayLabelForAudit(_rowAuditUserUuid(row), userNamesByUuid);

  if (dt == null && rowAuditWhenFieldMissing) {
    return '$title${_rowAuditFallbackHoverMessage(row, userNamesByUuid)}\n(Storico generale riga)';
  }

  return '$title${_formatAuditHoverMessage(by: by, dt: dt)}';
}
