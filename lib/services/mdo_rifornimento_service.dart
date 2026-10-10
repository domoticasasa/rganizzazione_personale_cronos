import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/date_formatters.dart';
import '../utils/rcc_mdo_destinations.dart';

/// `personale.id_uuid` → `users.id_uuid` del dipendente collegato.
Future<String?> userUuidForPersonale(SupabaseClient supa, String personaleUuid) async {
  final pid = personaleUuid.trim();
  if (pid.isEmpty) return null;
  try {
    final personaleRow = await supa
        .from('personale')
        .select('user_id')
        .eq('id_uuid', pid)
        .maybeSingle();
    if (personaleRow == null) return null;

    final userLink = (personaleRow['user_id'] ?? '').toString().trim();
    if (userLink.isEmpty) return null;

    final byAuth = await supa
        .from('users')
        .select('id_uuid')
        .eq('auth_id', userLink)
        .maybeSingle();
    final fromAuth = (byAuth?['id_uuid'] ?? '').toString().trim();
    if (fromAuth.isNotEmpty) return fromAuth;

    final byLegacy = await supa
        .from('users')
        .select('id_uuid')
        .eq('id', userLink)
        .maybeSingle();
    final fromLegacy = (byLegacy?['id_uuid'] ?? '').toString().trim();
    if (fromLegacy.isNotEmpty) return fromLegacy;

    final byUuid = await supa
        .from('users')
        .select('id_uuid')
        .eq('id_uuid', userLink)
        .maybeSingle();
    final fromUuid = (byUuid?['id_uuid'] ?? '').toString().trim();
    return fromUuid.isEmpty ? null : fromUuid;
  } catch (_) {
    return null;
  }
}

/// `users.id_uuid` del compilatore → `personale.id_uuid`.
Future<String?> personaleIdUuidForUser(SupabaseClient supa, String userUuid) async {
  final u = userUuid.trim();
  if (u.isEmpty) return null;
  try {
    final userRow = await supa
        .from('users')
        .select('auth_id, id, id_uuid')
        .eq('id_uuid', u)
        .maybeSingle();
    if (userRow == null) return null;

    Future<String?> byUserId(String value) async {
      final v = value.trim();
      if (v.isEmpty) return null;
      final p = await supa
          .from('personale')
          .select('id_uuid')
          .eq('user_id', v)
          .maybeSingle();
      final pid = (p?['id_uuid'] ?? '').toString().trim();
      return pid.isEmpty ? null : pid;
    }

    final authId = (userRow['auth_id'] ?? '').toString().trim();
    final fromAuth = await byUserId(authId);
    if (fromAuth != null) return fromAuth;

    final legacyId = (userRow['id'] ?? '').toString().trim();
    final fromLegacy = await byUserId(legacyId);
    if (fromLegacy != null) return fromLegacy;

    return byUserId(u);
  } catch (_) {
    return null;
  }
}

/// Normalizza un valore commessa (uuid o nome) in `commesse.id_uuid`.
Future<String?> resolveCommessaIdUuid(SupabaseClient supa, String raw) async {
  final v = raw.trim();
  if (v.isEmpty) return null;
  try {
    final byUuid = await supa
        .from('commesse')
        .select('id_uuid')
        .eq('id_uuid', v)
        .maybeSingle();
    final uuid = (byUuid?['id_uuid'] ?? '').toString().trim();
    if (uuid.isNotEmpty) return uuid;

    final byNome = await supa
        .from('commesse')
        .select('id_uuid')
        .eq('nome', v)
        .maybeSingle();
    final id = (byNome?['id_uuid'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}

bool _isoDayInBookingRange(String isoRefuelDay, dynamic startRaw, dynamic endRaw) {
  final ref = DateTime.tryParse(isoRefuelDay);
  final start = DateTime.tryParse((startRaw ?? '').toString());
  final end = DateTime.tryParse((endRaw ?? '').toString());
  if (ref == null || start == null || end == null) return false;
  final d = DateTime(ref.year, ref.month, ref.day);
  final ds = DateTime(start.year, start.month, start.day);
  final de = DateTime(end.year, end.month, end.day);
  return !d.isBefore(ds) && !d.isAfter(de);
}

String? _commessaFromBookingRow(Map<String, dynamic> b) {
  for (final k in const ['commessa_uuid', 'commessa_id', 'id_commessa']) {
    final v = (b[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

String? _personaleFromBookingRow(Map<String, dynamic> b) {
  for (final k in const ['personale_uuid', 'personale_id', 'id_personale']) {
    final v = (b[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

/// Prima commessa da prenotazione pernottamento (`bookings`) che copre [data].
Future<String?> suggestCommessaUuidFromPernottamento({
  required SupabaseClient supa,
  required String compilatoreUserUuid,
  required String isoRefuelDate,
}) async {
  final iso = isoRefuelDate.trim();
  if (iso.isEmpty) return null;
  final personaleUuid = await personaleIdUuidForUser(supa, compilatoreUserUuid);
  if (personaleUuid == null) return null;

  try {
    final res = await supa
        .from('bookings')
        .select(
            'personale_id, personale_uuid, commessa_id, commessa_uuid, start_date, end_date, status, booking_type')
        .eq('booking_type', 'pernottamento')
        .lte('start_date', iso)
        .gte('end_date', iso)
        .order('start_date', ascending: false)
        .limit(80);

    for (final raw in (res as List)) {
      final b = Map<String, dynamic>.from(raw as Map);
      final bt = (b['booking_type'] ?? '').toString().trim().toLowerCase();
      if (bt.isNotEmpty && bt != 'pernottamento') continue;
      final pid = _personaleFromBookingRow(b);
      if (pid != personaleUuid) continue;
      if (!_isoDayInBookingRange(iso, b['start_date'], b['end_date'])) continue;
      final comm = _commessaFromBookingRow(b);
      if (comm == null || comm.isEmpty) continue;
      final resolved = await resolveCommessaIdUuid(supa, comm);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }
  } catch (_) {}
  return null;
}

bool isMdoRifornimentoComplete({
  required double litriTotali,
  required double litriRiforniti,
}) {
  if (litriRiforniti > litriTotali + 0.001) return false;
  return (litriTotali - litriRiforniti).abs() < 0.001;
}

double mdoLitriTotaliFromRow(Map<String, dynamic> row) {
  final litri = row['litri'];
  if (litri is num) return litri.toDouble();
  final parsed = double.tryParse(
    litri.toString().trim().replaceAll(',', '.'),
  );
  return parsed ?? 0;
}

/// True se i litri totali coincidono con la somma mezzi (manca da rifornire = 0).
bool isMdoRifornimentoCompleteFromRow(Map<String, dynamic> row) {
  final litriTotali = mdoLitriTotaliFromRow(row);
  if (litriTotali <= 0) return false;
  final litriRiforniti = sumMdoDestinationLitri(parseMdoDestinationsFromRow(row));
  return isMdoRifornimentoComplete(
    litriTotali: litriTotali,
    litriRiforniti: litriRiforniti,
  );
}

bool isMdoRifornimentoLockedForDipendente(
  Map<String, dynamic> row, {
  required bool dipendenteMode,
}) {
  if (!dipendenteMode) return false;
  // Blocca solo se manca da rifornire = 0 (non solo il flag DB, che può essere disallineato).
  return isMdoRifornimentoCompleteFromRow(row);
}

const Duration kMdoRifornimentoEditGrace = Duration(minutes: 5);

bool isMdoRifornimentoWithinEditGrace(
  Map<String, dynamic> row, {
  DateTime? now,
}) {
  final ref = (now ?? DateTime.now()).toUtc();
  final updated = parseSupabaseTimestampToUtc(row['updated_at']);
  final created = parseSupabaseTimestampToUtc(row['created_at']);
  final base = updated ?? created;
  if (base == null) return false;
  return ref.difference(base) <= kMdoRifornimentoEditGrace;
}
