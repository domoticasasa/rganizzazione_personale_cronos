import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Su **web** (e desktop) riduce tutta l'app in modo uniforme quando la
/// finestra del browser è più piccola di un monitor normale.
/// Telefono: layout mobile, senza questo zoom.
class CronosSmallScreenFit extends StatelessWidget {
  const CronosSmallScreenFit({super.key, required this.child});

  final Widget child;

  /// Riferimento “monitor normale”. Sul web l'altezza è più alta perché
  /// schede/barra del browser tolgono spazio visibile.
  static double get minWidth => 1280;
  static double get minHeight => kIsWeb ? 800 : 720;

  static bool get _isPhoneNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (_isPhoneNative) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mqSize = MediaQuery.sizeOf(context);
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : mqSize.width;
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : mqSize.height;
        if (w <= 0 || h <= 0) return child;
        final shortest = math.min(w, h);
        // Viewport da telefono in browser: resta il layout mobile.
        if (shortest < 600) return child;

        final scale = math.min(1.0, math.min(w / minWidth, h / minHeight));
        if (scale >= 0.999) return child;

        final logical = Size(w / scale, h / scale);
        final mq = MediaQuery.of(context);
        return SizedBox(
          width: w,
          height: h,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.center,
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: MediaQuery(
                data: _mediaQueryForLogicalSize(mq, logical, scale),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  static MediaQueryData _mediaQueryForLogicalSize(
    MediaQueryData mq,
    Size logical,
    double scale,
  ) {
    EdgeInsets scaled(EdgeInsets insets) => EdgeInsets.fromLTRB(
          insets.left / scale,
          insets.top / scale,
          insets.right / scale,
          insets.bottom / scale,
        );
    return mq.copyWith(
      size: logical,
      padding: scaled(mq.padding),
      viewPadding: scaled(mq.viewPadding),
      viewInsets: scaled(mq.viewInsets),
      systemGestureInsets: scaled(mq.systemGestureInsets),
    );
  }
}
