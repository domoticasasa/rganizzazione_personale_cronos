import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart'; // espone SupabaseService.anonKey

class UserAdminService {
  UserAdminService(this._client);
  final SupabaseClient _client;

  // Attende che la sessione venga ripristinata (max 5s)
  Future<Session> _waitForSession({Duration timeout = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    var session = _client.auth.currentSession;
    if (session != null) return session;

    while (DateTime.now().difference(start) < timeout) {
      await Future.delayed(const Duration(milliseconds: 150));
      session = _client.auth.currentSession;
      if (session != null) return session;
    }
    throw Exception('⚠️ Nessuna sessione valida. Effettua di nuovo il login.');
  }

  // Restituisce un JWT valido (3 parti) oppure errore
  Future<String> _getValidAccessToken() async {
    final session = await _waitForSession();
    final token = session.accessToken;
    if (token.isEmpty || token.split('.').length != 3) {
      throw Exception('⚠️ Token JWT non valido. Rieffettua login.');
    }
    return token;
  }

  /// Aggiorna dipendente (chiama la Edge Function admin-update-employee)
  /// Invia soltanto i campi presenti (null-safety sul body)
  Future<void> updateEmployee({
    int? userId,
    String? authId,
    String? email,
    String? fullName,
    String? username,
    bool? active,
    String? role,
  }) async {
    // 1) Token sicuro e valido
    final token = await _getValidAccessToken();

    // 2) Body dinamico
    final body = <String, dynamic>{
      'user_id': ?userId,
      'auth_id': ?authId,
      'email': ?email,
      'full_name': ?fullName,
      'username': ?username,
      'active': ?active,
      'role': ?role,
    };

    // 3) URL della Function sul progetto configurato in SupabaseService
    //    (prima puntava al vecchio progetto vvnpamypxexdtvruzecp, spento).
    final functionsUrl =
        '${SupabaseService.supabaseUrl}/functions/v1/admin-update-employee';

    // 4) POST HTTP "puro" (header non filtrati)
    final uri = Uri.parse(functionsUrl);
    final response = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',          // 🔑 session token
            'apikey': SupabaseService.anonKey,         // 🔑 anon key del progetto
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    // 5) Log utili
    // ignore: avoid_print
    print('DEBUG → FUNCTION STATUS: ${response.statusCode}');
    // ignore: avoid_print
    print('DEBUG → FUNCTION BODY  : ${response.body}');

    // 6) Gestione errori
    if (response.statusCode != 200) {
      // Prova a estrarre un JSON { error: ... } dal body, altrimenti passa testo grezzo
      try {
        final m = jsonDecode(response.body) as Map<String, dynamic>;
        final err = (m['error'] ?? m['message'] ?? response.body).toString();
        throw Exception('Errore funzione: $err');
      } catch (_) {
        throw Exception('Errore funzione: ${response.body}');
      }
    }
  }
}