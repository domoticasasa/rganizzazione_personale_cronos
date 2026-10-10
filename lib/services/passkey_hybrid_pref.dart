import 'passkey_hybrid_pref_stub.dart'
    if (dart.library.html) 'passkey_hybrid_pref_web.dart' as impl;

/// Su browser desktop: WebAuthn hybrid (QR telefono Windows), non Hello locale.
void setPreferHybridPasskey(bool value) => impl.setPreferHybridPasskey(value);

/// Su browser desktop: preferisci Windows Hello / questo PC, poi il telefono.
void setPreferPlatformPasskey(bool value) =>
    impl.setPreferPlatformPasskey(value);

bool get preferHybridPasskeyActive => impl.preferHybridPasskeyActive;
