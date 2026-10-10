/// Famiglie font disponibili per i titoli dei tile hub.
abstract final class HubTileFonts {
  HubTileFonts._();

  static const String keyDefault = 'default';

  static const List<(String key, String label, String? family)> options =
      <(String, String, String?)>[
    (keyDefault, 'Predefinito', null),
    ('roboto', 'Roboto', 'Roboto'),
    ('arial', 'Arial', 'Arial'),
    ('georgia', 'Georgia (serif)', 'Georgia'),
    ('courier', 'Courier (mono)', 'Courier New'),
    ('segoe', 'Segoe UI', 'Segoe UI'),
  ];

  static String? familyForKey(String? key) {
    if (key == null || key.isEmpty || key == keyDefault) return null;
    for (final o in options) {
      if (o.$1 == key) return o.$3;
    }
    return null;
  }

  static String keyForFamily(String? family) {
    if (family == null || family.isEmpty) return keyDefault;
    for (final o in options) {
      if (o.$3 == family) return o.$1;
    }
    return keyDefault;
  }

  static String labelForKey(String? key) {
    for (final o in options) {
      if (o.$1 == (key ?? keyDefault)) return o.$2;
    }
    return 'Predefinito';
  }
}
