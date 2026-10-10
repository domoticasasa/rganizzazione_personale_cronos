import 'package:flutter/material.dart';

/// Testo che si adatta alla cella: sceglie il font più grande che entra
/// nello spazio disponibile, andando a capo fino a [maxLines] righe.
/// Se anche il minimo non basta, riduce l'intero blocco (niente taglio).
class HubTileAutoFitText extends StatelessWidget {
  const HubTileAutoFitText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 3,
    this.minFontSize = 6,
    this.maxFontSize = 44,
    this.textAlign = TextAlign.center,
  });

  final String text;

  /// Stile di base (colore, peso, famiglia, altezza riga). Il `fontSize`
  /// viene ignorato e calcolato per riempire la cella, fino a [maxFontSize].
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final double maxFontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : double.infinity;
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : double.infinity;
        final hiCap = maxFontSize < minFontSize ? minFontSize : maxFontSize;
        final base = style.copyWith(height: style.height ?? 1.15);

        TextPainter painter(double fontSize) {
          return TextPainter(
            text: TextSpan(
              text: text,
              style: base.copyWith(fontSize: fontSize),
            ),
            maxLines: maxLines,
            textAlign: textAlign,
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          )..layout(maxWidth: maxW.isFinite ? maxW : double.infinity);
        }

        bool fits(double fontSize) {
          final tp = painter(fontSize);
          final fitsHeight = !maxH.isFinite || tp.height <= maxH + 0.5;
          return !tp.didExceedMaxLines && fitsHeight;
        }

        var best = minFontSize;
        if (fits(hiCap)) {
          best = hiCap;
        } else {
          var lo = minFontSize;
          var hi = hiCap;
          for (var i = 0; i < 12; i++) {
            final mid = (lo + hi) / 2;
            if (fits(mid)) {
              best = mid;
              lo = mid;
            } else {
              hi = mid;
            }
          }
        }

        final textWidget = Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: base.copyWith(fontSize: best),
        );

        if (!maxW.isFinite) return textWidget;
        if (!maxH.isFinite) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: textWidget,
          );
        }

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: textWidget,
          ),
        );
      },
    );
  }
}
