// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';
import 'mdo_google_map_html.dart';

/// Mappa Google su Flutter Web (iframe + Maps JavaScript API).
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
  static int _nextViewId = 0;

  html.IFrameElement? _iframe;
  bool _ready = false;
  StreamSubscription<html.MessageEvent>? _msgSub;
  late final String _viewType = 'mdo-google-map-${_nextViewId++}';
  double? _pendingUserLat;
  double? _pendingUserLon;
  double _pendingUserZoom = 12;
  double? _pendingUserAccuracy;

  @override
  void initState() {
    super.initState();
    _msgSub = html.window.onMessage.listen(_onWindowMessage);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'geolocation'
        ..srcdoc = mdoGoogleMapHtml(widget.apiKey);
      _iframe = iframe;
      return iframe;
    });
  }

  @override
  void didUpdateWidget(covariant MdoGoogleMapBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions ||
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.markerStyle != widget.markerStyle) {
      _pushMarkers();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  void _onWindowMessage(html.MessageEvent event) {
    final raw = event.data?.toString() ?? '';
    _handleMapMessage(raw);
  }

  void _handleMapMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final type = (decoded['type'] ?? '').toString();
      if (type == 'ready') {
        setState(() => _ready = true);
        _pushMarkers();
        _flushUserLocation();
        return;
      }
      if (type == 'marker') {
        final id = (decoded['id'] ?? '').toString();
        final hit =
            widget.positions.where((p) => p.idUuid == id).firstOrNull;
        if (hit != null) widget.onMarkerTap?.call(hit);
      }
    } catch (_) {}
  }

  void _postToMap(Map<String, dynamic> message) {
    final win = _iframe?.contentWindow;
    if (win == null) return;
    win.postMessage(jsonEncode(message), '*');
  }

  void _pushMarkers() {
    if (!_ready) return;
    _postToMap(<String, dynamic>{
      'type': 'updateMarkers',
      'markers': mdoMarkersList(widget.positions),
      'style': widget.markerStyle.toJson(),
    });
  }

  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {
    if (!_ready) return;
    _postToMap(<String, dynamic>{
      'type': 'updateMarkers',
      'markers': mdoMarkersList(widget.positions),
      'style': style.toJson(),
    });
  }

  Future<void> fitItaly() async {
    _postToMap(<String, dynamic>{'type': 'fitItaly'});
  }

  Future<void> fitAllMarkers() async {
    _postToMap(<String, dynamic>{'type': 'fitAllMarkers'});
  }

  Future<void> focusPosition(MdoMapPosition p) async {
    _postToMap(<String, dynamic>{
      'type': 'focusMarker',
      'lat': p.lat,
      'lon': p.lon,
      'zoom': 11,
    });
  }

  Future<void> focusUserLocation(
    double lat,
    double lon, {
    double zoom = 12,
    double? accuracyMeters,
  }) async {
    _pendingUserLat = lat;
    _pendingUserLon = lon;
    _pendingUserZoom = zoom;
    _pendingUserAccuracy = accuracyMeters;
    _flushUserLocation();
  }

  void _flushUserLocation() {
    final lat = _pendingUserLat;
    final lon = _pendingUserLon;
    if (!_ready || lat == null || lon == null) return;
    _postToMap(<String, dynamic>{
      'type': 'setUserLocation',
      'lat': lat,
      'lon': lon,
      'zoom': _pendingUserZoom,
      if (_pendingUserAccuracy != null) 'accuracy': _pendingUserAccuracy,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready)
          const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
