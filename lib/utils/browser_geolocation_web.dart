// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

/// Rileva posizione via `navigator.geolocation` (come Google Maps).
///
/// Su PC spesso il primo fix è solo IP (città sbagliata, es. Torino).
/// Per questo ascolta alcuni secondi e tiene il fix con accuratezza migliore.
Future<({double lat, double lon, double accuracy})?> getBrowserGeolocation({
  Duration timeout = const Duration(seconds: 20),
  /// Scarta fix troppo grossolani (tipici di geolocalizzazione IP).
  double maxAcceptableAccuracyMeters = 2500,
}) async {
  final geo = html.window.navigator.geolocation;
  ({double lat, double lon, double accuracy})? best;
  StreamSubscription<html.Geoposition>? sub;

  void consider(html.Geoposition pos) {
    final coords = pos.coords;
    if (coords == null) return;
    final lat = coords.latitude?.toDouble();
    final lon = coords.longitude?.toDouble();
    if (lat == null || lon == null) return;
    final acc = coords.accuracy?.toDouble() ?? 50000;
    if (best == null || acc < best!.accuracy) {
      best = (lat: lat, lon: lon, accuracy: acc);
    }
  }

  try {
    // Primo tentativo immediato.
    try {
      final first = await geo.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: timeout,
        maximumAge: Duration.zero,
      );
      consider(first);
    } catch (_) {}

    // Se già abbastanza preciso, stop.
    if (best != null && best!.accuracy <= maxAcceptableAccuracyMeters) {
      return best;
    }

    // Altrimenti aspetta aggiornamenti più precisi (Wi‑Fi / GPS).
    final done = Completer<void>();
    sub = geo.watchPosition(
      enableHighAccuracy: true,
      timeout: timeout,
      maximumAge: Duration.zero,
    ).listen(
      (pos) {
        consider(pos);
        if (best != null &&
            best!.accuracy <= maxAcceptableAccuracyMeters &&
            !done.isCompleted) {
          done.complete();
        }
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    await Future.any([
      done.future,
      Future<void>.delayed(const Duration(seconds: 10)),
    ]);
  } catch (_) {
    // ignore
  } finally {
    await sub?.cancel();
  }

  final out = best;
  if (out == null) return null;
  // Non restituire fix IP grossolani: meglio null che Torino sbagliato.
  if (out.accuracy > maxAcceptableAccuracyMeters) return null;
  return out;
}
