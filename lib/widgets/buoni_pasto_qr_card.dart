import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/buoni_pasto_qr_payload.dart';

/// Card QR per ristorante (anteprima + export PNG).
class BuoniPastoQrCard extends StatelessWidget {
  BuoniPastoQrCard({
    super.key,
    required this.ristoranteNome,
    required this.qrToken,
    this.size = 280,
    GlobalKey? repaintBoundaryKey,
  }) : repaintBoundaryKey = repaintBoundaryKey ?? GlobalKey();

  final String ristoranteNome;
  final String qrToken;
  final double size;
  final GlobalKey repaintBoundaryKey;

  String get _payload => encodeBuoniPastoQrPrintPayload(qrToken);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintBoundaryKey,
      child: Container(
        width: size,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black26),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 36,
              errorBuilder: (_, _, _) => const Text(
                'CRONOS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ristoranteNome,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Scansiona per registrare il buono pasto',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            QrImageView(
              data: _payload,
              version: QrVersions.auto,
              size: size * 0.55,
              backgroundColor: Colors.white,
            ),
            if (_payload.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _payload,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<Uint8List?> captureBuoniPastoQrPng(GlobalKey key) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 3);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}
