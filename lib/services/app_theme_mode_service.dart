import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferenza globale tema chiaro / scuro (persistita sul dispositivo).
class AppThemeModeService extends ChangeNotifier {
  AppThemeModeService._();

  static final AppThemeModeService instance = AppThemeModeService._();

  static const _prefsKey = 'cronos_app_theme_mode';

  ThemeMode _mode = ThemeMode.light;
  bool _loaded = false;

  ThemeMode get themeMode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();
      _mode = raw == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      _mode = ThemeMode.light;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDark(bool dark) async {
    final next = dark ? ThemeMode.dark : ThemeMode.light;
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, dark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> toggle() => setDark(!isDark);
}
