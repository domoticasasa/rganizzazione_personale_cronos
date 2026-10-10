/// Stub non-web: nessuna biometria piattaforma.
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

abstract final class DocFirmaWebAuthn {
  DocFirmaWebAuthn._();

  static Future<bool> canAttemptPlatformAuth() async => false;

  static Future<bool> isPlatformAuthenticatorAvailable() async => false;

  static Future<String?> register({
    required String userId,
    required String userName,
    required String displayName,
  }) async =>
      null;

  static Future<DocFirmaWebAuthnResult> registerDetailed({
    required String userId,
    required String userName,
    required String displayName,
  }) async =>
      const DocFirmaWebAuthnResult(
        ok: false,
        errorMessage: 'Impronta disponibile solo su web mobile HTTPS.',
      );

  static Future<bool> authenticate({
    required String credentialIdBase64Url,
  }) async =>
      false;

  static Future<DocFirmaWebAuthnResult> authenticateDetailed({
    String? credentialIdBase64Url,
  }) async =>
      const DocFirmaWebAuthnResult(
        ok: false,
        errorMessage: 'Impronta disponibile solo su web mobile HTTPS.',
      );
}
