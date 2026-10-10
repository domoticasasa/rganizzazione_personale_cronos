import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

/// Palette GESTOPRO — blu notte profondo, accenti morbidi (non neon aggressivo).
abstract final class CronosFuturisticTheme {
  static const Color voidBg = Color(0xFF0B1020);
  static const Color deepSpace = Color(0xFF121A2E);
  static const Color panelBg = Color(0xFF1A2438);
  static const Color electricBlue = Color(0xFF3D6FD9);
  static const Color electricBright = Color(0xFF5B8DEF);
  static const Color neonBlue = Color(0xFF6B9FE8);
  static const Color neonCyan = Color(0xFF8CB4F0);
  static const Color neonGreen = Color(0xFF5BC9A8);
  static const Color neonPurple = Color(0xFF9B7FD4);
  static const Color neonMagenta = Color(0xFFD46B9A);
  static const Color neonOrange = Color(0xFFE8A84A);
  static const Color neonRed = Color(0xFFE86A7A);
  static const Color neonGold = Color(0xFFD4B85C);
  static const Color neonTeal = Color(0xFF4DB8A8);
  static const Color cobaltBlue = Color(0xFF4A7FD4);
  static const Color glassPanel = Color(0xFF1E2A40);
  static const Color brushedMetal = Color(0xFF243048);
  static const Color hologramCyan = Color(0xFF7DAFFF);
  static const Color borderGlow = Color(0xFF5B8DEF);
  static const Color textPrimary = Color(0xFFE8EDF5);
  static const Color textMuted = Color(0xFF9AA8C0);

  static const Color bg = voidBg;
  static const double cardRadius = 14;
  static const double gridSpacing = 10;

  static List<Color> get auroraColors => [
        electricBlue.withValues(alpha: 0.0),
        electricBright.withValues(alpha: 0.12),
        neonPurple.withValues(alpha: 0.08),
        electricBlue.withValues(alpha: 0.0),
      ];

  static ThemeData themeData(TextTheme textTheme) {
    final colorScheme = ColorScheme.dark(
      surface: panelBg,
      onSurface: textPrimary,
      onSurfaceVariant: textMuted,
      primary: electricBright,
      onPrimary: Colors.white,
      secondary: neonCyan,
      onSecondary: voidBg,
      tertiary: neonPurple,
      error: neonRed,
      onError: Colors.white,
      outline: neonCyan.withValues(alpha: 0.22),
      outlineVariant: electricBright.withValues(alpha: 0.18),
      surfaceContainerHighest: brushedMetal,
      surfaceContainerHigh: glassPanel,
    );

    final base = textTheme.apply(
      bodyColor: textPrimary.withValues(alpha: 0.92),
      displayColor: textPrimary,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: voidBg,
      colorScheme: colorScheme,
      textTheme: base,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: deepSpace.withValues(alpha: 0.85),
        foregroundColor: textPrimary,
        titleTextStyle: CronosFonts.exo2(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: neonCyan.withValues(alpha: 0.9), size: 22),
      ),
      cardTheme: CardThemeData(
        color: glassPanel.withValues(alpha: 0.88),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: electricBright.withValues(alpha: 0.2)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: neonCyan,
        textColor: textPrimary.withValues(alpha: 0.9),
        tileColor: glassPanel.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: electricBright.withValues(alpha: 0.12)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: electricBright.withValues(alpha: 0.1),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: deepSpace.withValues(alpha: 0.75),
        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.85)),
        labelStyle: TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: electricBright.withValues(alpha: 0.22)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: electricBright.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: electricBright.withValues(alpha: 0.65), width: 1.2),
        ),
        prefixIconColor: neonCyan.withValues(alpha: 0.75),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glassPanel,
        selectedColor: electricBright.withValues(alpha: 0.28),
        labelStyle: CronosFonts.exo2(
          fontSize: 12,
          color: textPrimary.withValues(alpha: 0.9),
        ),
        secondaryLabelStyle: CronosFonts.exo2(color: Colors.white),
        side: BorderSide(color: electricBright.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      iconTheme: IconThemeData(color: neonCyan.withValues(alpha: 0.88)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: electricBright,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: glassPanel,
        contentTextStyle: CronosFonts.exo2(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: electricBright.withValues(alpha: 0.25)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: electricBright.withValues(alpha: 0.25)),
        ),
        titleTextStyle: CronosFonts.orbitron(
          color: textPrimary,
          fontSize: 15,
          letterSpacing: 1.2,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: electricBright.withValues(alpha: 0.2)),
        ),
        textStyle: CronosFonts.exo2(color: textPrimary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: electricBright,
        foregroundColor: Colors.white,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: neonCyan),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: electricBright.withValues(alpha: 0.88),
          foregroundColor: Colors.white,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(glassPanel),
        ),
      ),
    );
  }
}
