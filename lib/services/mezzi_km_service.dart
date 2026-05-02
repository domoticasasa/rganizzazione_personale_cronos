import 'package:supabase_flutter/supabase_flutter.dart';

class MezziKmService {
  MezziKmService._();

  static final SupabaseClient _supa = Supabase.instance.client;

  static DateTime currentMonthStart([DateTime? now]) {
    final ref = now ?? DateTime.now();
    return DateTime(ref.year, ref.month, 1);
  }

  static bool shouldRequireMonthlyKm([DateTime? now]) {
    final ref = now ?? DateTime.now();
    return ref.day > 1;
  }

  /// Allineato alla logica della pagina Mezzi Stradali: confronto nome normalizzato.
  static String normalizePersonName(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'->.*$'), ' ');
    s = s.replaceAll(RegExp(r'\(.*?\)'), ' ');
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static bool _isAssignedByText(String rawAssignatario, String myNameNorm) {
    if (myNameNorm.isEmpty) return false;
    final assign = normalizePersonName(rawAssignatario);
    if (assign.isEmpty) return false;
    if (assign.contains(myNameNorm) || myNameNorm.contains(assign)) {
      return true;
    }
    final myTokens = myNameNorm
        .split(' ')
        .where((t) => t.length >= 3)
        .toList(growable: false);
    if (myTokens.isEmpty) return false;
    var matches = 0;
    for (final t in myTokens) {
      if (assign.contains(t)) matches++;
    }
    return matches >= 2 || (myTokens.length == 1 && matches == 1);
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
    return _isAssignedByText(
      (row['assegnatario_attuale'] ?? '').toString(),
      myNameNorm,
    );
  }

  static Future<String?> _currentUserUuid() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) return null;
    final row = await _supa
        .from('users')
        .select('id_uuid')
        .eq('auth_id', authId!)
        .maybeSingle();
    final idUuid = (row?['id_uuid'] ?? '').toString().trim();
    return idUuid.isEmpty ? null : idUuid;
  }

  static Future<({String? uuid, String nameNorm})> _currentUserIdentity() async {
    final authId = _supa.auth.currentUser?.id;
    if ((authId ?? '').trim().isEmpty) {
      return (uuid: null, nameNorm: '');
    }
    try {
      final me = await _supa
          .from('users')
          .select('id_uuid,full_name,username')
          .eq('auth_id', authId!)
          .maybeSingle();
      final idUuid = (me?['id_uuid'] ?? '').toString().trim();
      final full = (me?['full_name'] ?? '').toString().trim();
      final user = (me?['username'] ?? '').toString().trim();
      final source = full.isNotEmpty ? full : user;
      final norm = normalizePersonName(source);
      return (
        uuid: idUuid.isEmpty ? null : idUuid,
        nameNorm: norm,
      );
    } catch (_) {
      return (uuid: null, nameNorm: '');
    }
  }

  static Future<List<Map<String, dynamic>>>
      pendingAssignedMezziForCurrentMonth() async {
    final ident = await _currentUserIdentity();
    final userUuid = ident.uuid ?? '';
    final nameNorm = ident.nameNorm;
    if (userUuid.isEmpty && nameNorm.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final monthStart = currentMonthStart();
    final mezzi = await _supa
        .from('logistica_mezzi_stradali')
        .select(
          'id_uuid,targa,marca,modello,assegnatario_user_uuid,assegnatario_attuale,active',
        )
        .eq('active', true)
        .order('targa', ascending: true);
    final mezziList = List<Map<String, dynamic>>.from(
      (mezzi as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final assignedToMe = mezziList
        .where((r) => isRowAssignedToCurrentUser(r, userUuid, nameNorm))
        .toList(growable: false);
    if (assignedToMe.isEmpty) return const <Map<String, dynamic>>[];
    final mezzoIds = assignedToMe
        .map((e) => (e['id_uuid'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (mezzoIds.isEmpty) return const <Map<String, dynamic>>[];
    if (userUuid.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final inserts = await _supa
        .from('logistica_mezzi_km_mensili')
        .select('mezzo_id_uuid')
        .eq('user_uuid', userUuid)
        .eq('mese_riferimento', monthStart.toIso8601String().split('T').first)
        .inFilter('mezzo_id_uuid', mezzoIds);
    final doneIds = <String>{
      for (final row in (inserts as List))
        (Map<String, dynamic>.from(row as Map)['mezzo_id_uuid'] ?? '')
            .toString()
            .trim(),
    };
    return assignedToMe
        .where(
            (m) => !doneIds.contains((m['id_uuid'] ?? '').toString().trim()))
        .toList(growable: false);
  }

  static Future<void> saveKmForCurrentMonth({
    required String mezzoIdUuid,
    required int kmInseriti,
  }) async {
    final userUuid = await _currentUserUuid();
    if ((userUuid ?? '').isEmpty) {
      throw Exception('Utente non identificato.');
    }
    final monthStart = currentMonthStart();
    await _supa.from('logistica_mezzi_km_mensili').upsert({
      'mezzo_id_uuid': mezzoIdUuid,
      'user_uuid': userUuid,
      'mese_riferimento': monthStart.toIso8601String().split('T').first,
      'km_inseriti': kmInseriti,
      'data_inserimento': DateTime.now().toIso8601String(),
    }, onConflict: 'mezzo_id_uuid,user_uuid,mese_riferimento');
  }
}
