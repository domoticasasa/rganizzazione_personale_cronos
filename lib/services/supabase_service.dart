import 'package:supabase_flutter/supabase_flutter.dart';

/// Servizio centralizzato Supabase
/// Usa i valori REALI del tuo progetto (bjdimalvbdablzoctrsf)
class SupabaseService {
  SupabaseService._();

  // 🔐 Salviamo l'anon key in un campo privato e la esponiamo con un getter
  static const String _supabaseUrl = 'https://bjdimalvbdablzoctrsf.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqZGltYWx2YmRhYmx6b2N0cnNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5MzczNTcsImV4cCI6MjA4NzUxMzM1N30.Lm4GHd1CWdSMMI87Wx2eBrHcmqFtMXO31hO7Q3BsYyc';

  static String get supabaseUrl => _supabaseUrl;

  /// Getter pubblico per recuperare l'anon key quando serve negli headers
  static String get anonKey => _anonKey;

  /// Client Supabase globale
  static SupabaseClient get client => Supabase.instance.client;

  /// Inizializzazione Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: _anonKey,

      // Opzionale ma consigliato su desktop per persistenza sessione:
      // authFlowType: AuthFlowType.pkce,
      // localStorage: const LocalStorage(),
    );

    // ignore: avoid_print
    print('✅ Supabase inizializzato correttamente');
    // ignore: avoid_print
    print('🔗 URL: $_supabaseUrl');
  }
}