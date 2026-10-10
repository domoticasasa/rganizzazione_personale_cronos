import 'package:flutter/material.dart';

/// Ramo di albero navigazione: linea verticale + gomito arrotondato
/// (stile docs: ├─ / └─) senza cambiare i colori della voce.
class NavTreeBranch extends StatelessWidget {
  const NavTreeBranch({
    super.key,
    required this.lineColor,
    required this.isLast,
    required this.item,
    this.childTree,
  });

  final Color lineColor;
  final bool isLast;
  final Widget item;
  final Widget? childTree;

  static const double gutterWidth = 16;

  @override
  Widget build(BuildContext context) {
    final nested = childTree;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: gutterWidth,
                child: CustomPaint(
                  painter: NavTreeElbowPainter(
                    color: lineColor,
                    isLast: isLast,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Expanded(child: item),
            ],
          ),
        ),
        if (nested != null)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: gutterWidth,
                  child: isLast
                      ? null
                      : CustomPaint(
                          painter: NavTreeSpinePainter(color: lineColor),
                          child: const SizedBox.expand(),
                        ),
                ),
                Expanded(child: nested),
              ],
            ),
          ),
      ],
    );
  }
}

/// Gomito: verticale dall'alto al centro riga, curva verso la voce.
/// Se non è l'ultimo, la verticale continua fino in fondo alla riga.
class NavTreeElbowPainter extends CustomPainter {
  const NavTreeElbowPainter({
    required this.color,
    required this.isLast,
  });

  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final x = size.width * 0.42;
    final midY = size.height * 0.5;
    const radius = 7.0;
    final path = Path()..moveTo(x, 0);

    if (midY > radius) {
      path.lineTo(x, midY - radius);
    }
    path.quadraticBezierTo(x, midY, x + radius, midY);
    path.lineTo(size.width, midY);
    canvas.drawPath(path, paint);

    if (!isLast && midY < size.height) {
      canvas.drawLine(Offset(x, midY), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant NavTreeElbowPainter old) =>
      old.color != color || old.isLast != isLast;
}

/// Verticale che continua accanto ai figli se il ramo non è l'ultimo.
class NavTreeSpinePainter extends CustomPainter {
  const NavTreeSpinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final x = size.width * 0.42;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant NavTreeSpinePainter old) => old.color != color;
}
