import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/mdo_gps_coords.dart';

/// Campo coordinate GPS: testo libero (lat, lon) + rilevamento da dispositivo.
class GpsCoordsInputRow extends StatelessWidget {
  const GpsCoordsInputRow({
    super.key,
    required this.controller,
    this.label = 'Coordinate GPS (lat, lon)',
    this.hint = 'es. 45.49805040586989, 9.219329053189183',
    this.dense = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool dense;

  static (double lat, double lon)? parseFromController(TextEditingController c) {
    return mdoGpsCoordsFromText(c.text);
  }

  static String formatCoords(double lat, double lon) => formatGpsCoordsText(lat, lon);

  Future<void> _captureGps(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('GPS disattivato: attiva la posizione sul dispositivo.'),
          ),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permesso posizione negato.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      controller.text = formatCoords(pos.latitude, pos.longitude);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Posizione GPS acquisita.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('GPS non disponibile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              isDense: dense,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: EdgeInsets.only(top: dense ? 4 : 8),
          child: IconButton.filledTonal(
            tooltip: 'Rileva posizione da telefono / GPS',
            onPressed: () => _captureGps(context),
            icon: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
