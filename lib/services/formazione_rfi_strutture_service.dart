import 'supabase_service.dart';

/// Anagrafica strutture RFI (DOIT) su [formazione_rfi_strutture].
abstract final class FormazioneRfiStruttureService {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static Map<String, dynamic> _map(dynamic row) =>
      Map<String, dynamic>.from(row as Map);

  static Future<List<Map<String, dynamic>>> loadAll({
    bool activeOnly = false,
  }) async {
    final res = await SupabaseService.client
        .from('formazione_rfi_strutture')
        .select('id_uuid, nome, indirizzo, maps_link, active')
        .order('nome', ascending: true);
    final all = (res as List).map(_map).toList(growable: false);
    if (!activeOnly) return all;
    return all.where((r) => r['active'] != false).toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> loadActive() =>
      loadAll(activeOnly: true);

  static Map<String, dynamic>? findById(
    List<Map<String, dynamic>> items,
    String? id,
  ) {
    final key = _s(id);
    if (key.isEmpty) return null;
    for (final r in items) {
      if (_s(r['id_uuid']) == key) return r;
    }
    return null;
  }

  /// Campi EAV su [formazione_rfi_records] collegati alla struttura.
  static const List<String> recordFieldKeys = <String>[
    'struttura_rfi_id',
    'struttura_nome',
    'struttura_indirizzo',
    'struttura_link',
  ];

  static Map<String, String> fieldsFromStruttura(Map<String, dynamic>? s) {
    if (s == null) {
      return const <String, String>{
        'struttura_rfi_id': '',
        'struttura_nome': '',
        'struttura_indirizzo': '',
        'struttura_link': '',
      };
    }
    return <String, String>{
      'struttura_rfi_id': _s(s['id_uuid']),
      'struttura_nome': _s(s['nome']),
      'struttura_indirizzo': _s(s['indirizzo']),
      'struttura_link': _s(s['maps_link']),
    };
  }

  static String displayLabel(Map<String, dynamic> row) {
    final nome = _s(row['struttura_nome']);
    if (nome.isNotEmpty) return nome;
    return _s(row['struttura_link']);
  }
}
