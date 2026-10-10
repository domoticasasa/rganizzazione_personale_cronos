import 'package:flutter/material.dart';

import '../models/mdo_map_marker_style.dart';
import '../utils/mdo_map_marker_shape_paths.dart';
import '../utils/mdo_map_special_marker_shapes.dart';

/// Anteprima / marker Flutter Map — stessa resa di [mapMarkerIcon].
class MdoMapMarkerPainter extends CustomPainter {
  MdoMapMarkerPainter({
    required this.label,
    required this.look,
    this.large = false,
  });

  final String label;
  final ResolvedMapMarkerLook look;
  final bool large;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final color = look.color;
    final scale = size.width / (large ? 148 : 96);
    final w = size.width;
    final h = size.height;
    final display = _trimLabel(label, large ? 14 : 8);
    final fontSize = (large ? 18.0 : 19.0) * scale * look.sizeScale.clamp(0.55, 1.2);

    if (look.shape == MdoMapMarkerShape.estintore) {
      drawEstintoreMarker(canvas, w, h, display, color, fontSize, scale);
      return;
    }
    if (look.shape == MdoMapMarkerShape.casettaPs) {
      drawCasettaPsMarker(canvas, w, h, display, color, fontSize, scale);
      return;
    }
    if (look.shape == MdoMapMarkerShape.iconStack) {
      _drawIconStack(canvas, paint, w, h, display, fontSize, color, look.icon, scale);
      return;
    }
    if (look.shape == MdoMapMarkerShape.circle) {
      _drawCircle(canvas, w, h, display, fontSize, color, look.icon, scale);
      return;
    }

    paint.color = color;
    final pin = markerShapeHasPin(look.shape);
    final bodyBottom = pin ? h - 28 * scale : h - 8 * scale;
    final rrect = markerShapeRRect(look.shape, w, h, scale);
    final path = markerShapePath(look.shape, w, h, scale);
    _shadow(canvas, rrect, path, scale);
    if (rrect != null) {
      canvas.drawRRect(rrect, paint);
      _strokeRRect(canvas, rrect, scale);
    } else if (path != null) {
      if (look.shape == MdoMapMarkerShape.cross) {
        final cx = w / 2;
        final t = 11 * scale;
        canvas.drawRect(
          Rect.fromLTWH(cx - t, 12 * scale, t * 2, bodyBottom - 16 * scale),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(14 * scale, bodyBottom * 0.42, w - 28 * scale, t * 2),
          paint,
        );
      } else {
        canvas.drawPath(path, paint);
        _strokePath(canvas, path, scale);
      }
    }
    if (pin &&
        look.shape != MdoMapMarkerShape.iconStack &&
        look.shape != MdoMapMarkerShape.mapPin) {
      final pinPath = markerPinPointerPath(w, bodyBottom, scale);
      canvas.drawPath(pinPath, paint);
      _strokePath(canvas, pinPath, scale);
    }
    final center = markerShapeContentCenter(look.shape, w, h, scale);
    _text(canvas, display, center, fontSize * 0.88, w - 16);
  }

  String _trimLabel(String raw, int max) {
    final t = raw.trim().toUpperCase();
    if (t.isEmpty) return '?';
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  void _drawCircle(
    Canvas canvas,
    double w,
    double h,
    String text,
    double fontSize,
    Color color,
    MdoMapMarkerIcon icon,
    double scale,
  ) {
    final r = w * 0.36;
    final c = Offset(w / 2, r + 8 * scale);
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
    canvas.drawCircle(Offset(c.dx, c.dy + 2 * scale), r, shadow);
    final paint = Paint()..isAntiAlias = true..color = color;
    canvas.drawCircle(c, r, paint);
    _strokeCircle(canvas, c, r, scale);
    _text(canvas, text, c, fontSize * 0.82, r * 1.6);
  }

  void _drawIconStack(
    Canvas canvas,
    Paint paint,
    double w,
    double h,
    String text,
    double fontSize,
    Color color,
    MdoMapMarkerIcon icon,
    double scale,
  ) {
    final iconR = 16 * scale;
    final iconCy = 10 * scale + iconR;
    paint.color = color;
    canvas.drawCircle(Offset(w / 2, iconCy), iconR, paint);
    _strokeCircle(canvas, Offset(w / 2, iconCy), iconR, scale);

    final labelTop = iconCy + iconR + 4 * scale;
    final labelH = 24 * scale;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, labelTop, w - 16, labelH),
      Radius.circular(8 * scale),
    );
    paint.color = color;
    canvas.drawRRect(rect, paint);
    _strokeRRect(canvas, rect, scale);
    _text(canvas, text, Offset(w / 2, labelTop + labelH / 2), fontSize * 0.78, w - 20);

    final pinPath = markerPinPointerPath(w, labelTop + labelH, scale);
    canvas.drawPath(pinPath, paint);
    _strokePath(canvas, pinPath, scale);
  }

  void _text(Canvas canvas, String t, Offset center, double fs, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: Colors.white,
          fontSize: fs,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _shadow(Canvas canvas, RRect? rrect, Path? path, double scale) {
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
    if (rrect != null) {
      canvas.drawRRect(rrect.shift(Offset(0, 2 * scale)), shadow);
    } else if (path != null) {
      canvas.drawPath(path.shift(Offset(0, 2 * scale)), shadow);
    }
  }

  void _strokeRRect(Canvas canvas, RRect rect, double scale) {
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
  }

  void _strokePath(Canvas canvas, Path path, double scale) {
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
  }

  void _strokeCircle(Canvas canvas, Offset c, double r, double scale) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
  }

  @override
  bool shouldRepaint(covariant MdoMapMarkerPainter oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.look != look ||
      oldDelegate.large != large;
}
