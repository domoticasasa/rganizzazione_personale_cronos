import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Esito WebAuthn con messaggio utente.
class DocFirmaWebAuthnResult {
  const DocFirmaWebAuthnResult({
    required this.ok,
    this.credentialId,
    this.errorMessage,
  });

  final bool ok;
  final String? credentialId;
  final String? errorMessage;
}

/// WebAuthn piattaforma (impronta / Face ID) via browser.
///
/// Usa solo `dart:js_interop` / `package:web` per i BufferSource:
/// `Uint8List.toJS` crea un vero `JSUint8Array` (con `new`).
/// L’approccio `dart:js` + `Uint8Array.apply(...)` fallisce su Chrome Android
/// con: "Constructor Uint8Array requires 'new'".
abstract final class DocFirmaWebAuthn {
  DocFirmaWebAuthn._();

  /// Secure context + API WebAuthn presenti (anche se isUVPAA mente su Safari).
  static Future<bool> canAttemptPlatformAuth() async {
    try {
      if (!web.window.isSecureContext) return false;
      final pk = globalContext.getProperty('PublicKeyCredential'.toJS);
      return pk != null && !pk.isUndefinedOrNull;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPlatformAuthenticatorAvailable() async {
    try {
      if (!await canAttemptPlatformAuth()) return false;
      final pk = globalContext.getProperty('PublicKeyCredential'.toJS);
      if (pk == null || pk.isUndefinedOrNull) return false;
      final pkObj = pk as JSObject;
      final fn = pkObj.getProperty(
        'isUserVerifyingPlatformAuthenticatorAvailable'.toJS,
      );
      if (fn == null || fn.isUndefinedOrNull) {
        // Safari / WebView: API presente ma senza helper → prova comunque.
        return true;
      }
      final promise = pkObj.callMethod(
        'isUserVerifyingPlatformAuthenticatorAvailable'.toJS,
      );
      final result = await (promise as JSPromise).toDart;
      if (result == null || result.isUndefinedOrNull) return true;
      return (result as JSBoolean).toDart;
    } catch (_) {
      // Non bloccare: su iOS la check a volte fallisce ma Face ID funziona.
      return await canAttemptPlatformAuth();
    }
  }

  static String _friendlyFromCatch(Object e) {
    final raw = _errorText(e);
    final lower = raw.toLowerCase();
    if (lower.contains('notallowed') || lower.contains('not allowed')) {
      return 'Sblocco annullato o bloccato. Riprova con impronta / Face ID / PIN del telefono.';
    }
    if (lower.contains('invalidstate')) {
      return 'Credenziale già presente. Riprova lo sblocco del telefono.';
    }
    if (lower.contains('notsupported') || lower.contains('not supported')) {
      return 'Sblocco di sistema non supportato in questo browser. Usa Chrome o Safari su HTTPS.';
    }
    if (lower.contains('uint8array') && lower.contains('new')) {
      return 'Errore tecnico browser sullo sblocco. Aggiorna la pagina e riprova.';
    }
    if (lower.contains('securityerror') || lower.contains('secure')) {
      return 'Contesto non sicuro o dominio non valido per WebAuthn.';
    }
    return 'Sblocco telefono non riuscito. ($raw)';
  }

  static String _errorText(Object e) {
    final s = e.toString();
    // Preferisci message JS se presente nel toString.
    return s;
  }

  static Uint8List _randomChallenge([int len = 32]) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(len, (_) => r.nextInt(256)));
  }

  /// BufferSource corretto per WebAuthn (JS `Uint8Array` via interop ufficiale).
  static JSUint8Array _toJsBytes(List<int> bytes) {
    final copy = bytes is Uint8List ? Uint8List.fromList(bytes) : Uint8List.fromList(bytes);
    return copy.toJS;
  }

  static String _rawIdToBase64Url(JSAny rawId) {
    // rawId WebAuthn = ArrayBuffer → JSUint8Array(buffer) usa `new`.
    final view = JSUint8Array(rawId as JSArrayBuffer);
    return base64UrlEncode(view.toDart).replaceAll('=', '');
  }

  static JSUint8Array _base64UrlToJsBytes(String b64) {
    var s = b64.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return _toJsBytes(base64Decode(s));
  }

  static String _rpId() {
    final host = web.window.location.hostname;
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return host.isEmpty ? 'localhost' : host;
    }
    return host;
  }

  static JSObject _jsMap(Map<String, JSAny?> map) {
    final o = JSObject();
    for (final e in map.entries) {
      final v = e.value;
      if (v != null) o.setProperty(e.key.toJS, v);
    }
    return o;
  }

  static JSObject _buildCreateOptions({
    required Uint8List challenge,
    required List<int> userIdBytes,
    required String userName,
    required String displayName,
  }) {
    final idBytes =
        userIdBytes.length > 64 ? userIdBytes.sublist(0, 64) : userIdBytes;

    final pubKeyCredParams = <JSAny>[
      _jsMap({
        'type': 'public-key'.toJS,
        'alg': (-7).toJS,
      }),
      _jsMap({
        'type': 'public-key'.toJS,
        'alg': (-257).toJS,
      }),
    ].toJS;

    final publicKey = _jsMap({
      'rp': _jsMap({
        'name': 'CRONOS GESTOPRO'.toJS,
        'id': _rpId().toJS,
      }),
      'user': _jsMap({
        'name': userName.toJS,
        'displayName': displayName.toJS,
        // Mai passare List Dart: serve TypedArray.
        'id': _toJsBytes(idBytes),
      }),
      'challenge': _toJsBytes(challenge),
      'pubKeyCredParams': pubKeyCredParams,
      'authenticatorSelection': _jsMap({
        'authenticatorAttachment': 'platform'.toJS,
        'userVerification': 'required'.toJS,
        'residentKey': 'preferred'.toJS,
      }),
      'timeout': (90000).toJS,
      'attestation': 'none'.toJS,
    });

    return _jsMap({'publicKey': publicKey});
  }

  static JSObject _buildGetOptions({
    required Uint8List challenge,
    String? credentialIdBase64Url,
  }) {
    final publicKey = _jsMap({
      'timeout': (90000).toJS,
      'userVerification': 'required'.toJS,
      'rpId': _rpId().toJS,
      'challenge': _toJsBytes(challenge),
    });

    final id = (credentialIdBase64Url ?? '').trim();
    if (id.isNotEmpty) {
      final allow = <JSAny>[
        _jsMap({
          'type': 'public-key'.toJS,
          'transports': <JSAny>['internal'.toJS].toJS,
          'id': _base64UrlToJsBytes(id),
        }),
      ].toJS;
      publicKey.setProperty('allowCredentials'.toJS, allow);
    }

    return _jsMap({'publicKey': publicKey});
  }

  static Future<JSAny?> _credentialsCall(String method, JSObject options) async {
    final credentials = web.window.navigator.credentials as JSObject?;
    if (credentials == null) {
      throw StateError('Browser senza supporto credenziali.');
    }
    final promise = credentials.callMethod(method.toJS, options);
    return await (promise as JSPromise<JSAny?>).toDart;
  }

  static Future<String?> register({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    final r = await registerDetailed(
      userId: userId,
      userName: userName,
      displayName: displayName,
    );
    return r.ok ? r.credentialId : null;
  }

  static Future<DocFirmaWebAuthnResult> registerDetailed({
    required String userId,
    required String userName,
    required String displayName,
  }) async {
    try {
      if (!web.window.isSecureContext) {
        return const DocFirmaWebAuthnResult(
          ok: false,
          errorMessage: 'Serve HTTPS per usare l\'impronta.',
        );
      }

      final safeName =
          userName.trim().isEmpty ? 'dipendente' : userName.trim();
      final safeDisplay =
          displayName.trim().isEmpty ? safeName : displayName.trim();
      final options = _buildCreateOptions(
        challenge: _randomChallenge(),
        userIdBytes: utf8.encode(userId.trim().isEmpty ? safeName : userId),
        userName: safeName,
        displayName: safeDisplay,
      );

      final cred = await _credentialsCall('create', options);
      if (cred == null || cred.isUndefinedOrNull) {
        return const DocFirmaWebAuthnResult(
          ok: false,
          errorMessage: 'Registrazione impronta annullata.',
        );
      }

      final rawId = (cred as JSObject).getProperty('rawId'.toJS);
      if (rawId == null || rawId.isUndefinedOrNull) {
        return const DocFirmaWebAuthnResult(
          ok: false,
          errorMessage: 'Risposta impronta non valida.',
        );
      }

      return DocFirmaWebAuthnResult(
        ok: true,
        credentialId: _rawIdToBase64Url(rawId),
      );
    } catch (e) {
      // ignore: avoid_print
      print('DocFirmaWebAuthn.register: $e');
      // Non chiamare authenticate qui: raddoppierebbe la richiesta impronta
      // e, con visibilitychange, poteva entrare in loop. Gestisce il gate.
      return DocFirmaWebAuthnResult(
        ok: false,
        errorMessage: _friendlyFromCatch(e),
      );
    }
  }

  static Future<bool> authenticate({
    required String credentialIdBase64Url,
  }) async {
    final r = await authenticateDetailed(
      credentialIdBase64Url: credentialIdBase64Url,
    );
    return r.ok;
  }

  static Future<DocFirmaWebAuthnResult> authenticateDetailed({
    String? credentialIdBase64Url,
  }) async {
    try {
      final options = _buildGetOptions(
        challenge: _randomChallenge(),
        credentialIdBase64Url: credentialIdBase64Url,
      );
      final assertion = await _credentialsCall('get', options);
      if (assertion == null || assertion.isUndefinedOrNull) {
        return const DocFirmaWebAuthnResult(
          ok: false,
          errorMessage: 'Verifica impronta annullata.',
        );
      }
      final rawId = (assertion as JSObject).getProperty('rawId'.toJS);
      final id = (rawId == null || rawId.isUndefinedOrNull)
          ? null
          : _rawIdToBase64Url(rawId);
      return DocFirmaWebAuthnResult(ok: true, credentialId: id);
    } catch (e) {
      // ignore: avoid_print
      print('DocFirmaWebAuthn.authenticate: $e');
      return DocFirmaWebAuthnResult(
        ok: false,
        errorMessage: _friendlyFromCatch(e),
      );
    }
  }
}
