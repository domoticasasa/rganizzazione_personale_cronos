import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/viaggi_mezzi_qr_payload.dart';

class ViaggiMezziQrCard extends StatelessWidget {
  ViaggiMezziQrCard({
    super.key,
    required this.mezzoLabel,
    required this.qrToken,
    this.size = 240,
    GlobalKey? repaintBoundaryKey,
  }) : repaintBoundaryKey = repaintBoundaryKey ?? GlobalKey();

  final String mezzoLabel;
  final String qrToken;
  final double size;
  final GlobalKey repaintBoundaryKey;

  String get _payload => encodeViaggiMezziQrPrintPayload(qrToken);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintBoundaryKey,
      child: Container(
        width: size,
        padding: const EdgeInsets.all(16),
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
              height: 28,
              errorBuilder: (_, _, _) => const Text(
                'CRONOS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mezzoLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fotocamera del telefono: inizio e fine viaggio',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            QrImageView(
              data: _payload,
              version: QrVersions.auto,
              size: size * 0.58,
              backgroundColor: Colors.white,
            ),
            if (_payload.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _payload,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
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

Future<Uint8List?> captureViaggiMezziQrPng(GlobalKey key) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 2.5);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

/// PDF quadrato stampabile (default 10×10 cm) con il QR centrato.
Future<Uint8List> buildViaggiMezziQrPdf({
  required Uint8List pngBytes,
  double sideCm = 10,
}) async {
  final side = sideCm * PdfPageFormat.cm;
  final doc = pw.Document();
  final image = pw.MemoryImage(pngBytes);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(side, side),
      margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
      build: (_) => pw.Center(
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    ),
  );
  return doc.save();
}
