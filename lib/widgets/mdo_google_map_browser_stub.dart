import 'package:flutter/material.dart';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';

/// Placeholder non-web (non usato).
class MdoGoogleMapBrowser extends StatefulWidget {
  const MdoGoogleMapBrowser({
    super.key,
    required this.apiKey,
    required this.positions,
    required this.markerStyle,
    this.onMarkerTap,
  });

  final String apiKey;
  final List<MdoMapPosition> positions;
  final MdoMapMarkerStyle markerStyle;
  final void Function(MdoMapPosition position)? onMarkerTap;

  @override
  State<MdoGoogleMapBrowser> createState() => MdoGoogleMapBrowserState();
}

class MdoGoogleMapBrowserState extends State<MdoGoogleMapBrowser> {
  Future<void> fitItaly() async {}
  Future<void> fitAllMarkers() async {}
  Future<void> focusPosition(MdoMapPosition p) async {}
  Future<void> focusUserLocation(
    double lat,
    double lon, {
    double zoom = 12,
    double? accuracyMeters,
  }) async {}
  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {}

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
