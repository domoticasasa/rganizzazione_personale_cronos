import 'dart:async';

import 'dart:convert';



import 'package:flutter/material.dart';

import 'package:webview_windows/webview_windows.dart';



import '../models/mdo_map_marker_style.dart';

import '../services/logistica_mdo_map_service.dart';

import '../services/windows_webview2_bootstrap.dart';

import 'mdo_flutter_map_view.dart';

import 'mdo_google_map_html.dart';



/// Mappa su Windows: Google Maps via WebView2, con fallback OpenStreetMap nativo.

class MdoGoogleMapDesktop extends StatefulWidget {

  const MdoGoogleMapDesktop({

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

  State<MdoGoogleMapDesktop> createState() => MdoGoogleMapDesktopState();

}



class MdoGoogleMapDesktopState extends State<MdoGoogleMapDesktop> {

  WebviewController? _ctrl;

  bool _ready = false;

  bool _initializing = false;

  bool _useFallback = false;

  final _fallbackKey = GlobalKey<MdoFlutterMapViewState>();

  StreamSubscription? _urlSub;

  StreamSubscription? _msgSub;



  @override

  void initState() {

    super.initState();

    unawaited(_init());

  }



  @override

  void didUpdateWidget(covariant MdoGoogleMapDesktop oldWidget) {

    super.didUpdateWidget(oldWidget);

    if (_useFallback) return;

    if (oldWidget.positions != widget.positions ||

        oldWidget.markerStyle != widget.markerStyle) {

      _pushMarkers();

    }

  }



  @override

  void dispose() {

    _urlSub?.cancel();

    _msgSub?.cancel();

    _ctrl?.dispose();

    super.dispose();

  }



  void _enableFallback() {

    if (!mounted || _useFallback) return;

    setState(() {

      _useFallback = true;

      _ready = false;

    });

    _urlSub?.cancel();

    _msgSub?.cancel();

    _urlSub = null;

    _msgSub = null;

    final old = _ctrl;

    _ctrl = null;

    unawaited(old?.dispose());

  }



  Future<void> _init() async {

    if (_initializing || _useFallback) return;

    _initializing = true;

    try {

      final envOk = await bootstrapWindowsWebView2();

      if (!envOk) {

        _enableFallback();

        return;

      }

      final ctrl = WebviewController();

      await ctrl.initialize();

      _msgSub = ctrl.webMessage.listen((msg) {

        _handleMapMessage(msg?.toString() ?? '');

      });

      _urlSub = ctrl.url.listen((url) {

        if (!url.startsWith('cronosmap://')) return;

        try {

          _handleMapMessage(

            Uri.decodeComponent(url.substring('cronosmap://'.length)),

          );

        } catch (_) {}

      });

      await ctrl.loadStringContent(mdoGoogleMapHtml(widget.apiKey));

      if (!mounted) {

        await ctrl.dispose();

        return;

      }

      setState(() {

        _ctrl = ctrl;

        _ready = true;

      });

    } catch (e) {

      debugPrint('WebView2 init failed: $e — using OpenStreetMap fallback');

      _enableFallback();

    } finally {

      _initializing = false;

    }

  }



  void _handleMapMessage(String raw) {

    final trimmed = raw.trim();

    if (trimmed.isEmpty) return;

    try {

      final decoded = jsonDecode(trimmed);

      if (decoded is! Map) return;

      final type = (decoded['type'] ?? '').toString();

      if (type == 'ready') {

        _ready = true;

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

    final ctrl = _ctrl;

    if (ctrl == null || !_ready) return;

    try {

      await ctrl.executeScript(js);

    } catch (_) {}

  }



  void _pushMarkers() {

    _runJs(mdoMapUpdateMarkersJs(widget.positions, widget.markerStyle));

  }



  Future<void> applyMarkerStyle(MdoMapMarkerStyle style) async {

    if (_useFallback) {

      await _fallbackKey.currentState?.applyMarkerStyle(style);

      return;

    }

    await _runJs(mdoMapUpdateMarkersJs(widget.positions, style));

  }



  Future<void> fitItaly() async {

    if (_useFallback) {

      await _fallbackKey.currentState?.fitItaly();

      return;

    }

    await _runJs('fitItaly();');

  }



  Future<void> fitAllMarkers() async {

    if (_useFallback) {

      await _fallbackKey.currentState?.fitAllMarkers();

      return;

    }

    await _runJs('fitAllMarkers();');

  }



  Future<void> focusPosition(MdoMapPosition p) async {

    if (_useFallback) {

      await _fallbackKey.currentState?.focusPosition(p);

      return;

    }

    await _runJs('focusMarker(${p.lat}, ${p.lon}, 11);');

  }



  Future<void> focusUserLocation(
    double lat,
    double lon, {
    double zoom = 12,
    double? accuracyMeters,
  }) async {

    if (_useFallback) {

      await _fallbackKey.currentState?.focusUserLocation(lat, lon, zoom: zoom);

      return;

    }

    final acc = accuracyMeters ?? 80;

    await _runJs('setUserLocation($lat, $lon, $zoom, $acc);');

  }



  @override

  Widget build(BuildContext context) {

    if (_useFallback) {

      return MdoFlutterMapView(

        key: _fallbackKey,

        positions: widget.positions,

        markerStyle: widget.markerStyle,

        onMarkerTap: widget.onMarkerTap,

      );

    }

    if (!_ready || _ctrl == null) {

      return const Center(child: CircularProgressIndicator());

    }

    return Webview(_ctrl!);

  }

}


