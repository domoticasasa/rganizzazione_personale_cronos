import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'device.dart';

/// Breakpoint condivisi (web, Windows, tablet, telefono).
abstract final class CronosBreakpoints {
  static const double phone = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;

  /// Sotto questa soglia le pagine logistica usano card/lista.
  static const double logisticaCompact = 960;

  /// Sotto questa soglia hub e navigazione usano layout compatto.
  static const double compactUi = 768;

  /// AppBar molto compatta (logo/titoli ridotti).
  static const double ultraCompactAppBar = 430;
}

enum CronosFormFactor { phone, tablet, desktop, wide }

CronosFormFactor cronosFormFactor(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < CronosBreakpoints.phone) return CronosFormFactor.phone;
  if (w < CronosBreakpoints.tablet) return CronosFormFactor.tablet;
  if (w < CronosBreakpoints.desktop) return CronosFormFactor.desktop;
  return CronosFormFactor.wide;
}

bool cronosIsPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < CronosBreakpoints.phone;

bool cronosIsTablet(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= CronosBreakpoints.phone && w < CronosBreakpoints.tablet;
}

bool cronosIsDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= CronosBreakpoints.tablet;

bool cronosIsWideDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= CronosBreakpoints.wide;

/// Telefono nativo o viewport stretto (incluso **browser mobile** / finestra ridotta).
/// Su tablet Android/iOS (lato corto ≥ 600px) usa layout adattivo, non quello telefono.
bool useMobileUi(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  // Web: iPhone/Android in landscape ha width > 768 ma resta un telefono.
  if (kIsWeb && size.shortestSide < CronosBreakpoints.phone) {
    return true;
  }
  if (isMobileDevice()) {
    return size.shortestSide < CronosBreakpoints.phone;
  }
  return size.width < CronosBreakpoints.compactUi;
}

/// Safari/Chrome su iOS o Android (User-Agent), anche con “sito desktop”.
bool isMobileWebPlatform() {
  if (!kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

/// Tablet nativo (Android/iOS) con schermo sufficientemente grande.
bool isTabletDevice(BuildContext context) {
  if (!isMobileDevice()) return false;
  return MediaQuery.sizeOf(context).shortestSide >= CronosBreakpoints.phone;
}

/// Tablet stretto o web in landscape ridotto: tabelle compatte, più colonne hub.
bool useCompactDataLayout(BuildContext context) {
  if (useMobileUi(context)) return true;
  return MediaQuery.sizeOf(context).width < CronosBreakpoints.logisticaCompact;
}

/// Sotto il breakpoint desktop (900px): card/lista invece di tabelle larghe.
bool useCompactPageLayout(BuildContext context) => !cronosIsDesktop(context);

T cronosAdaptiveValue<T>({
  required BuildContext context,
  required T phone,
  T? tablet,
  T? desktop,
  T? wide,
}) {
  switch (cronosFormFactor(context)) {
    case CronosFormFactor.phone:
      return phone;
    case CronosFormFactor.tablet:
      return tablet ?? phone;
    case CronosFormFactor.desktop:
      return desktop ?? tablet ?? phone;
    case CronosFormFactor.wide:
      return wide ?? desktop ?? tablet ?? phone;
  }
}

/// Padding orizzontale pagina in base al form factor.
double cronosPageHorizontalPadding(BuildContext context) {
  return cronosAdaptiveValue(
    context: context,
    phone: 12,
    tablet: 16,
    desktop: 20,
    wide: 24,
  );
}

/// Larghezza massima contenuti centrati (login, form, hub stretti).
double cronosContentMaxWidth(BuildContext context) {
  return cronosAdaptiveValue(
    context: context,
    phone: double.infinity,
    tablet: 720,
    desktop: 1080,
    wide: 1280,
  );
}

/// Larghezza dialog adattiva.
double cronosDialogWidth(BuildContext context, {double desktop = 520}) {
  final w = MediaQuery.sizeOf(context).width;
  if (useMobileUi(context)) return w * 0.94;
  if (w < CronosBreakpoints.tablet) return w * 0.92;
  return desktop.clamp(360.0, w * 0.85);
}

/// Colonne griglia hub.
int cronosHubCrossAxisCount({
  required BuildContext context,
  required int itemCount,
  double maxTileWidth = 220,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (useMobileUi(context)) {
    if (w < 360) return 1;
    if (w < 520) return 2;
    return 3;
  }
  if (w < CronosBreakpoints.phone) return 1;
  if (w < CronosBreakpoints.tablet) return 2;
  final count = ((w + 12) / (maxTileWidth + 12)).floor();
  return count.clamp(3, 7).clamp(1, itemCount > 0 ? itemCount : 1);
}

/// Larghezza minima cella griglia hub freeform (26 colonne, celle piccole).
double cronosHubMinCellWidth(BuildContext context) {
  return cronosAdaptiveValue(
    context: context,
    phone: 20,
    tablet: 26,
    desktop: 32,
    wide: 36,
  );
}

bool cronosIsUltraCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 400;

bool useUltraCompactAppBar(BuildContext context) =>
    MediaQuery.sizeOf(context).width < CronosBreakpoints.ultraCompactAppBar;

bool useCompactPageLayoutWidth(double width) =>
    width < CronosBreakpoints.tablet;

bool useUltraCompactAppBarWidth(double width) =>
    width < CronosBreakpoints.ultraCompactAppBar;

/// Larghezza campo a tutta riga su layout compatto.
double cronosFullFieldWidth(
  BuildContext context, {
  double horizontalMargin = 32,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (useCompactDataLayout(context)) {
    return (w - horizontalMargin).clamp(200.0, w);
  }
  return w;
}

/// Larghezza dialog form (sostituisce calcoli manuali `width - 48`).
double cronosFormDialogWidth(
  BuildContext context, {
  double desktop = 520,
  double min = 280,
}) {
  return cronosDialogWidth(context, desktop: desktop).clamp(min, desktop);
}

/// Padding pagina standard.
EdgeInsets cronosPagePadding(BuildContext context) {
  final h = cronosPageHorizontalPadding(context);
  return EdgeInsets.symmetric(horizontal: h, vertical: 8);
}

/// Extension comoda per le pagine.
extension CronosResponsiveContext on BuildContext {
  CronosFormFactor get formFactor => cronosFormFactor(this);
  bool get isPhone => cronosIsPhone(this);
  bool get isTablet => cronosIsTablet(this);
  bool get isDesktop => cronosIsDesktop(this);
  bool get isMobileUi => useMobileUi(this);
  bool get isCompactData => useCompactDataLayout(this);
  bool get isCompactPage => useCompactPageLayout(this);
  bool get isUltraCompact => cronosIsUltraCompact(this);
  double get pageHorizontalPadding => cronosPageHorizontalPadding(this);
  double dialogWidth({double desktop = 520}) =>
      cronosDialogWidth(this, desktop: desktop);
  double fieldWidth({double desktop = 320}) =>
      cronosAdaptiveValue(
        context: this,
        phone: cronosFullFieldWidth(this),
        tablet: desktop,
        desktop: desktop,
      );
}

/// Applica limiti di zoom testo per evitare layout rotti su web con font molto grandi.
MediaQueryData cronosClampMediaQuery(MediaQueryData data) {
  return data.copyWith(
    textScaler: data.textScaler.clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: kIsWeb ? 1.15 : 1.25,
    ),
  );
}
