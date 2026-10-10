import 'package:shared_preferences/shared_preferences.dart';

/// Ultima posizione GPS della mappa, sul dispositivo/browser.
class MdoMapUserLocationPrefs {
  MdoMapUserLocationPrefs._();

  // v3: non salvare più fix IP grossolani (es. Torino invece di Reggio).
  static const _lat = 'mdo_map_user_lat_v3';
  static const _lon = 'mdo_map_user_lon_v3';
  static const _acc = 'mdo_map_user_acc_v3';

  /// Accuratezza massima accettabile per cache / inquadramento città.
  static const maxUsefulAccuracyMeters = 2500.0;

  /// Area operativa tipica CRONOS (Italia + confine).
  static bool isPlausibleItalyArea(double lat, double lon) {
    return lat >= 35.5 && lat <= 47.6 && lon >= 6.2 && lon <= 18.8;
  }

  static bool isPreciseEnough(double accuracyMeters) =>
      accuracyMeters > 0 && accuracyMeters <= maxUsefulAccuracyMeters;

  static Future<({double lat, double lon, double accuracy})?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in const [
        'mdo_map_user_lat_v1',
        'mdo_map_user_lon_v1',
        'mdo_map_user_acc_v1',
        'mdo_map_user_lat_v2',
        'mdo_map_user_lon_v2',
        'mdo_map_user_acc_v2',
      ]) {
        await prefs.remove(k);
      }

      final lat = prefs.getDouble(_lat);
      final lon = prefs.getDouble(_lon);
      final acc = prefs.getDouble(_acc) ?? 99999;
      if (lat == null || lon == null) return null;
      if (!isPlausibleItalyArea(lat, lon) || !isPreciseEnough(acc)) {
        await clear();
        return null;
      }
      return (lat: lat, lon: lon, accuracy: acc);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required double lat,
    required double lon,
    required double accuracy,
  }) async {
    if (!isPlausibleItalyArea(lat, lon) || !isPreciseEnough(accuracy)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lat, lat);
    await prefs.setDouble(_lon, lon);
    await prefs.setDouble(_acc, accuracy);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lat);
    await prefs.remove(_lon);
    await prefs.remove(_acc);
  }
}
