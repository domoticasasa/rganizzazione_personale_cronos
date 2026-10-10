import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const int _kMaxOcrEdge = 1600;
const int _kMaxOcrEdgeWeb = 1100;
const int _kMinOcrWidth = 900;

Future<Uint8List> preparePrimaryOcrJpeg(Uint8List raw) async {
  if (kIsWeb) return _preparePrimary(raw);
  return compute(_preparePrimary, raw);
}

Future<Uint8List?> buildCardBandJpeg(Uint8List raw) async {
  if (kIsWeb) return _cardBand(raw);
  return compute(_cardBand, raw);
}

Future<List<Uint8List>> buildRicevutaOcrVariants(Uint8List raw) async {
  if (kIsWeb) return _buildVariants(raw);
  return compute(_buildVariants, raw);
}

Uint8List _preparePrimary(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final receipt = _cropBrightReceipt(decoded) ?? decoded;
  final sized = _resizeIfNeeded(receipt);
  return _encode(sized, quality: kIsWeb ? 72 : 82);
}

Uint8List? _cardBand(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  final receipt = _cropBrightReceipt(decoded) ?? decoded;
  final sized = _resizeIfNeeded(receipt);
  if (sized.height < 180) return null;
  final y = (sized.height * 0.18).round();
  final h = math.max(140, (sized.height * 0.38).round());
  final cropped = img.copyCrop(
    sized,
    x: 0,
    y: y,
    width: sized.width,
    height: math.min(h, sized.height - y),
  );
  return _encode(
    _enhanceForOcr(cropped, contrast: 1.75, brightness: 0.94),
    quality: kIsWeb ? 75 : 85,
  );
}

List<Uint8List> _buildVariants(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return const [];
  final receipt = _cropBrightReceipt(decoded) ?? decoded;
  final base = kIsWeb
      ? _resizeIfNeeded(receipt)
      : _upscaleIfNeeded(_resizeIfNeeded(receipt));
  return [
    _encode(_enhanceForOcr(base, contrast: 1.45, brightness: 0.92)),
  ];
}

Uint8List _encode(img.Image image, {int quality = 80}) {
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// Ritaglia la carta termica chiara (esclude abitacolo / mano).
img.Image? _cropBrightReceipt(img.Image src) {
  final w = src.width;
  final h = src.height;
  if (w < 80 || h < 80) return null;

  const step = 4;
  const brightMin = 168;
  final cols = (w / step).ceil();
  final rows = (h / step).ceil();
  final heat = List<int>.filled(rows * cols, 0);

  for (var ry = 0; ry < rows; ry++) {
    final y = math.min(h - 1, ry * step);
    for (var cx = 0; cx < cols; cx++) {
      final x = math.min(w - 1, cx * step);
      final p = src.getPixel(x, y);
      final lum = (p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000;
      heat[ry * cols + cx] = lum;
    }
  }

  var minX = cols;
  var maxX = -1;
  var minY = rows;
  var maxY = -1;
  for (var ry = 0; ry < rows; ry++) {
    var rowHits = 0;
    var rowMinX = cols;
    var rowMaxX = -1;
    for (var cx = 0; cx < cols; cx++) {
      if (heat[ry * cols + cx] < brightMin) continue;
      rowHits++;
      if (cx < rowMinX) rowMinX = cx;
      if (cx > rowMaxX) rowMaxX = cx;
    }
    if (rowHits < (cols * 0.12).ceil()) continue;
    if (ry < minY) minY = ry;
    if (ry > maxY) maxY = ry;
    if (rowMinX < minX) minX = rowMinX;
    if (rowMaxX > maxX) maxX = rowMaxX;
  }

  if (maxX < 0 || maxY < 0) return null;

  final padX = 2;
  final padY = 2;
  final x0 = (math.max(0, minX - padX) * step).clamp(0, w - 1);
  final y0 = (math.max(0, minY - padY) * step).clamp(0, h - 1);
  final x1 = (math.min(cols - 1, maxX + padX) * step + step).clamp(1, w);
  final y1 = (math.min(rows - 1, maxY + padY) * step + step).clamp(1, h);
  final cw = x1 - x0;
  final ch = y1 - y0;
  if (cw < w * 0.28 || ch < h * 0.35) return null;
  if (cw >= w * 0.97 && ch >= h * 0.97) return null;

  return img.copyCrop(
    src,
    x: x0,
    y: y0,
    width: cw,
    height: ch,
  );
}

img.Image _resizeIfNeeded(img.Image decoded) {
  final cap = kIsWeb ? _kMaxOcrEdgeWeb : _kMaxOcrEdge;
  final maxEdge = math.max(decoded.width, decoded.height);
  if (maxEdge <= cap) return decoded;
  final scale = cap / maxEdge;
  return img.copyResize(
    decoded,
    width: math.max(1, (decoded.width * scale).round()),
    height: math.max(1, (decoded.height * scale).round()),
  );
}

img.Image _upscaleIfNeeded(img.Image decoded) {
  if (decoded.width >= _kMinOcrWidth) return decoded;
  final scale = _kMinOcrWidth / decoded.width;
  return img.copyResize(
    decoded,
    width: _kMinOcrWidth,
    height: math.max(1, (decoded.height * scale).round()),
  );
}

img.Image _enhanceForOcr(
  img.Image source, {
  required double contrast,
  required double brightness,
  double gamma = 1.05,
}) {
  var out = img.grayscale(source);
  out = img.adjustColor(
    out,
    contrast: contrast,
    brightness: brightness,
    gamma: gamma,
  );
  return out;
}
