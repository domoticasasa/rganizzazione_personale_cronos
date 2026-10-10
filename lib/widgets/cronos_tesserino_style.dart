import 'package:flutter/material.dart';

/// Testi, colori e proporzioni tesserino (layout `tes2` / ISO ID-1).
abstract final class CronosTesserinoStyle {
  static const String assetHeaderPng = 'assets/tesserino_tes2_header.png';
  static const String assetHeaderFallback = 'assets/logo.png';

  static const String via = 'Viale Della Musica 41, 00144 Roma';
  static const String cf = 'C.F./P.I. 14383401008';

  static const String lblNome = 'NOME: ';
  static const String lblCognome = 'COGNOME:';
  static const String lblNato = 'NATO IL:';
  static const String lblAssunto = 'ASSUNTO DAL:';
  static const String lblTess = 'N. TESSERINO:';

  static const Color barFill = Color(0xFF2F528F);
  static const Color borderBlack = Color(0xFF000000);
  static const Color photoBg = Color(0xFFFFFFFF);

  static const String fontFamily = 'Tahoma';

  /// Dimensioni carta tesserino ISO ID-1 (mm) per export PDF A4.
  static const double id1WidthMm = 85.60;
  static const double id1HeightMm = 53.98;

  /// Riquadro foto ritratto sul tesserino (standard documento).
  static const double photoWidthMm = 35;
  static const double photoHeightMm = 45;
  static const double photoAspectRatio = photoWidthMm / photoHeightMm;
  static const double id1HeaderHeightOverWidth = 122 / 512;
  static const double id1BottomBarHeightOverWidth = 0.036;
  static const double id1MiddleBandHeightOverWidth = 0.42;
  /// Logo header (~49% larghezza card, ridotto del 30% rispetto al 70% precedente).
  static const double headerLogoScale = 0.49;

  static double layoutScale({required bool hasExtraLine}) =>
      hasExtraLine ? 0.92 : 1.0;

  static double layoutScaleForExtraLineCount(int count) {
    if (count <= 0) return 1.0;
    if (count == 1) return 0.92;
    if (count == 2) return 0.86;
    if (count == 3) return 0.80;
    return 0.74;
  }

  static double labelFontSize(double cardW, {required bool hasExtraLine}) =>
      cardW * 0.0285 * layoutScale(hasExtraLine: hasExtraLine);

  static double labelFontSizeForCount(double cardW, int extraLineCount) =>
      cardW * 0.0285 * layoutScaleForExtraLineCount(extraLineCount);

  static double valueFontSize(double cardW, {required bool hasExtraLine}) =>
      cardW * 0.0355 * layoutScale(hasExtraLine: hasExtraLine);

  static double valueFontSizeForCount(double cardW, int extraLineCount) =>
      cardW * 0.0355 * layoutScaleForExtraLineCount(extraLineCount);

  static double lineBottomPadding({required bool hasExtraLine}) =>
      hasExtraLine ? 1.0 : 2.0;

  static double blockGapBeforeAnagrafica(
    double cardW, {
    required bool hasExtraLine,
    int extraLineCount = 0,
  }) {
    if (extraLineCount >= 2) return cardW * 0.012;
    return cardW * 0.018;
  }

  static TextStyle fontLabel(double w, {bool hasExtraLine = false}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: w * 0.0285 * layoutScale(hasExtraLine: hasExtraLine),
        fontWeight: FontWeight.w700,
        height: hasExtraLine ? 1.1 : 1.15,
        color: borderBlack,
      );

  static TextStyle fontValue(double w, {bool hasExtraLine = false}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: w * 0.0355 * layoutScale(hasExtraLine: hasExtraLine),
        fontWeight: FontWeight.w700,
        height: hasExtraLine ? 1.12 : 1.2,
        color: borderBlack,
      );
}
