import 'package:flutter/material.dart';

import '../theme/cronos_app_themes.dart';
import '../widgets/futuristic/futuristic_shell_scope.dart';
import 'ember_fire_background.dart';
import 'liquid_water_background.dart';

/// Sfondo decorativo (treno) leggero, non invasivo per testi e tabelle.
class CronosAppBackground extends StatelessWidget {
  const CronosAppBackground({super.key});

  /// Sfondo "acqua liquida" azzurro interattivo (solo tema chiaro).
  /// Metti false per tornare allo sfondo con il treno.
  static const bool useLiquidWater = true;

  /// Sfondo scuro "fiammella" (braci + fuoco che segue il mouse), solo tema
  /// scuro. Metti false per tornare allo sfondo con il treno.
  static const bool useEmberFire = true;

  static const String landscapeAsset = 'assets/bg_train_landscape.png';
  static const String portraitAsset = 'assets/bg_train_portrait.png';

  /// Opacità dell'illustrazione (più alta = più visibile).
  static const double imageOpacityLight = 0.78;
  static const double imageOpacityDark = 0.22;

  /// Velo sopra l'immagine per mantenere contrasto sui contenuti.
  static const double veilOpacityLight = 0.06;
  static const double veilOpacityDark = 0.72;

  static const Color lightBaseColor = CronosAppThemes.lightCanvas;
  static const Color darkBaseColor = CronosAppThemes.darkCanvas;

  /// Compatibilità chiamate legacy (tema chiaro).
  static const Color baseColor = lightBaseColor;

  static Color baseColorOf(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? darkBaseColor : lightBaseColor;
  }

  @override
  Widget build(BuildContext context) {
    if (FuturisticShellScope.hideChromeOf(context)) {
      return const SizedBox.shrink();
    }

    // Tema chiaro: acqua liquida azzurra interattiva (vedi useLiquidWater).
    if (useLiquidWater && Theme.of(context).brightness != Brightness.dark) {
      return const LiquidWaterBackground();
    }

    // Tema scuro: fiammella che segue il puntatore (vedi useEmberFire).
    if (useEmberFire && Theme.of(context).brightness == Brightness.dark) {
      return const EmberFireBackground();
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? darkBaseColor : lightBaseColor;
    final imageOpacity = dark ? imageOpacityDark : imageOpacityLight;
    final veilOpacity = dark ? veilOpacityDark : veilOpacityLight;

    final size = MediaQuery.sizeOf(context);
    final usePortrait = size.height > size.width;
    final asset = usePortrait ? portraitAsset : landscapeAsset;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: base),
          Opacity(
            opacity: imageOpacity,
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              // Portrait/mobile: treno ancora più in basso, via dalla zona logo.
              alignment: usePortrait
                  ? const Alignment(0, 0.82)
                  : Alignment.center,
              filterQuality: FilterQuality.medium,
              color: dark ? Colors.black : null,
              colorBlendMode: dark ? BlendMode.softLight : null,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          ColoredBox(color: base.withValues(alpha: veilOpacity)),
          // Velo superiore: zona logo più pulita (web mobile / portrait).
          if (usePortrait && !dark)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xF5F2F6FC),
                    Color(0xCCF2F6FC),
                    Color(0x66F2F6FC),
                    Color(0x00F2F6FC),
                  ],
                  stops: [0.0, 0.18, 0.32, 0.48],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
