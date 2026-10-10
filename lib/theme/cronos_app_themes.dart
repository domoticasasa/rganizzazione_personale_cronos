import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/cronos_3d_surface.dart';
import '../widgets/neon_orbit_border.dart';

/// Temi Material globali CRONOS (chiaro / scuro), allineati ai colori branding.
abstract final class CronosAppThemes {
  CronosAppThemes._();

  static const Color lightCanvas = Color(0xFFF5F8FA);

  /// Palette dark “performante”: quasi-nero con superfici leggermente elevate.
  static const Color darkCanvas = Color(0xFF070B10);
  static const Color darkAppBar = Color(0xFF05080C);
  static const Color darkSidebar = Color(0xFF0C1219);
  static const Color darkSurface = Color(0xFF141B24);
  static const Color darkSurfaceHigh = Color(0xFF1B2430);
  static const Color darkSidebarFg = Color(0xFFE6ECF5);
  static const Color darkSidebarFgMuted = Color(0xFF8E9CB0);

  static ThemeData light({
    required Color accent,
    required Color topBar,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    );
    return _base(
      scheme: scheme,
      accent: accent,
      topBar: topBar,
      canvas: lightCanvas,
      appBarFg: Colors.white,
      iconButtonBg: Colors.white.withValues(alpha: 0.2),
    );
  }

  static ThemeData dark({
    required Color accent,
    required Color topBar,
  }) {
    final seeded = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );
    final scheme = seeded.copyWith(
      primary: accent,
      surface: darkSurface,
      surfaceContainerLowest: darkCanvas,
      surfaceContainerLow: darkSidebar,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkSurfaceHigh,
      surfaceContainerHighest: darkSurfaceHigh,
      onSurface: darkSidebarFg,
      onSurfaceVariant: darkSidebarFgMuted,
      outline: Colors.white.withValues(alpha: 0.14),
      outlineVariant: Colors.white.withValues(alpha: 0.08),
    );
    return _base(
      scheme: scheme,
      accent: accent,
      topBar: darkAppBar,
      canvas: darkCanvas,
      appBarFg: Colors.white,
      iconButtonBg: Colors.white.withValues(alpha: 0.10),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color accent,
    required Color topBar,
    required Color canvas,
    required Color appBarFg,
    required Color iconButtonBg,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      fontFamily: kIsWeb ? 'Arial' : null,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: canvas,
      cardColor: isDark ? darkSurface : Colors.white,
      dividerColor: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.12),
      useMaterial3: false,
      iconTheme: IconThemeData(color: isDark ? darkSidebarFg : accent),
      appBarTheme: AppBarTheme(
        backgroundColor: topBar,
        foregroundColor: appBarFg,
        elevation: isDark ? 0 : 2,
        centerTitle: false,
        iconTheme: IconThemeData(color: appBarFg),
        actionsIconTheme: IconThemeData(color: appBarFg),
        titleTextStyle: TextStyle(
          color: appBarFg,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? darkSurface : Colors.white,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shadowColor: isDark ? Colors.transparent : null,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDark ? darkSidebarFg : accent,
        textColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: isDark,
        fillColor: isDark ? darkSurfaceHigh : null,
        border: const OutlineInputBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: cronos3dElevatedButtonStyle(
          foreground: isDark ? darkSidebarFg : accent,
          dark: isDark,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: cronos3dFilledButtonStyle(background: accent, dark: isDark),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: cronos3dOutlinedButtonStyle(
          foreground: isDark ? darkSidebarFg : accent,
          dark: isDark,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(
            isDark ? darkSidebarFg : accent,
          ),
          elevation: WidgetStateProperty.resolveWith<double>((states) {
            if (states.contains(WidgetState.pressed)) return 0;
            return 2;
          }),
          shadowColor: WidgetStateProperty.all(
            Colors.black.withValues(alpha: 0.18),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          backgroundBuilder: (context, states, child) {
            final c = child ?? const SizedBox.shrink();
            return NeonOrbitPaint(
              active: states.contains(WidgetState.hovered) &&
                  !states.contains(WidgetState.disabled),
              borderRadius: 999,
              child: c,
            );
          },
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          elevation: WidgetStateProperty.resolveWith<double>((states) {
            if (states.contains(WidgetState.pressed)) return 1;
            return 3;
          }),
          shadowColor: WidgetStateProperty.all(
            Colors.black.withValues(alpha: isDark ? 0.45 : 0.2),
          ),
          backgroundColor: WidgetStateProperty.all(iconButtonBg),
          shape: WidgetStateProperty.all(const CircleBorder()),
          backgroundBuilder: (context, states, child) {
            final c = child ?? const SizedBox.shrink();
            return NeonOrbitPaint(
              active: states.contains(WidgetState.hovered) &&
                  !states.contains(WidgetState.disabled),
              borderRadius: 999,
              strokeWidth: 1.8,
              child: c,
            );
          },
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : null,
        contentTextStyle: TextStyle(color: scheme.onSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? darkSurfaceHigh : Colors.white,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkSurface : Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : Colors.white,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? darkSidebar : null,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? darkSurfaceHigh
            : accent.withValues(alpha: 0.08),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSurface),
        brightness: scheme.brightness,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  static bool isDarkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color canvasOf(BuildContext context) =>
      isDarkOf(context) ? darkCanvas : lightCanvas;

  static Color cardOf(BuildContext context) =>
      isDarkOf(context) ? darkSurface : Colors.white;

  static Color cardMutedOf(BuildContext context) =>
      isDarkOf(context) ? darkSurfaceHigh : const Color(0xFFF3F6F9);

  static Color hairlineOf(BuildContext context) =>
      isDarkOf(context)
          ? Colors.white.withValues(alpha: 0.12)
          : const Color(0xFFD7E0EA);

  static Color onSurfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color mutedOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color selectedFillOf(BuildContext context) =>
      isDarkOf(context)
          ? const Color(0xFF1565C0).withValues(alpha: 0.32)
          : const Color(0xFFE3F2FD);

  static Color selectedBorderOf(BuildContext context) =>
      isDarkOf(context)
          ? const Color(0xFF90CAF9).withValues(alpha: 0.55)
          : const Color(0xFF90CAF9);

  static Color warnFillOf(BuildContext context) =>
      isDarkOf(context)
          ? const Color(0xFFFF9800).withValues(alpha: 0.16)
          : const Color(0xFFFFF3E0);
}
