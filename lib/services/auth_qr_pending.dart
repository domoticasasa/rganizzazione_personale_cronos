import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_qr_login_service.dart';
import 'auth_qr_storage_stub.dart'
    if (dart.library.html) 'auth_qr_storage_web.dart' as store;

/// Pairing login QR: codice in URL `?auth_qr=CODE`.
/// Un QR vecchio in memoria non deve bloccare il login sul telefono.
abstract final class AuthQrPending {
  AuthQrPending._();

  static const _prefsKey = 'cronos_pending_auth_qr';
  static const _prefsAtKey = 'cronos_pending_auth_qr_at_ms';
  static const _maxAge = Duration(minutes: 20);
  static final Set<String> _consumed = <String>{};

  /// Solo query/hash della pagina attuale (non storage).
  static String? codeFromUrl([Uri? uri]) {
    final u = uri ?? Uri.base;
    final raw = (u.queryParameters['auth_qr'] ?? '').trim().toUpperCase();
    if (raw.isNotEmpty) return raw;
    final frag = u.fragment;
    if (frag.contains('auth_qr=')) {
      final qIndex = frag.indexOf('?');
      if (qIndex >= 0) {
        final qp = Uri.splitQueryString(frag.substring(qIndex + 1));
        final f = (qp['auth_qr'] ?? '').trim().toUpperCase();
        if (f.isNotEmpty) return f;
      }
    }
    return null;
  }

  static String? codeFromUri([Uri? uri]) => codeFromUrl(uri);

  static bool get hasPendingCode {
    final c = codeFromUrl();
    return c != null && !_consumed.contains(c);
  }

  static Future<void> remember(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, c);
    await p.setInt(_prefsAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearPending() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
    await p.remove(_prefsAtKey);
    store.clearAuthQrFromSessionStorage();
  }

  static Future<String?> peekPending() async {
    final fromUrl = codeFromUrl();
    if (fromUrl != null && !_consumed.contains(fromUrl)) return fromUrl;

    final p = await SharedPreferences.getInstance();
    final stored = (p.getString(_prefsKey) ?? '').trim().toUpperCase();
    if (stored.isEmpty || _consumed.contains(stored)) return null;
    final at = p.getInt(_prefsAtKey);
    if (at == null) {
      await clearPending();
      return null;
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age > _maxAge) {
      await clearPending();
      return null;
    }
    return stored;
  }

  static bool _isStaleError(String msg) {
    final l = msg.toLowerCase();
    return l.contains('scaduto') ||
        l.contains('non valido') ||
        l.contains('non trovata') ||
        l.contains('non utilizzabile') ||
        l.contains('expired') ||
        l.contains('410');
  }

  /// Se c’è un QR pending e sessione attiva, conferma l’accesso sul PC.
  /// Ritorna `null` se ok / niente da fare / QR vecchio ignorato.
  static Future<String?> tryApproveForCurrentSession(
    BuildContext? context, {
    bool showSuccessSnack = true,
  }) async {
    final code = await peekPending();
    if (code == null) return null;
    try {
      await AuthQrLoginService.approve(publicCode: code);
      _consumed.add(code);
      await clearPending();
      if (showSuccessSnack && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Accesso sul PC confermato. Torna al computer: il dialog si chiude da solo.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }
      return null;
    } catch (e) {
      final msg = e.toString();
      if (_isStaleError(msg)) {
        await clearPending();
        return null;
      }
      await remember(code);
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conferma PC non riuscita: $msg'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return msg;
    }
  }

  static Future<String?> takePending() => peekPending();
}
