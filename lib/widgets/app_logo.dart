import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Titolo app bar con logo Gestopro360 integrato.
class ResponsiveAppBarTitle extends StatelessWidget {
  final String title;
  final bool showIcon;

  const ResponsiveAppBarTitle({
    super.key,
    required this.title,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 640;
    return Row(
      children: [
        if (showIcon) ...[
          const _AppIconBadge(size: 30),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrapper pagina con logo brand in alto e contenuto sotto.
class PageWithTopLogo extends StatelessWidget {
  final Widget child;
  final bool showBrandHeader;

  const PageWithTopLogo({
    super.key,
    required this.child,
    this.showBrandHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBrandHeader) return child;
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _AppIconBadge(size: 34),
              SizedBox(width: 10),
              _BrandText(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: child),
      ],
    );
  }
}

class _BrandText extends StatelessWidget {
  const _BrandText();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2947A9), Color(0xFF2CCAF2)],
          ).createShader(bounds),
          child: const Text(
            'GESTOPRO360',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Text(
          'Sempre aggiornate. Con un solo clic.',
          style: TextStyle(
            fontSize: 10.5,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AppIconBadge extends StatelessWidget {
  final double size;

  const _AppIconBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GestoproIconPainter(),
      ),
    );
  }
}

/// Riproduzione vettoriale semplificata dell'icona "combo":
/// documento/check + monogramma G360.
class _GestoproIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF142768), Color(0xFF1C5DC3)],
      ).createShader(rect);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.22));
    canvas.drawRRect(outer, bgPaint);

    final center = Offset(size.width / 2, size.height / 2);
    final discRadius = size.width * 0.33;
    final discPaint = Paint()..color = const Color(0xFFF7FBFF);
    canvas.drawCircle(center, discRadius, discPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width * 0.028)
      ..color = const Color(0xFFA8CBF9);
    canvas.drawCircle(center, discRadius * 0.88, ringPaint);

    final arcRect = Rect.fromCircle(center: center, radius: discRadius * 0.89);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.8, size.width * 0.034)
      ..shader = const LinearGradient(
        colors: [Color(0xFF436FF0), Color(0xFF2ADAF4)],
      ).createShader(arcRect);
    canvas.drawArc(arcRect, 3.9, 4.4, false, arcPaint);

    final arrow = Path()
      ..moveTo(size.width * 0.28, size.height * 0.63)
      ..lineTo(size.width * 0.23, size.height * 0.73)
      ..lineTo(size.width * 0.34, size.height * 0.71)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF2ADAF4));

    final docRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.31,
        size.height * 0.34,
        size.width * 0.17,
        size.height * 0.24,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(
      docRect,
      Paint()..color = const Color(0xFFEEF4FF),
    );
    canvas.drawRRect(
      docRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size.width * 0.009)
        ..color = const Color(0xFF9FC3F2),
    );

    final linePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.width * 0.013)
      ..color = const Color(0xFFA2BFEB);
    final l1y = size.height * 0.40;
    final l2y = size.height * 0.435;
    final l3y = size.height * 0.47;
    canvas.drawLine(Offset(size.width * 0.34, l1y), Offset(size.width * 0.43, l1y), linePaint);
    canvas.drawLine(Offset(size.width * 0.34, l2y), Offset(size.width * 0.42, l2y), linePaint);
    canvas.drawLine(Offset(size.width * 0.34, l3y), Offset(size.width * 0.425, l3y), linePaint);

    final checkPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.016)
      ..color = const Color(0xFF16B77B);
    final check = Path()
      ..moveTo(size.width * 0.34, size.height * 0.53)
      ..lineTo(size.width * 0.37, size.height * 0.56)
      ..lineTo(size.width * 0.45, size.height * 0.49);
    canvas.drawPath(check, checkPaint);

    final dividerPaint = Paint()
      ..color = const Color(0xFFA7C8F5).withValues(alpha: 0.65);
    final dividerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.34,
        math.max(1.2, size.width * 0.01),
        size.height * 0.24,
      ),
      Radius.circular(size.width * 0.01),
    );
    canvas.drawRRect(dividerRect, dividerPaint);

    final gStyle = TextStyle(
      color: const Color(0xFF2747A0),
      fontWeight: FontWeight.w800,
      fontSize: size.width * 0.20,
      height: 1.0,
    );
    final tG = TextPainter(
      text: TextSpan(text: 'G', style: gStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tG.paint(canvas, Offset(size.width * 0.56, size.height * 0.39));

    final nStyle = TextStyle(
      color: const Color(0xFF2F8DDE),
      fontWeight: FontWeight.w800,
      fontSize: size.width * 0.10,
      height: 1.0,
    );
    final tN = TextPainter(
      text: TextSpan(text: '360', style: nStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tN.paint(canvas, Offset(size.width * 0.59, size.height * 0.53));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
