import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/date_formatters.dart';
import '../utils/field_timestamps.dart';
import '../utils/users_directory.dart';

/// Km mezzi stradali sincronizzati dal registro RCC (`logistica_rcc_carburante.km_ore`).
class MezziKmService {
  MezziKmService._();

  static final SupabaseClient _supa = Supabase.instance.client;

  static int? parseKmOreValue(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    final asDouble = double.tryParse(normalized);
    if (asDouble != null) return asDouble.round();
    return int.tryParse(text.replaceAll(RegExp(r'[^0-9-]'), ''));
  }

  static bool rccRowHasKmOre(Map<String, dynamic> row) =>
      parseKmOreValue(row['km_ore']) != null;

  static DateTime? kmOreInsertedAtFromRccRow(Map<String, dynamic> row) =>
      fieldInsertedAtInstant(row, 'km_ore');

  /// Aggiorna `km_attuali` e `km_aggiornato_il` sul mezzo dall'ultimo RCC con km.
  /// Non azzera mai i km già registrati (es. dopo eliminazione rifornimento).
  static Future<void> syncLatestKmFromRccForMezzo(String mezzoIdUuid) async {
    final mezzoId = mezzoIdUuid.trim();
    if (mezzoId.isEmpty) return;

    final res = await _supa
        .from('logistica_rcc_carburante')
        .select(
          'km_ore,data_rifornimento,created_at,updated_at,field_timestamps',
        )
        .eq('mezzo_stradale_id_uuid', mezzoId)
        .order('data_rifornimento', ascending: false)
        .order('updated_at', ascending: false)
        .limit(50);
    Map<String, dynamic>? latestWithKm;
    for (final raw in (res as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (!rccRowHasKmOre(row)) continue;
      latestWithKm = row;
      break;
    }

    if (latestWithKm == null) return;

    final km = parseKmOreValue(latestWithKm['km_ore']);
    if (km == null) return;
    final aggAt =
        kmOreInsertedAtFromRccRow(latestWithKm) ?? DateTime.now().toUtc();
    await _supa.from('logistica_mezzi_stradali').update({
      'km_attuali': km,
      'km_aggiornato_il': aggAt.toIso8601String(),
    }).eq('id_uuid', mezzoId);
  }

  static String kmAttualiLabel(
    Map<String, dynamic> row, {
    required String Function(int km) formatKm,
  }) {
    final km = parseKmOreValue(row['km_attuali']);
    if (km == null) return '—';
    return '${formatKm(km)} km';
  }

  static String kmUltimoAggiornamentoLabel(Map<String, dynamic> row) {
    final raw = row['km_aggiornato_il'];
    if (raw == null || raw.toString().trim().isEmpty) return '—';
    return formatDateDdMmYyyy(raw);
  }

  /// Mappa nome assegnatario normalizzato → `users.id_uuid` (da personale + users).
  static Future<Map<String, String>> loadAssigneeNameToUserUuidMap() async {
    final map = <String, String>{};

    void putName(String rawName, String? userUuid) {
      final uuid = (userUuid ?? '').trim();
      if (uuid.isEmpty) return;
      final norm = normalizePersonName(rawName);
      if (norm.isEmpty) return;
      map.putIfAbsent(norm, () => uuid);
    }

    try {
      final personaleRows = await _supa
          .from('personale')
          .select('full_name,user_id,active')
          .eq('active', true);
      final personaleList = List<Map<String, dynamic>>.from(
        (personaleRows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final userIds = <int>{};
      for (final p in personaleList) {
        final uid = p['user_id'];
        if (uid is int) userIds.add(uid);
        final parsed = int.tryParse((uid ?? '').toString().trim());
        if (parsed != null) userIds.add(parsed);
      }

      final userById = <int, String>{};
      if (userIds.isNotEmpty) {
        final users = await _supa
            .from('users')
            .select('id,id_uuid')
            .inFilter('id', userIds.toList());
        for (final e in (users as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = m['id'] is int
              ? m['id'] as int
              : int.tryParse((m['id'] ?? '').toString());
          final uuid = (m['id_uuid'] ?? '').toString().trim();
          if (id != null && uuid.isNotEmpty) userById[id] = uuid;
        }
      }

      for (final p in personaleList) {
        final fullName = (p['full_name'] ?? '').toString().trim();
        if (fullName.isEmpty) continue;
        final uid = p['user_id'];
        int? userId;
        if (uid is int) userId = uid;
        userId ??= int.tryParse((uid ?? '').toString().trim());
        putName(fullName, userId != null ? userById[userId] : null);
      }

      List allUsers;
      try {
        allUsers = await _supa
            .from('users')
            .select('id_uuid,full_name,username,hidden_from_directory');
      } catch (_) {
        allUsers = await _supa
            .from('users')
            .select('id_uuid,full_name,username');
      }
      for (final e in allUsers) {
        final m = Map<String, dynamic>.from(e as Map);
        if (!UsersDirectory.isVisibleInDirectory(m)) continue;
        final uuid = (m['id_uuid'] ?? '').toString().trim();
        final full = (m['full_name'] ?? '').toString().trim();
        final user = (m['username'] ?? '').toString().trim();
        if (full.isNotEmpty) putName(full, uuid);
        if (user.isNotEmpty) putName(user, uuid);
      }
    } catch (_) {}

    return map;
  }

  static bool namesReferToSamePerson(String rawA, String rawB) {
    final a = normalizePersonName(rawA);
    final b = normalizePersonName(rawB);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    final aParts = a.split(' ').where((t) => t.length >= 2).toList();
    final bParts = b.split(' ').where((t) => t.length >= 2).toList();
    if (aParts.length < 2 || bParts.length < 2) return false;

    bool allPartsIn(String haystack, List<String> parts) {
      for (final t in parts) {
        if (!haystack.contains(t)) return false;
      }
      return true;
    }

    if (!allPartsIn(a, bParts) || !allPartsIn(b, aParts)) return false;

    var overlap = 0;
    for (final t in aParts) {
      if (b.contains(t)) overlap++;
    }
    return overlap >= 2;
  }

  static bool _normalizedNamesMatch(String aNorm, String bNorm) =>
      namesReferToSamePerson(aNorm, bNorm);

  static String? resolveAssigneeUserUuid(
    Map<String, dynamic> row, {
    Map<String, String> assigneeNameToUserUuid = const {},
  }) {
    final direct = (row['assegnatario_user_uuid'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final assignNorm =
        normalizePersonName((row['assegnatario_attuale'] ?? '').toString());
    if (assignNorm.isEmpty || assigneeNameToUserUuid.isEmpty) return null;

    final exact = assigneeNameToUserUuid[assignNorm];
    if (exact != null && exact.isNotEmpty) return exact;

    for (final e in assigneeNameToUserUuid.entries) {
      if (_normalizedNamesMatch(assignNorm, e.key)) return e.value;
    }
    return null;
  }

  static String normalizePersonName(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'->.*$'), ' ');
    s = s.replaceAll(RegExp(r'\(.*?\)'), ' ');
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static bool isRowAssignedToCurrentUser(
    Map<String, dynamic> row,
    String userUuid,
    String myNameNorm,
  ) {
    final assignedUuid =
        (row['assegnatario_user_uuid'] ?? '').toString().trim();
    if (userUuid.isNotEmpty && assignedUuid.isNotEmpty) {
      return assignedUuid == userUuid;
    }
    if (myNameNorm.isEmpty) return false;
    return namesReferToSamePerson(
      (row['assegnatario_attuale'] ?? '').toString(),
      myNameNorm,
    );
  }

  static Future<({String uuid, String nameNorm})> loadCurrentUserIdentity() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) {
      return (uuid: '', nameNorm: '');
    }
    try {
      final me = await _supa
          .from('users')
          .select('id,id_uuid,full_name,username')
          .eq('auth_id', authId!)
          .maybeSingle();
      var idUuid = (me?['id_uuid'] ?? '').toString().trim();
      final userId = me?['id'] is int
          ? me!['id'] as int
          : int.tryParse((me?['id'] ?? '').toString().trim());
      final userFull = (me?['full_name'] ?? '').toString().trim();
      final username = (me?['username'] ?? '').toString().trim();

      String personaleName = '';
      Future<Map<String, dynamic>?> fetchPersonale(String col, String val) async {
        try {
          final row = await _supa
              .from('personale')
              .select('full_name,user_id')
              .eq(col, val)
              .maybeSingle();
          if (row == null) return null;
          return Map<String, dynamic>.from(row);
        } catch (_) {
          return null;
        }
      }

      var p = await fetchPersonale('user_id', authId);
      if (p == null && userId != null) {
        p = await fetchPersonale('user_id', userId.toString());
      }
      if (p == null && idUuid.isNotEmpty) {
        p = await fetchPersonale('user_id', idUuid);
      }
      if (p != null) {
        personaleName = (p['full_name'] ?? '').toString().trim();
      }

      final nameSource = personaleName.isNotEmpty
          ? personaleName
          : (userFull.isNotEmpty ? userFull : username);
      return (
        uuid: idUuid,
        nameNorm: normalizePersonName(nameSource),
      );
    } catch (_) {
      return (uuid: '', nameNorm: '');
    }
  }
}
