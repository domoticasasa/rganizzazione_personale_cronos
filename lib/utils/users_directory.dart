import '../services/supabase_service.dart';
import 'roles.dart';

/// Account nascosti dalle liste/selettori (`users.hidden_from_directory`)
/// e, di default, anche gli utenti con ruolo **Admin vista**.
/// Login e permessi restano attivi; in Gestione Dipendenti restano visibili.
abstract final class UsersDirectory {
  UsersDirectory._();

  static bool isHiddenFromDirectory(Map<String, dynamic> row) {
    final v = row['hidden_from_directory'];
    if (v is bool) return v;
    if (v == null) return false;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  static bool isVisibleInDirectory(Map<String, dynamic> row) =>
      !isHiddenFromDirectory(row);

  static List<Map<String, dynamic>> onlyVisible(
    Iterable<Map<String, dynamic>> rows,
  ) {
    return rows.where(isVisibleInDirectory).toList(growable: false);
  }

  /// Colonna da includere nei select (tollerante se assente a runtime).
  static const String selectFlag = 'hidden_from_directory';

  static String normalizePersonName(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Anagrafiche di servizio (es. «Nome Cognome (admin)»).
  static bool isHiddenServicePersonaleName(String raw) {
    final n = normalizePersonName(raw);
    if (n.isEmpty) return false;
    if (n.contains('(admin)') || n.contains('[admin]')) return true;
    const known = <String>{
      'cibuc alexandru (admin)',
      'alexandru cibuc (admin)',
      'alexandru admin cibuc',
      'alexandru cibuc admin',
    };
    return known.contains(n);
  }

  static void _addLinkKeys(Set<String> keys, Map<String, dynamic> m) {
    for (final k in ['auth_id', 'id_uuid', 'email', 'username']) {
      final v = (m[k] ?? '').toString().trim().toLowerCase();
      if (v.isNotEmpty) keys.add(v);
    }
    final name = normalizePersonName((m['full_name'] ?? '').toString());
    if (name.isNotEmpty) keys.add('name:$name');
  }

  /// Chiavi per abbinare `personale` agli utenti da escludere dalle liste.
  ///
  /// [includeAdminVistaRole]: se true (default), esclude anche chi ha ruolo
  /// Admin vista (primario o secondario). Mettere false solo in Gestione Dipendenti.
  static Future<Set<String>> loadHiddenLinkKeys({
    bool includeAdminVistaRole = true,
  }) async {
    final keys = <String>{};
    try {
      final res = await SupabaseService.client
          .from('users')
          .select(
            'auth_id, id_uuid, email, full_name, username, hidden_from_directory',
          )
          .eq('hidden_from_directory', true);
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (!isHiddenFromDirectory(m)) continue;
        _addLinkKeys(keys, m);
      }
    } catch (_) {}

    if (includeAdminVistaRole) {
      try {
        final res = await SupabaseService.client
            .from('users')
            .select(
              'auth_id, id_uuid, email, full_name, username, role, secondary_role',
            );
        for (final raw in (res as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final role = (m['role'] ?? '').toString();
          final secondary = (m['secondary_role'] ?? '').toString();
          if (!isAdminVistaRole(role) && !isAdminVistaRole(secondary)) {
            continue;
          }
          _addLinkKeys(keys, m);
        }
      } catch (_) {}
    }

    return keys;
  }

  /// True se la riga `personale` è un account nascosto / di servizio / Admin vista.
  static bool isPersonaleHiddenFromDirectory(
    Map<String, dynamic> personaleRow,
    Set<String> hiddenKeys,
  ) {
    if (isHiddenFromDirectory(personaleRow)) return true;
    final name = (personaleRow['full_name'] ?? '').toString();
    if (isHiddenServicePersonaleName(name)) return true;
    if (hiddenKeys.isEmpty) return false;
    final userId =
        (personaleRow['user_id'] ?? '').toString().trim().toLowerCase();
    final email = (personaleRow['email'] ?? '').toString().trim().toLowerCase();
    final idUuid =
        (personaleRow['id_uuid'] ?? '').toString().trim().toLowerCase();
    final nameKey = normalizePersonName(name);
    if (userId.isNotEmpty && hiddenKeys.contains(userId)) return true;
    if (email.isNotEmpty && hiddenKeys.contains(email)) return true;
    if (idUuid.isNotEmpty && hiddenKeys.contains(idUuid)) return true;
    if (nameKey.isNotEmpty && hiddenKeys.contains('name:$nameKey')) return true;
    return false;
  }

  static List<Map<String, dynamic>> onlyVisiblePersonale(
    Iterable<Map<String, dynamic>> rows,
    Set<String> hiddenKeys,
  ) {
    return rows
        .where((r) => !isPersonaleHiddenFromDirectory(r, hiddenKeys))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> visiblePersonale(
    Iterable<dynamic> rows, {
    bool includeAdminVistaRole = true,
  }) async {
    final maps = rows.map((e) => Map<String, dynamic>.from(e as Map));
    final keys = await loadHiddenLinkKeys(
      includeAdminVistaRole: includeAdminVistaRole,
    );
    return onlyVisiblePersonale(maps, keys);
  }
}
