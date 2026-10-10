import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_session_heal.dart';
import 'supabase_service.dart';

class AuthQrStartResult {
  const AuthQrStartResult({
    required this.id,
    required this.publicCode,
    required this.claimSecret,
    required this.expiresAt,
    required this.phoneUrl,
  });

  final String id;
  final String publicCode;
  final String claimSecret;
  final DateTime expiresAt;
  final String phoneUrl;
}

/// Login PC ↔ telefono via QR (non usa Windows Hello / WebAuthn hybrid).
abstract final class AuthQrLoginService {
  AuthQrLoginService._();

  static Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'auth-qr-login',
        body: body,
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw StateError('Risposta auth-qr-login non valida.');
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final err = details['error'] ?? details['message'];
        if (err != null) throw StateError(err.toString());
      }
      throw StateError(e.reasonPhrase ?? 'Errore auth-qr-login (${e.status})');
    }
  }

  static Future<AuthQrStartResult> start({required String origin}) async {
    final data = await _invoke({'action': 'start'});
    if (data['ok'] != true) {
      throw StateError((data['error'] ?? 'Avvio QR fallito').toString());
    }
    final code = (data['public_code'] ?? '').toString().trim().toUpperCase();
    const canonical = 'https://www.gestopro360.it';
    return AuthQrStartResult(
      id: (data['id'] ?? '').toString(),
      publicCode: code,
      claimSecret: (data['claim_secret'] ?? '').toString(),
          expiresAt: DateTime.tryParse((data['expires_at'] ?? '').toString()) ??
          DateTime.now().add(const Duration(minutes: 15)),
      phoneUrl: '$canonical/login?auth_qr=$code',
    );
  }

  static Future<Map<String, dynamic>> poll({
    required String id,
    required String claimSecret,
  }) {
    return _invoke({
      'action': 'poll',
      'id': id,
      'claim_secret': claimSecret,
    });
  }

  static Future<void> approve({required String publicCode}) async {
    final session = await AuthSessionHeal.ensureFreshSession();
    if (session == null) {
      throw StateError(
        'Sessione telefono scaduta o non valida. '
        'Accedi di nuovo con password sul telefono, poi conferma il QR.',
      );
    }
    final refresh = (session.refreshToken ?? '').trim();
    if (refresh.isEmpty) {
      throw StateError(
        'Sessione telefono senza refresh token. Esci e rifai Accedi.',
      );
    }
    final data = await _invoke({
      'action': 'approve',
      'public_code': publicCode.trim().toUpperCase(),
      'access_token': session.accessToken,
      'refresh_token': refresh,
    });
    if (data['ok'] != true) {
      throw StateError((data['error'] ?? 'Conferma QR fallita').toString());
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('auth-qr approve ok code=$publicCode');
    }
  }

  static Future<void> cancel({
    required String id,
    required String claimSecret,
  }) async {
    try {
      await _invoke({
        'action': 'cancel',
        'id': id,
        'claim_secret': claimSecret,
      });
    } catch (_) {}
  }
}
