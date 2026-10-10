import 'supabase_service.dart';

/// Anagrafica strutture D.Lgs. 81/08 su [formazione_dlgs_strutture].
abstract final class FormazioneDlgsStruttureService {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static Map<String, dynamic> _map(dynamic row) =>
      Map<String, dynamic>.from(row as Map);

  static Future<List<Map<String, dynamic>>> loadAll({
    bool activeOnly = false,
  }) async {
    final res = await SupabaseService.client
        .from('formazione_dlgs_strutture')
        .select('id_uuid, nome, indirizzo, maps_link, email_outlook, active')
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

  static const List<String> corsoFieldKeys = <String>[
    'struttura_dlgs_id',
    'struttura_nome',
    'struttura_indirizzo',
    'struttura_email',
    'struttura_link',
  ];

  static Map<String, String> fieldsFromStruttura(Map<String, dynamic>? s) {
    if (s == null) {
      return const <String, String>{
        'struttura_dlgs_id': '',
        'struttura_nome': '',
        'struttura_indirizzo': '',
        'struttura_email': '',
        'struttura_link': '',
      };
    }
    return <String, String>{
      'struttura_dlgs_id': _s(s['id_uuid']),
      'struttura_nome': _s(s['nome']),
      'struttura_indirizzo': _s(s['indirizzo']),
      'struttura_email': _s(s['email_outlook']),
      'struttura_link': _s(s['maps_link']),
    };
  }

  static Map<String, dynamic> clearCorsoStrutturaPayload() => <String, dynamic>{
        'struttura_dlgs_id': null,
        'struttura_nome': null,
        'struttura_indirizzo': null,
        'struttura_email': null,
        'struttura_link': null,
      };

  static String displayLabel(Map<String, dynamic> row) {
    final nome = _s(row['struttura_nome']);
    if (nome.isNotEmpty) return nome;
    return _s(row['struttura_link']);
  }
}
