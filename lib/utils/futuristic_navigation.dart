import 'package:flutter/material.dart';

import '../services/classic_nav_sub_items_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/futuristic_admin_nav.dart';

/// Navigazione centralizzata — shell GESTOPRO su tutte le pagine aperte.
abstract final class FuturisticNavigation {
  FuturisticNavigation._();

  /// Solo sessione GESTOPRO attiva (non la sola skin dashboard futuristica).
  static Future<bool> isGestoproActive() => GestoproModePrefs.isActive();

  static Future<T?> pushPage<T>(
    BuildContext context, {
    required Widget page,
    String? title,
    String? activeSubKey,
    VoidCallback? onAfter,
  }) {
    return _push<T>(
      context,
      page: page,
      title: title,
      activeSubKey: activeSubKey,
      onAfter: onAfter,
    );
  }

  static Future<T?> _push<T>(
    BuildContext context, {
    required Widget page,
    String? title,
    String? activeSubKey,
    VoidCallback? onAfter,
  }) async {
    final gestopro = await isGestoproActive();
    if (!context.mounted) return null;

    if (!gestopro) {
      if (activeSubKey != null) {
        ClassicNavSubItemsCache.setActiveKey(activeSubKey);
      }
      return Navigator.push<T>(
        context,
        MaterialPageRoute(builder: (_) => page),
      ).then((value) {
        onAfter?.call();
        return value;
      });
    }

    final destination = FuturisticAdminNav.wrapGestoproNavDestination(
      context: context,
      child: page,
      fallbackTitle: title,
      activeSubKey: activeSubKey,
    );

    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (_) => destination),
    ).then((value) {
      onAfter?.call();
      return value;
    });
  }
}
