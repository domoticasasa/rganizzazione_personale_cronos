import 'package:flutter/material.dart';

import '../services/app_chat_overlay_controller.dart';
import '../services/gestopro_mode_prefs.dart';

/// Marchio GESTOPRO360 in basso a sinistra, come filigrana di sfondo.
class GestoproCornerWatermark extends StatelessWidget {
  const GestoproCornerWatermark({
    super.key,
    this.alignToContentArea = false,
  });

  static const String assetPath = 'assets/gestopro360_watermark.png';

  /// Larghezza sidebar GESTOPRO (`FuturisticSidebar`).
  static const double gestoproSidebarWidth = 248;

  /// True se il widget è già a destra della rail classica.
  final bool alignToContentArea;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppChatOverlayController.splashBlocking,
      builder: (context, splash, _) {
        if (splash) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: GestoproModePrefs.sessionActiveListenable,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(context);
            final pad = MediaQuery.paddingOf(context);
            final gestopro = GestoproModePrefs.sessionActive;
            final extraLeft =
                (!alignToContentArea && gestopro && size.width >= 900)
                    ? gestoproSidebarWidth
                    : 0.0;
            final markW = (size.shortestSide * 0.26).clamp(128.0, 210.0);
            return IgnorePointer(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    10 + pad.left + extraLeft,
                    0,
                    0,
                    10 + pad.bottom,
                  ),
                  child: Opacity(
                    opacity: gestopro ? 0.22 : 0.14,
                    child: Image.asset(
                      assetPath,
                      width: markW,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
