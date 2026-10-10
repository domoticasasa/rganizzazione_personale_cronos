import 'package:shared_preferences/shared_preferences.dart';

enum DashboardUiMode { classic, futuristic }

/// Preferenza locale: dashboard admin classica o interfaccia futuristica.
abstract final class DashboardUiModePrefs {
  DashboardUiModePrefs._();

  static const _key = 'admin_dashboard_ui_mode';

  static Future<DashboardUiMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_key) ?? '').trim();
    return raw == 'futuristic'
        ? DashboardUiMode.futuristic
        : DashboardUiMode.classic;
  }

  static Future<void> save(DashboardUiMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      mode == DashboardUiMode.futuristic ? 'futuristic' : 'classic',
    );
  }
}
