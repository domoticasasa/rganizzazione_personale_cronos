import 'supabase_service.dart';

class DpiCategoriesService {
  static const String _table = 'dpi_categories';

  static const List<String> defaultCategories = <String>[
    'Elmetto',
    'Imbracatura',
    'Cordino',
    'Cordino Singolo con Dissipatore',
    'Cordino di Posizionamento',
    'Cordino Shock Absorber Doppio',
    'Guanti',
    'Occhiali',
    'Scarpe',
  ];

  /// Nome canonico se coincide (ignorando maiuscole) con un default predefinito.
  static String? defaultCanonicalForLower(String lowerKey) {
    for (final d in defaultCategories) {
      if (d.toLowerCase() == lowerKey) return d;
    }
    return null;
  }

  static bool _looksAllCaps(String s) {
    final t = s.trim();
    if (t.length < 2) return false;
    return t == t.toUpperCase() && t != t.toLowerCase();
  }

  /// Sceglie un’unica etichetta tra due varianti dello stesso nome (stesso lower case).
  static String pickCanonicalDisplayName(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.toLowerCase() != y.toLowerCase()) return x;
    final def = defaultCanonicalForLower(x.toLowerCase());
    if (def != null) return def;
    if (_looksAllCaps(x) && !_looksAllCaps(y)) return y;
    if (!_looksAllCaps(x) && _looksAllCaps(y)) return x;
    return x.length <= y.length ? x : y;
  }

  /// Unifica elenchi di categorie: niente duplicati per differenza solo di maiuscole.
  /// [seedDefaults] aggiunge le stringhe predefinite del codice (solo per compatibilità legacy).
  /// Per elenchi ufficiali usare `false`: la fonte è solo il database `dpi_categories`.
  static List<String> mergeUniqueCategoryNames(
    Iterable<String> names, {
    bool seedDefaults = false,
  }) {
    final byLower = <String, String>{};
    if (seedDefaults) {
      for (final d in defaultCategories) {
        byLower[d.toLowerCase()] = d;
      }
    }
    for (final raw in names) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final k = t.toLowerCase();
      if (byLower.containsKey(k)) {
        byLower[k] = pickCanonicalDisplayName(byLower[k]!, t);
      } else {
        byLower[k] = defaultCanonicalForLower(k) ?? t;
      }
    }
    final out = byLower.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Categorie **attive** da `dpi_categories` — stessa logica della pagina «Categorie DPI»
  /// (nessun elenco hardcoded aggiuntivo che duplica i cordini ecc.).
  static Future<List<String>> listCategories() async {
    try {
      final res = await SupabaseService.client
          .from(_table)
          .select('name')
          .eq('active', true)
          .order('name');
      final fromDb = (res as List)
          .map((e) => (e['name'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (fromDb.isEmpty) {
        return List<String>.from(defaultCategories);
      }
      return mergeUniqueCategoryNames(fromDb, seedDefaults: false);
    } catch (_) {
      return List<String>.from(defaultCategories);
    }
  }

  static Future<void> addCategory(String name) async {
    final v = name.trim();
    if (v.isEmpty) return;
    await SupabaseService.client
        .from(_table)
        .upsert({'name': v, 'active': true}, onConflict: 'name');
  }

  static Future<List<Map<String, dynamic>>> listAll() async {
    final res = await SupabaseService.client
        .from(_table)
        .select('name, active, created_at, updated_at')
        .order('name');
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> renameCategory({
    required String oldName,
    required String newName,
  }) async {
    final from = oldName.trim();
    final to = newName.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;
    await SupabaseService.client.from(_table).upsert({
      'name': to,
      'active': true,
    }, onConflict: 'name');
    await SupabaseService.client
        .from('dpi_dotazioni')
        .update({'categoria': to})
        .eq('categoria', from);
    await SupabaseService.client.from(_table).delete().eq('name', from);
  }

  static Future<void> setActive({
    required String name,
    required bool active,
  }) async {
    final v = name.trim();
    if (v.isEmpty) return;
    await SupabaseService.client
        .from(_table)
        .update({'active': active})
        .eq('name', v);
  }

  static Future<void> deleteCategory(String name) async {
    final v = name.trim();
    if (v.isEmpty) return;
    await SupabaseService.client.from(_table).delete().eq('name', v);
  }
}

