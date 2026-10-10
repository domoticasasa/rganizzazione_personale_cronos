import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';
import 'mdo_google_map_browser_stub.dart'
    if (dart.library.html) 'mdo_google_map_browser.dart';
import 'mdo_google_map_desktop.dart';
import 'mdo_google_map_webview.dart';

/// Mappa Google embedded per desktop (Windows WebView2, macOS webview).
class MdoGoogleMapEmbed extends StatefulWidget {
  const MdoGoogleMapEmbed({
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
  State<MdoGoogleMapEmbed> createState() => MdoGoogleMapEmbedState();
}

class MdoGoogleMapEmbedState extends State<MdoGoogleMapEmbed> {
  final _windowsKey = GlobalKey<MdoGoogleMapDesktopState>();
  final _macKey = GlobalKey<MdoGoogleMapWebViewState>();
  final _webKey = GlobalKey<MdoGoogleMapBrowserState>();

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> fitItaly() async {
    if (kIsWeb) {
      await _webKey.currentState?.fitItaly();
    } else if (_isWindows) {
      await _windowsKey.currentState?.fitItaly();
    } else {
      await _macKey.currentState?.fitItaly();
    }
  }

  Future<void> fitAllMarkers() async {
    if (kIsWeb) {
      await _webKey.currentState?.fitAllMarkers();
    } else if (_isWindows) {
      await _windowsKey.currentState?.fitAllMarkers();
    } else {
      await _macKey.currentState?.fitAllMarkers();
    }
  }

  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {
    if (kIsWeb) {
      await _webKey.currentState?.applyMarkerStyle(style);
    } else if (_isWindows) {
      await _windowsKey.currentState?.applyMarkerStyle(style);
    } else {
      await _macKey.currentState?.applyMarkerStyle(style);
    }
  }

  Future<void> focusPosition(MdoMapPosition p) async {
    if (kIsWeb) {
      await _webKey.currentState?.focusPosition(p);
    } else if (_isWindows) {
      await _windowsKey.currentState?.focusPosition(p);
    } else {
      await _macKey.currentState?.focusPosition(p);
    }
  }

  Future<void> focusUserLocation(
    double lat,
    double lon, {
    double zoom = 12,
    double? accuracyMeters,
  }) async {
    if (kIsWeb) {
      await _webKey.currentState?.focusUserLocation(
        lat,
        lon,
        zoom: zoom,
        accuracyMeters: accuracyMeters,
      );
    } else if (_isWindows) {
      await _windowsKey.currentState?.focusUserLocation(
        lat,
        lon,
        zoom: zoom,
        accuracyMeters: accuracyMeters,
      );
    } else {
      await _macKey.currentState?.focusUserLocation(
        lat,
        lon,
        zoom: zoom,
        accuracyMeters: accuracyMeters,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return MdoGoogleMapBrowser(
        key: _webKey,
        apiKey: widget.apiKey,
        positions: widget.positions,
        markerStyle: widget.markerStyle,
        onMarkerTap: widget.onMarkerTap,
      );
    }
    if (_isWindows) {
      return MdoGoogleMapDesktop(
        key: _windowsKey,
        apiKey: widget.apiKey,
        positions: widget.positions,
        markerStyle: widget.markerStyle,
        onMarkerTap: widget.onMarkerTap,
      );
    }
    return MdoGoogleMapWebView(
      key: _macKey,
      apiKey: widget.apiKey,
      positions: widget.positions,
      markerStyle: widget.markerStyle,
      onMarkerTap: widget.onMarkerTap,
    );
  }
}
