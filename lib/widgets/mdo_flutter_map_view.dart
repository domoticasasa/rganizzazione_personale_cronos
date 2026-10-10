import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';
import '../utils/mdo_map_marker_spread.dart';
import '../utils/mdo_map_marker_zoom.dart';
import 'mdo_map_marker_icon.dart';
import 'mdo_map_marker_painter.dart';

/// Mappa interattiva Flutter (OpenStreetMap) — fallback Windows senza WebView2.
class MdoFlutterMapView extends StatefulWidget {
  const MdoFlutterMapView({
    super.key,
    required this.positions,
    required this.markerStyle,
    this.onMarkerTap,
  });

  final List<MdoMapPosition> positions;
  final MdoMapMarkerStyle markerStyle;
  final void Function(MdoMapPosition position)? onMarkerTap;

  @override
  State<MdoFlutterMapView> createState() => MdoFlutterMapViewState();
}

class MdoFlutterMapViewState extends State<MdoFlutterMapView> {
  static const _italyCenter = LatLng(42.5, 12.5);
  static const _italyZoom = 6.0;

  final _mapController = MapController();
  double _mapZoom = _italyZoom;

  @override
  void didUpdateWidget(covariant MdoFlutterMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions ||
        oldWidget.markerStyle != widget.markerStyle) {
      setState(() {});
    }
  }

  void _onMapEvent(MapEvent event) {
    final z = _mapController.camera.zoom;
    if ((z - _mapZoom).abs() < 0.04) return;
    setState(() => _mapZoom = z);
  }

  double _markerZoomScaleFor(MdoMapPosition p) {
    return mdoMapMarkerZoomScale(
      _mapZoom,
      kind: p.mapMarkerKind,
      userMapSizeScale: widget.markerStyle.mapSizeScale,
    );
  }

  Future<void> fitItaly() async {
    _mapController.move(_italyCenter, _italyZoom);
  }

  Future<void> fitAllMarkers() async {
    if (widget.positions.isEmpty) {
      await fitItaly();
      return;
    }
    final spread = spreadMdoMapMarkerCoords(widget.positions);
    final points =
        spread.values.map((c) => LatLng(c.lat, c.lon)).toList(growable: false);
    if (points.length == 1) {
      _mapController.move(points.first, 11);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  Future<void> focusPosition(MdoMapPosition p) async {
    _mapController.move(LatLng(p.lat, p.lon), 11);
  }

  Future<void> focusUserLocation(double lat, double lon, {double zoom = 12, double? accuracyMeters}) async {
    _mapController.move(LatLng(lat, lon), zoom);
  }

  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {
    if (!mounted) return;
    setState(() {});
  }

  Widget _markerChild(
    MdoMapPosition p,
    MdoMapMarkerCoords coords,
    double zoomScale,
  ) {
    final look = widget.markerStyle.resolveForKind(p.mapMarkerKind);
    final label = p.isCommessa
        ? commessaMapDisplayLabel(p.sigla)
        : p.sigla.trim().toUpperCase();
    final large = p.isCommessa;
    final w = (large ? 148.0 : 96.0) * zoomScale;
    final h = (large ? 128.0 : 112.0) * zoomScale;
    return Transform.rotate(
      angle: coords.rotationDeg * math.pi / 180,
      alignment: Alignment.bottomCenter,
      child: CustomPaint(
        size: Size(w, h),
        painter: MdoMapMarkerPainter(
          label: label,
          look: look,
          large: large,
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final spread = spreadMdoMapMarkerCoords(widget.positions);
    final out = <Marker>[];
    for (final p in widget.positions) {
      final coords = spread[p.idUuid]!;
      final zoomScale = _markerZoomScaleFor(p);
      final large = p.isCommessa;
      final w = (large ? 148.0 : 96.0) * zoomScale;
      final h = (large ? 128.0 : 112.0) * zoomScale;
      out.add(
        Marker(
          point: LatLng(coords.lat, coords.lon),
          width: w + 8,
          height: h + 8,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => widget.onMarkerTap?.call(p),
            child: _markerChild(p, coords, zoomScale),
          ),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _italyCenter,
            initialZoom: _italyZoom,
            minZoom: 4,
            maxZoom: 18,
            onMapEvent: _onMapEvent,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.cronos.organizzazione_personale',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                'OpenStreetMap',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
