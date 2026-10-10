import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/mdo_map_marker_style.dart';
import '../utils/mdo_map_special_marker_shapes.dart';
import '../utils/mdo_map_marker_shape_paths.dart';

Future<BitmapDescriptor> mdoMapMarkerIcon(
  String sigla, {
  double zoomScale = 1,
  MdoMapMarkerStyle style = MdoMapMarkerStyle.defaults,
}) =>
    mapMarkerIcon(
      sigla,
      look: style.resolveForKind('mdo'),
      zoomScale: zoomScale,
    );

String commessaMapDisplayLabel(String nome) {
  final s = nome.trim();
  if (s.isEmpty) return '?';
  final first = s.split(RegExp(r'\s+')).first;
  if (first.length >= 4) return first.toUpperCase();
  return s.length > 14 ? '${s.substring(0, 14)}…' : s.toUpperCase();
}

Future<BitmapDescriptor> boxMapMarkerIcon(
  String label, {
  double zoomScale = 1,
  MdoMapMarkerStyle style = MdoMapMarkerStyle.defaults,
}) =>
    mapMarkerIcon(
      label,
      look: style.resolveForKind('box'),
      zoomScale: zoomScale,
    );

Future<BitmapDescriptor> commessaMapMarkerIcon(
  String code, {
  double zoomScale = 1,
  MdoMapMarkerStyle style = MdoMapMarkerStyle.defaults,
}) =>
    mapMarkerIcon(
      commessaMapDisplayLabel(code),
      look: style.resolveForKind('commessa'),
      zoomScale: zoomScale,
      large: true,
    );

Future<BitmapDescriptor> estintoreMapMarkerIcon(
  String label, {
  double zoomScale = 1,
  MdoMapMarkerStyle style = MdoMapMarkerStyle.defaults,
}) =>
    mapMarkerIcon(
      label,
      look: style.resolveForKind('estintore'),
      zoomScale: zoomScale,
    );

Future<BitmapDescriptor> casettaPsMapMarkerIcon(
  String label, {
  double zoomScale = 1,
  MdoMapMarkerStyle style = MdoMapMarkerStyle.defaults,
}) =>
    mapMarkerIcon(
      label,
      look: style.resolveForKind('casetta_ps'),
      zoomScale: zoomScale,
    );

Future<BitmapDescriptor> mapMarkerIcon(
  String label, {
  required ResolvedMapMarkerLook look,
  double zoomScale = 1,
  bool large = false,
}) async {
  final display = _trimLabel(label, large ? 14 : 8);
  final scale = (zoomScale * look.sizeScale).clamp(0.55, 2.8);
  final w = (large ? 148.0 : 96.0) * scale;
  final h = (large ? 128.0 : 112.0) * scale;
  final fontSize = (large ? 18.0 : 19.0) * scale;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..isAntiAlias = true;
  final color = look.color;

  if (look.shape == MdoMapMarkerShape.estintore) {
    drawEstintoreMarker(canvas, w, h, display, color, fontSize, scale);
  } else if (look.shape == MdoMapMarkerShape.casettaPs) {
    drawCasettaPsMarker(canvas, w, h, display, color, fontSize, scale);
  } else if (look.shape == MdoMapMarkerShape.iconStack) {
    _drawIconStack(canvas, paint, w, h, display, fontSize, color, look.icon, scale);
  } else if (look.shape == MdoMapMarkerShape.circle) {
    _drawCircleMarker(canvas, w, h, display, fontSize, color, look.icon, scale);
  } else {
    _drawShapeMarker(
      canvas,
      paint,
      w,
      h,
      display,
      fontSize,
      color,
      look.icon,
      scale,
      shape: look.shape,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.ceil(), h.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    return BitmapDescriptor.defaultMarker;
  }
  return BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: w, height: h);
}

String _trimLabel(String raw, int max) {
  final t = raw.trim().toUpperCase();
  if (t.isEmpty) return '?';
  return t.length <= max ? t : '${t.substring(0, max)}…';
}

void _drawShapeMarker(
  Canvas canvas,
  Paint paint,
  double w,
  double h,
  String text,
  double fontSize,
  Color color,
  MdoMapMarkerIcon icon,
  double scale, {
  required MdoMapMarkerShape shape,
}) {
  paint.color = color;

  final pin = markerShapeHasPin(shape);
  final bodyBottom = pin ? h - 28 * scale : h - 8 * scale;
  final rrect = markerShapeRRect(shape, w, h, scale);
  final path = markerShapePath(shape, w, h, scale);

  _drawBodyShadow(canvas, rrect, path, scale);

  if (rrect != null) {
    canvas.drawRRect(rrect, paint);
    _stroke(canvas, rrect, scale);
  } else if (path != null) {
    if (shape == MdoMapMarkerShape.cross) {
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
      _strokeRect(
        canvas,
        Rect.fromLTWH(6, 6, w - 12, bodyBottom - 6),
        scale,
      );
    } else {
      canvas.drawPath(path, paint);
      _strokePath(canvas, path, scale);
    }
  }

  if (pin && shape != MdoMapMarkerShape.iconStack && shape != MdoMapMarkerShape.mapPin) {
    final pinPath = markerPinPointerPath(w, bodyBottom, scale);
    canvas.drawPath(pinPath, paint);
    _strokePath(canvas, pinPath, scale);
  }

  final center = markerShapeContentCenter(shape, w, h, scale);
  if (icon != MdoMapMarkerIcon.none &&
      shape != MdoMapMarkerShape.mapPin &&
      shape != MdoMapMarkerShape.cross) {
    _drawIcon(canvas, icon, center, 17 * scale);
    _drawText(
      canvas,
      text,
      Offset(center.dx + w * 0.08, center.dy),
      fontSize * 0.78,
      w * 0.42,
    );
  } else {
    _drawText(canvas, text, center, fontSize * 0.88, w - 16);
  }
}

void _drawBodyShadow(
  Canvas canvas,
  RRect? rrect,
  Path? path,
  double scale,
) {
  final shadow = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
  if (rrect != null) {
    canvas.drawRRect(rrect.shift(Offset(0, 2 * scale)), shadow);
  } else if (path != null) {
    canvas.drawPath(path.shift(Offset(0, 2 * scale)), shadow);
  }
}

void _drawCircleMarker(
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
  if (icon != MdoMapMarkerIcon.none) {
    _drawIcon(canvas, icon, c, 22 * scale);
  } else {
    _drawText(canvas, text, c, fontSize * 0.82, r * 1.6);
  }
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
  _drawIcon(
    canvas,
    icon == MdoMapMarkerIcon.none ? MdoMapMarkerIcon.container : icon,
    Offset(w / 2, iconCy),
    20 * scale,
  );

  final labelTop = iconCy + iconR + 4 * scale;
  final labelH = 24 * scale;
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTWH(8, labelTop, w - 16, labelH),
    Radius.circular(8 * scale),
  );
  paint.color = color;
  canvas.drawRRect(rect, paint);
  _stroke(canvas, rect, scale);
  _drawText(canvas, text, Offset(w / 2, labelTop + labelH / 2), fontSize * 0.78, w - 20);

  final pinPath = markerPinPointerPath(w, labelTop + labelH, scale);
  canvas.drawPath(pinPath, paint);
  _strokePath(canvas, pinPath, scale);
}

void _stroke(Canvas canvas, RRect rect, double scale) {
  final border = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2 * scale;
  canvas.drawRRect(rect, border);
}

void _strokePath(Canvas canvas, Path path, double scale) {
  final border = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2 * scale;
  canvas.drawPath(path, border);
}

void _strokeRect(Canvas canvas, Rect rect, double scale) {
  final border = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2 * scale;
  canvas.drawRect(rect, border);
}

void _strokeCircle(Canvas canvas, Offset c, double r, double scale) {
  final border = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2 * scale;
  canvas.drawCircle(c, r, border);
}

void _drawIcon(Canvas canvas, MdoMapMarkerIcon icon, Offset center, double size) {
  final data = icon.iconData;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(data.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: data.fontFamily,
        package: data.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
}

void _drawText(
  Canvas canvas,
  String text,
  Offset center,
  double fontSize,
  double maxW,
) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxW);
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
}
