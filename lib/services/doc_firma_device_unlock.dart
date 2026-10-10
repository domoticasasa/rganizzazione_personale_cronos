import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'doc_firma_webauthn.dart';

/// Seconda conferma dispositivo (impronta / PIN / segno) per firma documenti.
abstract final class DocFirmaDeviceUnlock {
  DocFirmaDeviceUnlock._();

  static const _pinHashKey = 'doc_firma_unlock_pin_hash_v1';
  static const _pinSaltKey = 'doc_firma_unlock_pin_salt_v1';
  static const _patternHashKey = 'doc_firma_unlock_pattern_hash_v1';
  static const _webAuthnCredKey = 'doc_firma_unlock_webauthn_cred_v1';
  static const _deviceInstallIdKey = 'doc_firma_unlock_device_install_id_v1';

  static String _hash(String salt, String value) =>
      sha256.convert(utf8.encode('$salt::$value')).toString();

  static String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static Future<bool> hasPin() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_pinHashKey) ?? '').isNotEmpty;
  }

  static Future<bool> hasPattern() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_patternHashKey) ?? '').isNotEmpty;
  }

  static Future<bool> hasWebAuthn() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_webAuthnCredKey) ?? '').isNotEmpty;
  }

  static Future<bool> isPlatformAuthenticatorAvailable() =>
      DocFirmaWebAuthn.isPlatformAuthenticatorAvailable();

  static Future<void> setPin(String pin) async {
    final clean = pin.trim();
    if (clean.length < 4 || clean.length > 8 || int.tryParse(clean) == null) {
      throw StateError('PIN: inserisci 4–8 cifre');
    }
    final salt = _randomSalt();
    final p = await SharedPreferences.getInstance();
    await p.setString(_pinSaltKey, salt);
    await p.setString(_pinHashKey, _hash(salt, clean));
  }

  static Future<bool> verifyPin(String pin) async {
    final p = await SharedPreferences.getInstance();
    final salt = p.getString(_pinSaltKey) ?? '';
    final expect = p.getString(_pinHashKey) ?? '';
    if (salt.isEmpty || expect.isEmpty) return false;
    return _hash(salt, pin.trim()) == expect;
  }

  static Future<void> clearPin() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pinHashKey);
    await p.remove(_pinSaltKey);
  }

  /// Segno = sequenza di indici 0..8 (griglia 3×3), almeno 4 punti.
  static Future<void> setPattern(List<int> cells) async {
    if (cells.length < 4) {
      throw StateError('Segno: collega almeno 4 punti');
    }
    final normalized = cells.join('-');
    final salt = _randomSalt();
    final p = await SharedPreferences.getInstance();
    await p.setString(_patternHashKey, _hash(salt, normalized));
    await p.setString('${_patternHashKey}_salt', salt);
  }

  static Future<bool> verifyPattern(List<int> cells) async {
    final p = await SharedPreferences.getInstance();
    final salt = p.getString('${_patternHashKey}_salt') ?? '';
    final expect = p.getString(_patternHashKey) ?? '';
    if (salt.isEmpty || expect.isEmpty) return false;
    return _hash(salt, cells.join('-')) == expect;
  }

  static Future<void> clearPattern() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_patternHashKey);
    await p.remove('${_patternHashKey}_salt');
  }

  static Future<bool> registerWebAuthn({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    final r = await DocFirmaWebAuthn.registerDetailed(
      userId: userId,
      userName: userName,
      displayName: displayName,
    );
    if (!r.ok || (r.credentialId ?? '').isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    await p.setString(_webAuthnCredKey, r.credentialId!);
    return true;
  }

  /// Registrazione con messaggio errore dettagliato.
  static Future<DocFirmaWebAuthnResult> registerWebAuthnDetailed({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    final r = await DocFirmaWebAuthn.registerDetailed(
      userId: userId,
      userName: userName,
      displayName: displayName,
    );
    if (r.ok && (r.credentialId ?? '').isNotEmpty) {
      final p = await SharedPreferences.getInstance();
      await p.setString(_webAuthnCredKey, r.credentialId!);
    }
    return r;
  }

  static Future<bool> authenticateWebAuthn() async {
    final p = await SharedPreferences.getInstance();
    final credId = p.getString(_webAuthnCredKey) ?? '';
    if (credId.isEmpty) return false;
    return DocFirmaWebAuthn.authenticate(credentialIdBase64Url: credId);
  }

  static Future<DocFirmaWebAuthnResult> authenticateWebAuthnDetailed() async {
    final p = await SharedPreferences.getInstance();
    final credId = p.getString(_webAuthnCredKey) ?? '';
    if (credId.isEmpty) {
      return const DocFirmaWebAuthnResult(
        ok: false,
        errorMessage: 'Nessuna impronta registrata. Attivala prima.',
      );
    }
    return DocFirmaWebAuthn.authenticateDetailed(
      credentialIdBase64Url: credId,
    );
  }

  /// Rimuove credenziale salvata (utile se fallisce spesso).
  static Future<void> clearWebAuthn() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_webAuthnCredKey);
  }

  static Future<String> _installationId() async {
    final p = await SharedPreferences.getInstance();
    final existing = (p.getString(_deviceInstallIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = _randomSalt();
    await p.setString(_deviceInstallIdKey, created);
    return created;
  }

  static Future<Map<String, dynamic>> buildDeviceProof({
    required String unlockMethod,
    required bool setup,
  }) async {
    final installId = await _installationId();
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    final tzName = DateTime.now().timeZoneName;
    final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
    final platform = defaultTargetPlatform.name;
    final payload = '$installId|$platform|$locale|$tzName|$tzOffsetMin';
    final digest = sha256.convert(utf8.encode(payload)).toString();
    return <String, dynamic>{
      'method': unlockMethod,
      'setup': setup,
      'required': true,
      'platform': kIsWeb ? 'web' : 'native',
      'platform_target': platform,
      'locale': locale,
      'timezone': tzName,
      'tz_offset_min': tzOffsetMin,
      // Codice dispositivo pseudonimo (stabile su questo browser/device).
      'device_code': digest.substring(0, 16).toUpperCase(),
      'device_hash': digest,
    };
  }

  /// Sempre obbligatoria prima della firma.
  static bool requiresSecondFactor({
    required bool isWeb,
    required bool isMobileUi,
  }) =>
      true;

  static Future<Map<String, dynamic>> status() async {
    return {
      'has_pin': await hasPin(),
      'has_pattern': await hasPattern(),
      'has_webauthn': await hasWebAuthn(),
      'platform_auth_available': await isPlatformAuthenticatorAvailable(),
      'is_web': kIsWeb,
    };
  }
}
