import 'package:flutter/material.dart';

import '../theme/cronos_futuristic_theme.dart';
import 'gestopro_page_chrome.dart';

/// Colori per tabelle e pannelli dati: scuro in GESTOPRO, chiaro in modalità classica.
class GestoproDataPalette {
  const GestoproDataPalette._(this._gestopro);

  final bool _gestopro;

  bool get futuristic => _gestopro;

  factory GestoproDataPalette.of(BuildContext context) {
    return GestoproDataPalette._(isGestoproFuturisticUi(context));
  }

  static GestoproDataPalette classic() => const GestoproDataPalette._(false);

  Color get surface => _gestopro
      ? CronosFuturisticTheme.glassPanel.withValues(alpha: 0.94)
      : const Color(0xFFFFFFFF);

  Color get canvas => _gestopro
      ? CronosFuturisticTheme.deepSpace
      : const Color(0xFFE8EEF4);

  Color get border => _gestopro
      ? CronosFuturisticTheme.electricBright.withValues(alpha: 0.22)
      : const Color(0xFFD8E0EA);

  Color get textPrimary => _gestopro
      ? CronosFuturisticTheme.textPrimary
      : const Color(0xFF1A2B3C);

  Color get textMuted => _gestopro
      ? CronosFuturisticTheme.textMuted
      : const Color(0xFF5C6B7A);

  Color get headerMuted => _gestopro
      ? CronosFuturisticTheme.textMuted.withValues(alpha: 0.95)
      : const Color(0xFF37474F);

  Color get tableHeader => _gestopro
      ? CronosFuturisticTheme.textMuted
      : const Color(0xFF455A64);

  Color get estivo => _gestopro
      ? CronosFuturisticTheme.neonOrange
      : const Color(0xFFE65100);

  Color get estivoBg => _gestopro
      ? CronosFuturisticTheme.neonOrange.withValues(alpha: 0.14)
      : const Color(0xFFFFF3E0);

  Color get invernale => _gestopro
      ? CronosFuturisticTheme.neonCyan
      : const Color(0xFF1565C0);

  Color get invernaleBg => _gestopro
      ? CronosFuturisticTheme.electricBlue.withValues(alpha: 0.18)
      : const Color(0xFFE3F2FD);

  Color get alertBg => _gestopro
      ? CronosFuturisticTheme.neonOrange.withValues(alpha: 0.12)
      : const Color(0xFFFFF8E1);

  Color get alertBorder => _gestopro
      ? CronosFuturisticTheme.neonOrange.withValues(alpha: 0.35)
      : const Color(0xFFFFE082);

  Color get alertIcon => _gestopro
      ? CronosFuturisticTheme.neonOrange
      : const Color(0xFFE65100);

  Color get consegnati => _gestopro
      ? CronosFuturisticTheme.neonGreen
      : const Color(0xFF2E7D32);

  Color get consegnatiBg => _gestopro
      ? CronosFuturisticTheme.neonGreen.withValues(alpha: 0.14)
      : const Color(0xFFE8F5E9);

  Color get selectedTile => _gestopro
      ? CronosFuturisticTheme.electricBright.withValues(alpha: 0.22)
      : const Color(0x1A1976D2);

  Color get panelHeader => _gestopro
      ? CronosFuturisticTheme.electricBright.withValues(alpha: 0.1)
      : const Color(0x121976D2);

  double get radius =>
      _gestopro ? CronosFuturisticTheme.cardRadius : 8;

  static const EdgeInsets padCard = EdgeInsets.all(10);

  static const double fsTitle = 14;
  static const double fsLabel = 12;
  static const double fsBody = 13;
  static const double fsNum = 14;
  static const double fsTiny = 11;

  List<BoxShadow> get cardShadow => _gestopro
      ? [
          BoxShadow(
            color: CronosFuturisticTheme.electricBright.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ];
}
