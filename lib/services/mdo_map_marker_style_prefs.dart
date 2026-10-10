import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mdo_map_marker_style.dart';

/// Preferenze locali stile marker mappa GPS (per dispositivo / browser).
class MdoMapMarkerStylePrefs {
  MdoMapMarkerStylePrefs._();

  static const _key = 'mdo_map_marker_style_v3';

  static Future<MdoMapMarkerStyle> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return MdoMapMarkerStyle.defaults;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return MdoMapMarkerStyle.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return MdoMapMarkerStyle.defaults;
  }

  static Future<void> save(MdoMapMarkerStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(style.toJson()));
  }
}
