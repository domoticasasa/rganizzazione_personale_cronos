
import 'package:flutter/material.dart';

/// Disegna simbolo estintore (corpo + maniglia + etichetta + punta GPS).
void drawEstintoreMarker(
  Canvas canvas,
  double w,
  double h,
  String label,
  Color color,
  double fontSize,
  double scale,
) {
  final cx = w / 2;
  final bodyW = 26 * scale;
  final bodyH = 40 * scale;
  final bodyTop = 14 * scale;
  final bodyLeft = cx - bodyW / 2;
  final bodyRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(bodyLeft, bodyTop, bodyW, bodyH),
    Radius.circular(5 * scale),
  );

  final shadow = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
  canvas.drawRRect(bodyRect.shift(Offset(0, 2 * scale)), shadow);

  final paint = Paint()..isAntiAlias = true..color = color;
  final handleW = 18 * scale;
  final handleRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(cx - handleW / 2, 6 * scale, handleW, 10 * scale),
    Radius.circular(8 * scale),
  );
  canvas.drawRRect(handleRect, paint);
  _strokeRRect(canvas, handleRect, scale);

  canvas.drawRRect(bodyRect, paint);
  _strokeRRect(canvas, bodyRect, scale);

  final nozzle = Path()
    ..moveTo(cx - 5 * scale, bodyTop + bodyH)
    ..lineTo(cx + 5 * scale, bodyTop + bodyH)
    ..lineTo(cx, bodyTop + bodyH + 8 * scale)
    ..close();
  canvas.drawPath(nozzle, paint);
  _strokePath(canvas, nozzle, scale);

  _drawLabel(
    canvas,
    label,
    Offset(cx, bodyTop + bodyH * 0.52),
    fontSize * 0.62,
    bodyW - 6 * scale,
  );

  final pinTop = bodyTop + bodyH + 8 * scale;
  final pin = Path()
    ..moveTo(cx, h - 4 * scale)
    ..lineTo(cx - 9 * scale, pinTop)
    ..lineTo(cx + 9 * scale, pinTop)
    ..close();
  canvas.drawPath(pin, paint);
  _strokePath(canvas, pin, scale);
}

/// Disegna casetta primo soccorso (box + croce + etichetta + punta GPS).
void drawCasettaPsMarker(
  Canvas canvas,
  double w,
  double h,
  String label,
  Color color,
  double fontSize,
  double scale,
) {
  final cx = w / 2;
  final boxW = 44 * scale;
  final boxH = 34 * scale;
  final boxTop = 10 * scale;
  final boxLeft = cx - boxW / 2;
  final outer = RRect.fromRectAndRadius(
    Rect.fromLTWH(boxLeft, boxTop, boxW, boxH),
    Radius.circular(4 * scale),
  );

  final shadow = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
  canvas.drawRRect(outer.shift(Offset(0, 2 * scale)), shadow);

  final paint = Paint()..isAntiAlias = true;
  paint.color = Colors.white;
  canvas.drawRRect(outer, paint);
  _strokeRRectColored(canvas, outer, color, scale * 2.2);

  paint.color = color;
  final crossT = 4.5 * scale;
  final crossCx = cx;
  final crossCy = boxTop + boxH * 0.46;
  canvas.drawRect(
    Rect.fromCenter(
      center: Offset(crossCx, crossCy),
      width: crossT,
      height: boxH * 0.55,
    ),
    paint,
  );
  canvas.drawRect(
    Rect.fromCenter(
      center: Offset(crossCx, crossCy),
      width: boxW * 0.55,
      height: crossT,
    ),
    paint,
  );

  final labelTop = boxTop + boxH + 4 * scale;
  final labelRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(boxLeft, labelTop, boxW, 18 * scale),
    Radius.circular(6 * scale),
  );
  canvas.drawRRect(labelRect, paint);
  _strokeRRect(canvas, labelRect, scale);
  _drawLabel(
    canvas,
    label,
    Offset(cx, labelTop + 9 * scale),
    fontSize * 0.58,
    boxW - 4 * scale,
  );

  final pinTop = labelTop + 18 * scale;
  final pin = Path()
    ..moveTo(cx, h - 4 * scale)
    ..lineTo(cx - 9 * scale, pinTop)
    ..lineTo(cx + 9 * scale, pinTop)
    ..close();
  canvas.drawPath(pin, paint);
  _strokePath(canvas, pin, scale);
}

void _drawLabel(
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
  tp.paint(
    canvas,
    Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
  );
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

void _strokeRRectColored(Canvas canvas, RRect rect, Color color, double width) {
  canvas.drawRRect(
    rect,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
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
