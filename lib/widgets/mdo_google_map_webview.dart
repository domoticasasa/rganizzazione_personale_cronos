import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';
import 'mdo_google_map_html.dart';

/// Mappa Google (JavaScript API) via webview_flutter (macOS desktop).
class MdoGoogleMapWebView extends StatefulWidget {
  const MdoGoogleMapWebView({
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
  State<MdoGoogleMapWebView> createState() => MdoGoogleMapWebViewState();
}

class MdoGoogleMapWebViewState extends State<MdoGoogleMapWebView> {
  WebViewController? _controller;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant MdoGoogleMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions ||
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.markerStyle != widget.markerStyle) {
      _pushMarkers();
    }
  }

  void _initController() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'CronosMap',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _mapReady = true;
            _pushMarkers();
          },
          onNavigationRequest: (req) {
            if (req.url.startsWith('cronosmap://')) {
              _handleMapMessage(
                Uri.decodeComponent(req.url.substring('cronosmap://'.length)),
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(mdoGoogleMapHtml(widget.apiKey));
    _controller = ctrl;
  }

  void _onJsMessage(JavaScriptMessage msg) => _handleMapMessage(msg.message);

  void _handleMapMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final type = (decoded['type'] ?? '').toString();
      if (type == 'ready') {
        _mapReady = true;
        _pushMarkers();
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

  Future<void> _runJs(String js) async {
    if (!_mapReady || _controller == null) return;
    try {
      await _controller!.runJavaScript(js);
    } catch (_) {}
  }

  void _pushMarkers() {
    _runJs(mdoMapUpdateMarkersJs(widget.positions, widget.markerStyle));
  }

  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {
    await _runJs(mdoMapUpdateMarkersJs(widget.positions, style));
  }

  Future<void> fitItaly() => _runJs('fitItaly();');

  Future<void> fitAllMarkers() => _runJs('fitAllMarkers();');

  Future<void> focusPosition(MdoMapPosition p) => _runJs(
        'focusMarker(${p.lat}, ${p.lon}, 11);',
      );

  Future<void> focusUserLocation(
    double lat,
    double lon, {
    double zoom = 12,
    double? accuracyMeters,
  }) {
    final acc = accuracyMeters ?? 80;
    return _runJs('setUserLocation($lat, $lon, $zoom, $acc);');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: ctrl);
  }
}
