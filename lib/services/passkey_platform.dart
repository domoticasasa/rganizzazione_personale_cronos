import 'passkey_platform_io.dart'
    if (dart.library.html) 'passkey_platform_web.dart' as impl;

/// True se la piattaforma può eseguire una cerimonia Passkey/WebAuthn.
bool get passkeyPlatformSupported => impl.passkeyPlatformSupported;
