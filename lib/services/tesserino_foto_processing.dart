import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../widgets/cronos_tesserino_style.dart';

/// Lato lungo massimo prima di ritaglio (evita OOM su foto camera).
const int kTesserinoMaxInputEdge = 1280;

Future<Uint8List> _runPhotoWorker(
  Uint8List input,
  Uint8List Function(Uint8List) fn,
) async {
  if (kIsWeb) return fn(input);
  return compute(fn, input);
}

/// Prepara la foto tesserino: ridimensiona e ritaglia 35×45 mm (riempimento frame).
Future<Uint8List> processTesserinoPhotoBytes(Uint8List raw) async {
  if (raw.isEmpty) {
    throw Exception('File immagine vuoto');
  }
  final downscaled = await _runPhotoWorker(raw, _downscaleForTesserino);
  final cropped = await _runPhotoWorker(downscaled, _cropToTesserinoFrame);
  if (cropped.length < 500) {
    throw Exception('Impossibile elaborare l\'immagine');
  }
  return cropped;
}

/// Riduce la foto in ingresso (isolate su mobile/desktop).
Uint8List _downscaleForTesserino(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  final maxEdge = math.max(decoded.width, decoded.height);
  if (maxEdge <= kTesserinoMaxInputEdge) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
  }

  final scale = kTesserinoMaxInputEdge / maxEdge;
  final w = math.max(1, (decoded.width * scale).round());
  final h = math.max(1, (decoded.height * scale).round());
  final resized = img.copyResize(decoded, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

/// Ritaglia la foto al riquadro 35×45 mm (7:9), riempiendo tutta la larghezza/altezza
/// (come `BoxFit.cover` + allineamento in alto sul tesserino, senza bande laterali bianche).
Uint8List _cropToTesserinoFrame(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  const pxPerMm = 20;
  final targetW =
      (CronosTesserinoStyle.photoWidthMm * pxPerMm).round(); // 700
  final targetH =
      (CronosTesserinoStyle.photoHeightMm * pxPerMm).round(); // 900

  final scale = math.max(
    targetW / decoded.width,
    targetH / decoded.height,
  );
  final nw = math.max(1, (decoded.width * scale).round());
  final nh = math.max(1, (decoded.height * scale).round());
  final resized = img.copyResize(decoded, width: nw, height: nh);

  final maxCropX = math.max(0, nw - targetW);
  final cropX = ((nw - targetW) ~/ 2).clamp(0, maxCropX);
  const cropY = 0;

  final cropped = img.copyCrop(
    resized,
    x: cropX,
    y: cropY,
    width: targetW,
    height: targetH,
  );

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 88));
}
