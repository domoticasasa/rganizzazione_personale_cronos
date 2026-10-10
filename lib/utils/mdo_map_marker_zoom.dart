import 'dart:math' as math;

/// Scala marker in base allo zoom mappa (reference zoom 11 ≈ 1.0).
double mdoMapMarkerZoomScale(
  double zoom, {
  required String kind,
  double kindSizeScale = 1.0,
  double userMapSizeScale = 1.0,
}) {
  final base = switch (kind) {
    'commessa' => 1.32,
    'box' => 0.82,
    'estintore' || 'casetta_ps' || 'struttura' || 'officina' => 0.68,
    _ => 0.76,
  };
  final size =
      math.pow(1.10, zoom - 11) * base * userMapSizeScale * kindSizeScale;
  return size.clamp(0.18, 2.15).toDouble();
}
