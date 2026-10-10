import 'package:flutter/foundation.dart';
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_web/passkeys_web.dart';

/// Registra [PasskeysWeb] se il registrant Flutter non l'ha incluso
/// (altrimenti resta lo stub MethodChannel → UnimplementedError).
void ensurePasskeysWebRegistered() {
  if (!kIsWeb) return;
  if (PasskeysPlatform.instance is PasskeysWeb) return;
  PasskeysWeb.registerWith();
}
