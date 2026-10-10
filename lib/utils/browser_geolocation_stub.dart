/// Stub non-web: nessun GPS nativo browser.
Future<({double lat, double lon, double accuracy})?> getBrowserGeolocation({
  Duration timeout = const Duration(seconds: 15),
  double maxAcceptableAccuracyMeters = 2500,
}) async =>
    null;
