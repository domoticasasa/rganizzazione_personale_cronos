import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_chat_overlay_controller.dart';
import '../services/app_chat_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/classic_nav_sub_items_cache.dart';
import '../services/dipendente_foto_prompt.dart';
import '../services/dipendente_qt_mancanti_prompt.dart';
import '../services/gestopro_mode_prefs.dart';
import '../services/web_app_badge.dart';
import 'app_navigator.dart';

/// Logout affidabile (anche mobile/PWA): non resta bloccato su `signOut` di rete.
Future<void> performAppLogout([BuildContext? context]) async {
  GestoproModePrefs.sessionActive = false;
  unawaited(GestoproModePrefs.deactivate());
  ClassicNavSessionCache.clear();
  ClassicNavSubItemsCache.clear();
  DipendenteFotoPrompt.resetSession();
  DipendenteQtMancantiPrompt.resetSession();
  AppChatOverlayController.close();
  unawaited(AppChatService.instance.stop());
  unawaited(WebAppBadge.clear());

  // Prima locale: toglie subito la sessione (evita auto-login al login).
  try {
    await Supabase.instance.client.auth
        .signOut(scope: SignOutScope.local)
        .timeout(const Duration(seconds: 4));
  } catch (_) {}

  // Best-effort revoca remota (non bloccare l'uscita).
  unawaited(() async {
    try {
      await Supabase.instance.client.auth
          .signOut(scope: SignOutScope.global)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }());

  final nav = appNavigatorKey.currentState ??
      (context != null && context.mounted
          ? Navigator.maybeOf(context, rootNavigator: true)
          : null) ??
      (context != null && context.mounted ? Navigator.maybeOf(context) : null);

  if (nav != null) {
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
    return;
  }

  final fallbackCtx = appNavigatorContext ?? context;
  if (fallbackCtx != null && fallbackCtx.mounted) {
    Navigator.of(fallbackCtx, rootNavigator: true)
        .pushNamedAndRemoveUntil('/login', (_) => false);
  }
}
