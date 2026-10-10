import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/numero_tesserino_generator.dart';

/// Assegnazione numero tesserino su `personale` (regola PATGIU01001 → PATGIU02001).
class NumeroTesserinoService {
  NumeroTesserinoService._();

  static Future<List<String>> _numeriConPrefisso(
    SupabaseClient supa,
    String prefix, {
    int? excludePersonaleId,
  }) async {
    final p = prefix.trim().toUpperCase();
    if (p.length < 6) return const [];

    var q = supa
        .from('personale')
        .select('id, numero_tesserino')
        .not('numero_tesserino', 'is', null)
        .ilike('numero_tesserino', '$p%');

    if (excludePersonaleId != null) {
      q = q.neq('id', excludePersonaleId);
    }

    final res = await q;
    return (res as List)
        .map((e) => (Map<String, dynamic>.from(e as Map)['numero_tesserino'] ?? '')
            .toString()
            .trim())
        .where((x) => x.isNotEmpty)
        .toList(growable: false);
  }

  /// Calcola il prossimo numero per cognome/nome o `full_name`.
  static Future<String> allocate({
    required SupabaseClient supa,
    String? fullName,
    String? cognome,
    String? nome,
    int? excludePersonaleId,
  }) async {
    final prefix = (cognome != null || nome != null)
        ? tesserinoPrefixFromParts(
            cognome: cognome ?? '',
            nome: nome ?? '',
          )
        : tesserinoPrefixFromFullName(fullName ?? '');
    final existing = await _numeriConPrefisso(
      supa,
      prefix,
      excludePersonaleId: excludePersonaleId,
    );
    return nextNumeroTesserino(prefix: prefix, existingNumeri: existing);
  }

  /// Se il record non ha numero, ne assegna uno; altrimenti restituisce quello attuale.
  static Future<String?> ensureForPersonaleId({
    required SupabaseClient supa,
    required int personaleId,
    required String fullName,
  }) async {
    final row = await supa
        .from('personale')
        .select('numero_tesserino')
        .eq('id', personaleId)
        .maybeSingle();
    final current = (row?['numero_tesserino'] ?? '').toString().trim();
    if (current.isNotEmpty) return current;

    final numero = await allocate(
      supa: supa,
      fullName: fullName,
      excludePersonaleId: personaleId,
    );
    await supa.from('personale').update({'numero_tesserino': numero}).eq('id', personaleId);
    return numero;
  }
}
