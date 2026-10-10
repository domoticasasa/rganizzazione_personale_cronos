import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../pages/dipendente_viaggio_mezzo_scan_page.dart';
import 'auth_callback_bootstrap_stub.dart'
    if (dart.library.html) 'auth_callback_bootstrap_web.dart';
import 'viaggi_mezzi_qr_payload.dart';

/// Deep link web: `https://www.gestopro360.it/?vm={token}` (QR fotocamera telefono).
abstract final class ViaggioMezzoScanDeepLink {
  ViaggioMezzoScanDeepLink._();

  static String? _pendingToken;

  /// Chiama all'avvio, prima che splash/login riscrivano la URL.
  static void captureFromBootUri(Uri uri) {
    if (!kIsWeb) return;
    final fromUri = parseViaggiMezziQrTokenFromUri(uri);
    final stored = parseViaggiMezziQrToken(readStoredViaggioMezzoVm() ?? '');
    final token = fromUri ?? stored;
    if (token != null && token.isNotEmpty) {
      _pendingToken = token;
    }
  }

  static String? takePending() {
    final token = _pendingToken;
    _pendingToken = null;
    clearStoredViaggioMezzoVm();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  /// Dopo login/home: apre la scansione se il QR è arrivato dalla fotocamera.
  static Future<void> openPendingScanIfAny(
    BuildContext context, {
    required int userId,
  }) async {
    final token = takePending();
    if (token == null) return;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DipendenteViaggioMezzoScanPage(
          userId: userId,
          initialQr: token,
        ),
      ),
    );
  }
}
