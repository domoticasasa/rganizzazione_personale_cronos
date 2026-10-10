import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../legal/gps_permission_explainer.dart';

export '../legal/gps_permission_explainer.dart' show GpsPurpose;

class BuoniPastoScanGps {
  const BuoniPastoScanGps._();

  /// Decimali salvati (4 ≈ 11 m): precisione ridotta, sufficiente per il
  /// controllo del luogo (audit legale M1).
  static const int storedDecimals = 4;

  static double _round(double v) =>
      double.parse(v.toStringAsFixed(storedDecimals));

  /// Lettura puntuale della posizione (nessun tracciamento continuo).
  /// Se [context] è passato e il permesso non è ancora concesso, mostra prima
  /// la schermata informativa (testo documento 07).
  static Future<({double lat, double lon})?> capture({
    BuildContext? context,
    GpsPurpose purpose = GpsPurpose.buonoPasto,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (context != null) {
          if (!context.mounted) return null;
          final ok = await GpsPermissionExplainer.show(context, purpose);
          if (!ok) return null;
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return (lat: _round(pos.latitude), lon: _round(pos.longitude));
    } catch (_) {
      return null;
    }
  }
}
