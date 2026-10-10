import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/tesserino_helpers.dart';

class CommessaTesserinoModello {
  const CommessaTesserinoModello({
    required this.idUuid,
    required this.commessaIdUuid,
    required this.righeExtra,
    this.commessaNome,
  });

  final String idUuid;
  final String commessaIdUuid;
  final List<String> righeExtra;
  final String? commessaNome;

  factory CommessaTesserinoModello.fromMap(
    Map<String, dynamic> m, {
    String? commessaNome,
  }) {
    return CommessaTesserinoModello(
      idUuid: (m['id_uuid'] ?? '').toString(),
      commessaIdUuid: (m['commessa_id_uuid'] ?? '').toString(),
      righeExtra: parseTesserinoRigheExtraJson(m['righe_extra']),
      commessaNome: commessaNome,
    );
  }
}

/// Commessa con modello tesserino selezionabile dal dipendente.
class CommessaTesserinoOpzione {
  const CommessaTesserinoOpzione({
    required this.commessaIdUuid,
    required this.commessaNome,
    required this.righeExtra,
  });

  final String commessaIdUuid;
  final String commessaNome;
  final List<String> righeExtra;
}

abstract final class CommessaTesserinoModelliService {
  CommessaTesserinoModelliService._();

  static Future<Map<String, String>> loadCommesseMap(SupabaseClient supa) async {
    final res = await supa.from('commesse').select('id_uuid,nome').order('nome');
    final out = <String, String>{};
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = (row['id_uuid'] ?? '').toString().trim();
      final nome = (row['nome'] ?? '').toString().trim();
      if (id.isEmpty || nome.isEmpty) continue;
      out[id] = nome;
    }
    return out;
  }

  static Future<List<CommessaTesserinoModello>> loadModelli(
    SupabaseClient supa,
  ) async {
    final commesse = await loadCommesseMap(supa);
    final res = await supa
        .from('commessa_tesserino_modelli')
        .select('id_uuid, commessa_id_uuid, righe_extra')
        .order('commessa_id_uuid');
    return (res as List)
        .map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final commessaId = (m['commessa_id_uuid'] ?? '').toString();
          return CommessaTesserinoModello.fromMap(
            m,
            commessaNome: commesse[commessaId],
          );
        })
        .toList(growable: false);
  }

  static List<CommessaTesserinoOpzione> modelliToOpzioni(
    List<CommessaTesserinoModello> modelli, {
    Map<String, String>? commesseByUuid,
  }) {
    final out = modelli
        .map(
          (m) => CommessaTesserinoOpzione(
            commessaIdUuid: m.commessaIdUuid,
            commessaNome: m.commessaNome ??
                commesseByUuid?[m.commessaIdUuid] ??
                m.commessaIdUuid,
            righeExtra: m.righeExtra,
          ),
        )
        .toList()
      ..sort((a, b) => a.commessaNome.compareTo(b.commessaNome));
    return out;
  }

  /// Tutti i modelli commessa configurati (per admin / anteprima).
  static Future<List<CommessaTesserinoOpzione>> loadTutteLeOpzioni(
    SupabaseClient supa,
  ) async {
    final commesse = await loadCommesseMap(supa);
    final modelli = await loadModelli(supa);
    return modelliToOpzioni(modelli, commesseByUuid: commesse);
  }

  static Future<void> upsertModello({
    required SupabaseClient supa,
    String? idUuid,
    required String commessaIdUuid,
    required List<String> righeExtra,
  }) async {
    final payload = <String, dynamic>{
      'commessa_id_uuid': commessaIdUuid,
      'righe_extra': normalizeTesserinoRigheExtra(righeExtra),
    };
    if (idUuid != null && idUuid.trim().isNotEmpty) {
      await supa
          .from('commessa_tesserino_modelli')
          .update(payload)
          .eq('id_uuid', idUuid);
      return;
    }
    await supa.from('commessa_tesserino_modelli').insert(payload);
  }

  static Future<void> deleteModello({
    required SupabaseClient supa,
    required String idUuid,
  }) async {
    await supa.from('commessa_tesserino_modelli').delete().eq('id_uuid', idUuid);
  }

  /// Modelli tesserino per le commesse del dipendente (POS); se POS vuoto, tutti i modelli.
  static Future<List<CommessaTesserinoOpzione>> loadOpzioniPerPersonale(
    SupabaseClient supa,
    String personaleIdUuid,
  ) async {
    final commesse = await loadCommesseMap(supa);
    final modelli = await loadModelli(supa);
    if (modelli.isEmpty) return const [];

    final mieCommesse = <String>{};
    try {
      final res = await supa
          .from('pos_commessa_dipendenti')
          .select('commessa_id')
          .eq('personale_id', personaleIdUuid);
      for (final raw in res as List) {
        final id = (raw['commessa_id'] ?? '').toString().trim();
        if (id.isNotEmpty) mieCommesse.add(id);
      }
    } catch (_) {}

    final filtered = mieCommesse.isEmpty
        ? modelli
        : modelli
            .where((m) => mieCommesse.contains(m.commessaIdUuid))
            .toList(growable: false);

    final source = filtered.isEmpty ? modelli : filtered;
    return modelliToOpzioni(source, commesseByUuid: commesse);
  }

  static CommessaTesserinoOpzione? findOpzione(
    List<CommessaTesserinoOpzione> opzioni,
    String? commessaIdUuid,
  ) {
    final id = (commessaIdUuid ?? '').trim();
    if (id.isEmpty) return null;
    for (final o in opzioni) {
      if (o.commessaIdUuid == id) return o;
    }
    return null;
  }
}
