import 'dart:math' as math;
import 'dart:ui';

import '../models/mdo_map_marker_style.dart';

/// Punta triangolare sotto al corpo etichetta.
Path markerPinPointerPath(double w, double bodyBottom, double scale) {
  final cx = w / 2;
  return Path()
    ..moveTo(cx, bodyBottom + 20 * scale)
    ..lineTo(cx - 10 * scale, bodyBottom - 1 * scale)
    ..lineTo(cx + 10 * scale, bodyBottom - 1 * scale)
    ..close();
}

/// Punta sotto al marker GPS.
bool markerShapeHasPin(MdoMapMarkerShape shape) => switch (shape) {
      MdoMapMarkerShape.badge ||
      MdoMapMarkerShape.pin ||
      MdoMapMarkerShape.iconStack ||
      MdoMapMarkerShape.mapPin ||
      MdoMapMarkerShape.bubble =>
        true,
      _ => false,
    };

/// Rettangolo arrotondato per forme rettangolari.
RRect? markerShapeRRect(MdoMapMarkerShape shape, double w, double h, double scale) {
  final pin = markerShapeHasPin(shape);
  final bottom = pin ? h - 28 * scale : h - 8 * scale;
  final rect = Rect.fromLTWH(6, 6, w - 12, bottom - 6);
  return switch (shape) {
    MdoMapMarkerShape.pill => RRect.fromRectAndRadius(rect, const Radius.circular(999)),
    MdoMapMarkerShape.square => RRect.fromRectAndRadius(rect, Radius.circular(4 * scale)),
    MdoMapMarkerShape.roundedRect => RRect.fromRectAndRadius(rect, Radius.circular(16 * scale)),
    MdoMapMarkerShape.banner => RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 10, w - 8, bottom - 14),
        Radius.circular(6 * scale),
      ),
    MdoMapMarkerShape.tag => RRect.fromRectAndRadius(rect, Radius.circular(4 * scale)),
    MdoMapMarkerShape.notch => RRect.fromRectAndRadius(rect, Radius.circular(10 * scale)),
    MdoMapMarkerShape.badge || MdoMapMarkerShape.pin => RRect.fromRectAndRadius(
        rect,
        Radius.circular(10 * scale),
      ),
    _ => null,
  };
}

/// Path per forme poligonali / speciali.
Path? markerShapePath(MdoMapMarkerShape shape, double w, double h, double scale) {
  final cx = w / 2;
  final pin = markerShapeHasPin(shape);
  final bodyBottom = pin ? h - 28 * scale : h - 8 * scale;

  switch (shape) {
    case MdoMapMarkerShape.diamond:
      return Path()
        ..moveTo(cx, 8 * scale)
        ..lineTo(w - 10 * scale, bodyBottom * 0.55)
        ..lineTo(cx, bodyBottom - 4 * scale)
        ..lineTo(10 * scale, bodyBottom * 0.55)
        ..close();
    case MdoMapMarkerShape.hexagon:
      return _regularPolygon(cx, bodyBottom * 0.48, w * 0.34, 6, -math.pi / 2);
    case MdoMapMarkerShape.octagon:
      return _regularPolygon(cx, bodyBottom * 0.48, w * 0.36, 8, -math.pi / 8);
    case MdoMapMarkerShape.pentagon:
      return _regularPolygon(cx, bodyBottom * 0.5, w * 0.34, 5, -math.pi / 2);
    case MdoMapMarkerShape.triangle:
      return Path()
        ..moveTo(cx, 8 * scale)
        ..lineTo(w - 10 * scale, bodyBottom - 6 * scale)
        ..lineTo(10 * scale, bodyBottom - 6 * scale)
        ..close();
    case MdoMapMarkerShape.shield:
      return Path()
        ..moveTo(cx, 8 * scale)
        ..lineTo(w - 12 * scale, 20 * scale)
        ..lineTo(w - 16 * scale, bodyBottom * 0.62)
        ..quadraticBezierTo(cx, bodyBottom, 16 * scale, bodyBottom * 0.62)
        ..lineTo(12 * scale, 20 * scale)
        ..close();
    case MdoMapMarkerShape.teardrop:
      final r = w * 0.3;
      final top = 10 * scale;
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, top + r), radius: r))
        ..moveTo(cx - r * 0.85, top + r * 1.45)
        ..lineTo(cx + r * 0.85, top + r * 1.45)
        ..lineTo(cx, bodyBottom - 4 * scale)
        ..close();
    case MdoMapMarkerShape.star:
      return _starPath(cx, bodyBottom * 0.46, w * 0.36, w * 0.16);
    case MdoMapMarkerShape.arch:
      return Path()
        ..addArc(
          Rect.fromCircle(center: Offset(cx, bodyBottom * 0.55), radius: w * 0.38),
          math.pi,
          math.pi,
        )
        ..lineTo(w - 10 * scale, bodyBottom - 4 * scale)
        ..lineTo(10 * scale, bodyBottom - 4 * scale)
        ..close();
    case MdoMapMarkerShape.cross:
      final t = 11 * scale;
      return Path()
        ..addRect(Rect.fromLTWH(cx - t, 12 * scale, t * 2, bodyBottom - 16 * scale))
        ..addRect(Rect.fromLTWH(14 * scale, bodyBottom * 0.42, w - 28 * scale, t * 2));
    case MdoMapMarkerShape.mapPin:
      final r = w * 0.28;
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, 14 * scale + r), radius: r))
        ..moveTo(cx - r * 0.7, 14 * scale + r * 1.6)
        ..lineTo(cx + r * 0.7, 14 * scale + r * 1.6)
        ..lineTo(cx, h - 10 * scale)
        ..close();
    case MdoMapMarkerShape.bubble:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, w - 16, bodyBottom - 14 * scale),
          Radius.circular(12 * scale),
        ))
        ..moveTo(cx - 8 * scale, bodyBottom - 14 * scale)
        ..lineTo(cx, bodyBottom - 2 * scale)
        ..lineTo(cx + 8 * scale, bodyBottom - 14 * scale)
        ..close();
    case MdoMapMarkerShape.parallelogram:
      return Path()
        ..moveTo(18 * scale, 10 * scale)
        ..lineTo(w - 8 * scale, 10 * scale)
        ..lineTo(w - 18 * scale, bodyBottom - 6 * scale)
        ..lineTo(8 * scale, bodyBottom - 6 * scale)
        ..close();
    default:
      return null;
  }
}

Path _regularPolygon(double cx, double cy, double r, int sides, double startAngle) {
  final path = Path();
  for (var i = 0; i < sides; i++) {
    final a = startAngle + (2 * math.pi * i / sides);
    final x = cx + r * math.cos(a);
    final y = cy + r * math.sin(a);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

Path _starPath(double cx, double cy, double outerR, double innerR) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outerR : innerR;
    final a = (math.pi / 5) * i - math.pi / 2;
    final x = cx + r * math.cos(a);
    final y = cy + r * math.sin(a);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// Centro testo/icona nel corpo del marker.
Offset markerShapeContentCenter(MdoMapMarkerShape shape, double w, double h, double scale) {
  final pin = markerShapeHasPin(shape);
  final bodyBottom = pin ? h - 28 * scale : h - 8 * scale;
  return switch (shape) {
    MdoMapMarkerShape.circle => Offset(w / 2, w * 0.36 + 8 * scale),
    MdoMapMarkerShape.mapPin => Offset(w / 2, 14 * scale + w * 0.22),
    MdoMapMarkerShape.triangle => Offset(w / 2, bodyBottom * 0.58),
    MdoMapMarkerShape.star ||
    MdoMapMarkerShape.hexagon ||
    MdoMapMarkerShape.octagon ||
    MdoMapMarkerShape.pentagon =>
      Offset(w / 2, bodyBottom * 0.46),
    _ => Offset(w / 2, 6 + (bodyBottom - 6) / 2),
  };
}
