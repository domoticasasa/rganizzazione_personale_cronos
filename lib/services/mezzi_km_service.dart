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

  static Future<List<Map<String, dynamic>>>
      pendingAssignedMezziForCurrentMonth() async {
    final userUuid = await _currentUserUuid();
    if ((userUuid ?? '').isEmpty) return const <Map<String, dynamic>>[];
    final monthStart = currentMonthStart();
    final mezzi = await _supa
        .from('logistica_mezzi_stradali')
        .select('id_uuid,targa,marca,modello,assegnatario_user_uuid,active')
        .eq('active', true)
        .eq('assegnatario_user_uuid', userUuid!)
        .order('targa', ascending: true);
    final mezziList = List<Map<String, dynamic>>.from(
      (mezzi as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    if (mezziList.isEmpty) return const <Map<String, dynamic>>[];
    final mezzoIds = mezziList
        .map((e) => (e['id_uuid'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (mezzoIds.isEmpty) return const <Map<String, dynamic>>[];
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
    return mezziList
        .where((m) => !doneIds.contains((m['id_uuid'] ?? '').toString().trim()))
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
