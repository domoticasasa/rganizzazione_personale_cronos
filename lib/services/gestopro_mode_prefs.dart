import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_ui_mode_prefs.dart';
import '../widgets/futuristic/gestopro_session_cache.dart';
import 'gestopro_ambient_sound_service.dart';
import 'gestopro_click_sound_service.dart';

/// Sessione GESTOPRO — interfaccia futuristica.
abstract final class GestoproModePrefs {
  GestoproModePrefs._();

  static const _key = 'gestopro_mode_active';

  /// Cache sincrona + listenable (sidebar classica ascolta questo).
  static final ValueNotifier<bool> sessionActiveListenable =
      ValueNotifier<bool>(false);

  static bool get sessionActive => sessionActiveListenable.value;

  static set sessionActive(bool value) {
    if (sessionActiveListenable.value == value) return;
    sessionActiveListenable.value = value;
  }

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    sessionActive = prefs.getBool(_key) ?? false;
    if (sessionActive) {
      unawaited(GestoproClickSoundService.preload());
    }
    unawaited(GestoproAmbientSoundService.syncWithSession(sessionActive));
    return sessionActive;
  }

  static Future<void> activate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    sessionActive = true;
    await DashboardUiModePrefs.save(DashboardUiMode.futuristic);
    // Non bloccare la navigazione su preload audio.
    unawaited(GestoproClickSoundService.preload());
    unawaited(GestoproAmbientSoundService.syncWithSession(true));
  }

  static Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    sessionActive = false;
    GestoproSessionCache.clear();
    await DashboardUiModePrefs.save(DashboardUiMode.classic);
    await GestoproAmbientSoundService.syncWithSession(false);
  }
}
