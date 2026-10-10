import 'dart:async';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../config/google_maps_config.dart';
import '../pages/admin_estintori_page.dart';
import '../pages/admin_logistica_attrezzature_page.dart';
import '../pages/admin_logistica_casette_ps_page.dart';
import '../pages/admin_logistica_box_page.dart';
import '../pages/admin_logistica_mdo_ferroviari_page.dart';
import '../pages/admin_logistica_officine_convenzionate_page.dart';
import '../pages/admin_master_data_page.dart';
import '../models/commessa_linked_assets.dart';
import '../models/mdo_map_marker_style.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/logistica_mdo_map_service.dart';
import '../services/mdo_map_marker_style_prefs.dart';
import '../services/mdo_map_user_location_prefs.dart';
import '../widgets/mdo_map_marker_style_dialog.dart';
import '../utils/browser_geolocation.dart';
import '../utils/logistica_layout.dart';
import '../utils/mdo_map_marker_spread.dart';
import '../utils/mdo_map_marker_zoom.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/app_logo.dart';
import '../widgets/mdo_google_map_embed.dart';
import '../widgets/mdo_map_marker_icon.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Centro approssimativo Italia.
const _italyCenter = LatLng(42.5, 12.5);
const _italyZoom = 5.8;

enum _MappaLayerFiltro {
  tuttiMdo,
  tutteCommesse,
  box,
  estintori,
  casettePs,
  strutture,
  officine,
  perCommessa,
}

class AdminLogisticaMdoMappaPage extends StatefulWidget {
  const AdminLogisticaMdoMappaPage({super.key});

  @override
  State<AdminLogisticaMdoMappaPage> createState() =>
      _AdminLogisticaMdoMappaPageState();
}

class _AdminLogisticaMdoMappaPageState extends State<AdminLogisticaMdoMappaPage> {
  final _service = LogisticaMdoMapService();
  final _searchCtrl = TextEditingController();
  final _embedMapKey = GlobalKey<MdoGoogleMapEmbedState>();
  GoogleMapController? _nativeMapCtrl;
  Timer? _refreshTimer;

  bool _loading = true;
  String? _error;
  String _search = '';
  bool _showListPanel = false;
  List<MdoMapPosition> _positions = [];
  List<MdoMapPosition> _boxPositions = [];
  List<MdoMapPosition> _estintoriPositions = [];
  List<MdoMapPosition> _casettePsPositions = [];
  List<MdoMapPosition> _strutturePositions = [];
  List<MdoMapPosition> _officinePositions = [];
  Set<Marker> _markers = {};
  double _mapZoom = _italyZoom;
  Timer? _markerRebuildDebounce;
  int _markerZoomBucket = _italyZoom.round();
  MdoMapPosition? _selected;
  _MappaLayerFiltro _layerFiltro = _MappaLayerFiltro.tuttiMdo;
  MdoMapMarkerStyle _markerStyle = MdoMapMarkerStyle.defaults;
  bool _blockMapPointer = false;
  LatLng? _userLocation;
  double? _userAccuracy;
  bool _locatingUser = false;

  List<CommessaOption> _commesseOptions = [];
  String? _selectedCommessaId;
  CommessaLinkedAssets? _linkedAssets;
  bool _loadingLinked = false;

  bool get _isPerCommessaView => _layerFiltro == _MappaLayerFiltro.perCommessa;

  bool get _useNativeGoogleMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _useEmbedMap =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _canShowMap => GoogleMapsConfig.isConfigured;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMarkerStylePrefs());
    unawaited(_loadCommesseOptions());
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text;
      if (q == _search) return;
      setState(() => _search = q);
      unawaited(_rebuildMarkers());
    });
    unawaited(_load());
    unawaited(_restoreCachedGps());
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      unawaited(_load(showLoader: false));
    });
  }

  @override
  void dispose() {
    _markerRebuildDebounce?.cancel();
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    _nativeMapCtrl?.dispose();
    super.dispose();
  }

  List<MdoMapPosition> get _layerFiltered {
    switch (_layerFiltro) {
      case _MappaLayerFiltro.tuttiMdo:
        return _positions.where((p) => p.isMdo).toList(growable: false);
      case _MappaLayerFiltro.tutteCommesse:
        return _positions.where((p) => p.isCommessa).toList(growable: false);
      case _MappaLayerFiltro.box:
        return _filterPositions(_boxPositions);
      case _MappaLayerFiltro.estintori:
        return _filterPositions(_estintoriPositions);
      case _MappaLayerFiltro.casettePs:
        return _filterPositions(_casettePsPositions);
      case _MappaLayerFiltro.strutture:
        return _filterPositions(_strutturePositions);
      case _MappaLayerFiltro.officine:
        return _filterPositions(_officinePositions);
      case _MappaLayerFiltro.perCommessa:
        return _linkedMapPoints;
    }
  }

  List<MdoMapPosition> get _linkedMapPoints {
    final assets = _linkedAssets;
    if (assets == null) return const [];
    final out = <MdoMapPosition>[];
    if (assets.commessaLat != null && assets.commessaLon != null) {
      out.add(
        MdoMapPosition(
          idUuid: assets.commessaIdUuid,
          sigla: assets.commessaNome,
          lat: assets.commessaLat!,
          lon: assets.commessaLon!,
          kind: MapPointKind.commessa,
          commessaIdUuid: assets.commessaIdUuid,
          commessa: assets.commessaNome,
        ),
      );
    }
    for (final item in assets.allItems) {
      if (!item.hasGps) continue;
      out.add(
        MdoMapPosition(
          idUuid: item.idUuid,
          sigla: item.label,
          lat: item.lat!,
          lon: item.lon!,
          kind: switch (item.assetType) {
            'box' => MapPointKind.box,
            'mdo' => MapPointKind.mdo,
            'estintore' => MapPointKind.estintore,
            'casetta_ps' => MapPointKind.casettaPs,
            _ => MapPointKind.commessa,
          },
          descrizioneMezzo: item.subtitle,
          commessa: assets.commessaNome,
          commessaIdUuid: assets.commessaIdUuid,
        ),
      );
    }
    return out;
  }

  List<MdoMapPosition> get _filtered {
    final base = _layerFiltered;
    if (_isPerCommessaView) return base;
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((p) {
      final tokens = [
        p.sigla,
        p.targaRfi,
        p.descrizioneMezzo,
        p.cantiere,
        p.commessa,
        p.kindLabel,
      ];
      return tokens.any((t) => (t ?? '').toLowerCase().contains(q));
    }).toList(growable: false);
  }

  List<MdoMapPosition> _filterPositions(List<MdoMapPosition> source) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((p) {
      final tokens = [
        p.sigla,
        p.descrizioneMezzo,
        p.commessa,
        p.coordsLabel,
        p.kindLabel,
      ];
      return tokens.any((t) => (t ?? '').toLowerCase().contains(q));
    }).toList(growable: false);
  }

  List<MdoMapPosition> get _mapDisplayPoints => _filtered;

  Future<void> _loadCommesseOptions() async {
    try {
      final list = await _service.fetchCommesseOptions();
      if (!mounted) return;
      setState(() => _commesseOptions = list);
    } catch (_) {}
  }

  Future<void> _loadLinkedAssetsForSelected() async {
    final id = (_selectedCommessaId ?? '').trim();
    if (id.isEmpty) {
      setState(() {
        _linkedAssets = null;
        _loadingLinked = false;
      });
      return;
    }
    final opt = _commesseOptions.firstWhere(
      (c) => c.idUuid == id,
      orElse: () => CommessaOption(idUuid: id, nome: id),
    );
    setState(() => _loadingLinked = true);
    try {
      final assets = await _service.fetchLinkedAssetsForCommessa(
        commessaIdUuid: id,
        commessaNome: opt.nome,
      );
      if (!mounted) return;
      setState(() {
        _linkedAssets = assets;
        _loadingLinked = false;
        _selected = null;
      });
      await _rebuildMarkers();
      if (_useEmbedMap) {
        await _embedMapKey.currentState?.applyMarkerStyle(_markerStyle);
      }
      if (_canShowMap && _linkedMapPoints.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_fitVisibleMarkers());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linkedAssets = null;
        _loadingLinked = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final list = await _service.fetchAllMapPoints();
      final boxes = await _service.fetchBoxesWithGps();
      final estintori = await _service.fetchEstintoriWithGps();
      final casette = await _service.fetchCasettePsWithGps();
      final strutture = await _service.fetchStruttureWithGps();
      final officine = await _service.fetchOfficineWithGps();
      if (!mounted) return;
      setState(() {
        _positions = list;
        _boxPositions = boxes;
        _estintoriPositions = estintori;
        _casettePsPositions = casette;
        _strutturePositions = strutture;
        _officinePositions = officine;
        _error = null;
        _loading = false;
      });
      await _rebuildMarkers();
      if (_useEmbedMap) {
        await _embedMapKey.currentState?.applyMarkerStyle(_markerStyle);
      }
      if (_selected != null &&
          !_mapDisplayPoints.any((p) => p.idUuid == _selected!.idUuid)) {
        setState(() => _selected = null);
      }
      if (showLoader && _canShowMap && !_isPerCommessaView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_applyUserCityFrame());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMarkerStylePrefs() async {
    final style = await MdoMapMarkerStylePrefs.load();
    if (!mounted) return;
    setState(() => _markerStyle = style);
    await _embedMapKey.currentState?.applyMarkerStyle(style);
    if (_useNativeGoogleMap) await _rebuildMarkers();
  }

  Future<void> _editMarkerStyle() async {
    setState(() => _blockMapPointer = true);
    MdoMapMarkerStyle? result;
    try {
      result = await showMdoMapMarkerStyleDialog(
        context,
        initial: _markerStyle,
      );
    } finally {
      if (mounted) setState(() => _blockMapPointer = false);
    }
    if (!mounted || result == null) return;
    final style = result;
    setState(() => _markerStyle = style);
    await MdoMapMarkerStylePrefs.save(style);
    await _embedMapKey.currentState?.applyMarkerStyle(style);
    if (_useNativeGoogleMap) await _rebuildMarkers();
  }

  double _markerZoomScaleFor(MdoMapPosition p) {
    return mdoMapMarkerZoomScale(
      _mapZoom,
      kind: p.mapMarkerKind,
      userMapSizeScale: _markerStyle.mapSizeScale,
    );
  }

  Future<void> _rebuildMarkers() async {
    if (!_useNativeGoogleMap) return;
    final list = _mapDisplayPoints;
    final spread = spreadMdoMapMarkerCoords(list);
    final markers = <Marker>{};
    for (final p in list) {
      final c = spread[p.idUuid]!;
      final zoomScale = _markerZoomScaleFor(p);
      final BitmapDescriptor icon;
      if (p.isCommessa) {
        icon = await commessaMapMarkerIcon(
          p.sigla,
          zoomScale: zoomScale,
          style: _markerStyle,
        );
      } else if (p.isBox) {
        icon = await boxMapMarkerIcon(
          p.sigla,
          zoomScale: zoomScale,
          style: _markerStyle,
        );
      } else if (p.isEstintore) {
        icon = await estintoreMapMarkerIcon(
          p.sigla,
          zoomScale: zoomScale,
          style: _markerStyle,
        );
      } else if (p.isCasettaPs) {
        icon = await casettaPsMapMarkerIcon(
          p.sigla,
          zoomScale: zoomScale,
          style: _markerStyle,
        );
      } else if (p.isStruttura || p.isOfficina) {
        icon = await mapMarkerIcon(
          p.sigla,
          look: _markerStyle.resolveForKind(p.mapMarkerKind),
          zoomScale: zoomScale,
        );
      } else {
        icon = await mdoMapMarkerIcon(
          p.sigla,
          zoomScale: zoomScale,
          style: _markerStyle,
        );
      }
      markers.add(
        Marker(
          markerId: MarkerId('${p.kind.name}_${p.idUuid}'),
          position: LatLng(c.lat, c.lon),
          rotation: c.rotationDeg,
          anchor: const Offset(0.5, 1.0),
          flat: true,
          icon: icon,
          infoWindow: InfoWindow(
            title: '${p.kindLabel}: ${p.sigla}',
            snippet: p.lastDetectedLabel,
          ),
          onTap: () => _onMarkerTap(p),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _markers = markers);
  }

  void _onMarkerTap(MdoMapPosition p) {
    setState(() => _selected = p);
    unawaited(_focusMezzo(p, updateSearch: false));
  }

  Future<void> _focusMezzo(MdoMapPosition p, {bool updateSearch = true}) async {
    if (updateSearch) {
      setState(() {
        _selected = p;
        _searchCtrl.text = p.sigla;
        _search = p.sigla;
      });
      await _rebuildMarkers();
      if (_useEmbedMap) {
        await _embedMapKey.currentState?.applyMarkerStyle(_markerStyle);
      }
    }
    if (_useNativeGoogleMap) {
      await _nativeMapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(p.lat, p.lon), 11),
      );
    } else if (_useEmbedMap) {
      await _embedMapKey.currentState?.focusPosition(p);
    }
  }

  Future<void> _fitAllItaly() async {
    if (_useNativeGoogleMap) {
      await _nativeMapCtrl?.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: _italyCenter, zoom: _italyZoom),
        ),
      );
    } else if (_useEmbedMap) {
      await _embedMapKey.currentState?.fitItaly();
    }
  }

  double _zoomForGpsAccuracy(double? meters) {
    final a = meters ?? 1500;
    if (a >= 20000) return 10;
    if (a >= 5000) return 11;
    if (a >= 1200) return 12.5;
    if (a >= 400) return 13.5;
    return 15;
  }

  Future<void> _restoreCachedGps() async {
    final cached = await MdoMapUserLocationPrefs.load();
    if (!mounted) return;
    if (cached == null) return;
    _userLocation = LatLng(cached.lat, cached.lon);
    _userAccuracy = cached.accuracy;
    unawaited(_applyUserCityFrame());
  }

  /// Su web usa `navigator.geolocation` come Google Maps; altrimenti Geolocator.
  Future<({double lat, double lon, double accuracy})?> _readDeviceGps({
    required bool allowPrompt,
  }) async {
    if (kIsWeb) {
      return getBrowserGeolocation(timeout: const Duration(seconds: 20));
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!allowPrompt) return null;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    ).timeout(const Duration(seconds: 15));
    return (lat: pos.latitude, lon: pos.longitude, accuracy: pos.accuracy);
  }

  Future<void> _locateUserCity({
    bool silent = true,
    bool allowPrompt = true,
  }) async {
    if (_locatingUser) {
      if (_userLocation != null) await _applyUserCityFrame();
      return;
    }
    _locatingUser = true;
    try {
      final fix = await _readDeviceGps(allowPrompt: allowPrompt);
      if (!mounted) return;
      if (fix == null) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Posizione troppo imprecisa (solo rete/IP, es. Torino). '
                'Su PC apri Chrome → impostazioni posizione e consenti la posizione precisa per questo sito, '
                'poi clicca di nuovo la mira. Su telefono è più affidabile.',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }
      if (!MdoMapUserLocationPrefs.isPlausibleItalyArea(fix.lat, fix.lon) ||
          !MdoMapUserLocationPrefs.isPreciseEnough(fix.accuracy)) {
        await MdoMapUserLocationPrefs.clear();
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Posizione scartata (±${fix.accuracy.round()} m): troppo imprecisa o fuori area. '
                'Riprova con la mira dopo aver consentito la posizione precisa.',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      await _commitGpsFix(
        lat: fix.lat,
        lon: fix.lon,
        accuracy: fix.accuracy,
      );
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Posizione: ${fix.lat.toStringAsFixed(5)}, ${fix.lon.toStringAsFixed(5)}'
              '${fix.accuracy < 5000 ? ' (±${fix.accuracy.round()} m)' : ''}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Posizione non disponibile: $e')),
        );
      }
    } finally {
      _locatingUser = false;
    }
  }

  Future<void> _commitGpsFix({
    required double lat,
    required double lon,
    required double accuracy,
  }) async {
    if (!mounted) return;
    if (!MdoMapUserLocationPrefs.isPlausibleItalyArea(lat, lon)) return;
    _userLocation = LatLng(lat, lon);
    _userAccuracy = accuracy;
    unawaited(
      MdoMapUserLocationPrefs.save(
        lat: lat,
        lon: lon,
        accuracy: accuracy,
      ),
    );
    await _applyUserCityFrame();
  }

  Future<void> _applyUserCityFrame({int attempt = 0}) async {
    final loc = _userLocation;
    if (loc == null) return;
    if (!mounted || !_canShowMap) return;
    final zoom = _zoomForGpsAccuracy(_userAccuracy);
    if (_useNativeGoogleMap) {
      if (_nativeMapCtrl == null && attempt < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        return _applyUserCityFrame(attempt: attempt + 1);
      }
      await _nativeMapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(loc, zoom),
      );
      return;
    }
    if (_useEmbedMap) {
      final embed = _embedMapKey.currentState;
      if (embed == null && attempt < 16) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        return _applyUserCityFrame(attempt: attempt + 1);
      }
      await embed?.focusUserLocation(
        loc.latitude,
        loc.longitude,
        zoom: zoom,
        accuracyMeters: _userAccuracy,
      );
    }
  }

  Future<void> _fitVisibleMarkers() async {
    final list = _mapDisplayPoints;
    if (list.isEmpty) {
      await _fitAllItaly();
      return;
    }
    if (list.length == 1) {
      await _focusMezzo(list.first, updateSearch: false);
      return;
    }
    if (_useNativeGoogleMap) {
      final spread = spreadMdoMapMarkerCoords(list);
      double minLat = spread.values.first.lat;
      double maxLat = minLat;
      double minLon = spread.values.first.lon;
      double maxLon = minLon;
      for (final c in spread.values) {
        if (c.lat < minLat) minLat = c.lat;
        if (c.lat > maxLat) maxLat = c.lat;
        if (c.lon < minLon) minLon = c.lon;
        if (c.lon > maxLon) maxLon = c.lon;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLon),
        northeast: LatLng(maxLat, maxLon),
      );
      await _nativeMapCtrl?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 56),
      );
    } else if (_useEmbedMap) {
      await _embedMapKey.currentState?.fitAllMarkers();
    }
  }

  void _openLinkedItem(CommessaLinkedItem item) {
    final id = item.idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 5);
    switch (item.assetType) {
      case 'mdo':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => useMobileUi(context)
                ? const AdminLogisticaMdoFerroviariMobilePage()
                : const AdminLogisticaMdoFerroviariPage(),
          ),
        );
      case 'box':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => useMobileUi(context)
                ? const AdminLogisticaBoxMobilePage()
                : const AdminLogisticaBoxPage(),
          ),
        );
      case 'estintore':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => useMobileUi(context)
                ? const AdminEstintoriMobilePage()
                : const AdminEstintoriPage(),
          ),
        );
      case 'attrezzatura':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => useMobileUi(context)
                ? const AdminLogisticaAttrezzatureMobilePage()
                : const AdminLogisticaAttrezzaturePage(),
          ),
        );
      case 'casetta_ps':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (ctx) => useMobileUi(context)
                ? const AdminLogisticaCasettePsMobilePage()
                : const AdminLogisticaCasettePsPage(),
          ),
        );
    }
  }

  void _openInMdoLogistica(MdoMapPosition p) {
    if (!p.isMdo) return;
    final id = p.idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 5);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => useMobileUi(context)
            ? const AdminLogisticaMdoFerroviariMobilePage()
            : const AdminLogisticaMdoFerroviariPage(),
      ),
    );
  }

  void _openInBoxLogistica(MdoMapPosition p) {
    if (!p.isBox) return;
    final id = p.idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 5);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => useMobileUi(context)
            ? const AdminLogisticaBoxMobilePage()
            : const AdminLogisticaBoxPage(),
      ),
    );
  }

  void _openInEstintori(MdoMapPosition p) {
    if (!p.isEstintore) return;
    final id = p.idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 5);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => useMobileUi(context)
            ? const AdminEstintoriMobilePage()
            : const AdminEstintoriPage(),
      ),
    );
  }

  void _openInCasettePs(MdoMapPosition p) {
    if (!p.isCasettaPs) return;
    final id = p.idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 5);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => useMobileUi(context)
            ? const AdminLogisticaCasettePsMobilePage()
            : const AdminLogisticaCasettePsPage(),
      ),
    );
  }

  void _openInStruttureAnagrafica(MdoMapPosition p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => AdminMasterDataPage(
          initialTabIndex: 3, // tab "Strutture"
          highlightStructureId: p.idUuid,
        ),
      ),
    );
  }

  void _openInOfficine(MdoMapPosition p) {
    if (!p.isOfficina) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => useMobileUi(context)
            ? const AdminLogisticaOfficineConvenzionateMobilePage()
            : const AdminLogisticaOfficineConvenzionatePage(),
      ),
    );
  }

  Future<void> _openExternalMap(MdoMapPosition p) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final mapPoints = _mapDisplayPoints;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Mappa GPS MDO e commesse'),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showListPanel ? 'Nascondi lista' : 'Mostra lista mezzi',
            onPressed: () => setState(() => _showListPanel = !_showListPanel),
            icon: Icon(_showListPanel ? Icons.map : Icons.list),
          ),
          IconButton(
            tooltip: 'Dimensione e forma marker',
            onPressed: _editMarkerStyle,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Aggiorna dati',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Vai alla mia posizione',
            onPressed: () => _locateUserCity(silent: false, allowPrompt: true),
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Inquadra tutti i mezzi',
            onPressed: mapPoints.isEmpty ? null : _fitVisibleMarkers,
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            tooltip: 'Vista Italia',
            onPressed: _fitAllItaly,
            icon: const Icon(Icons.public),
          ),
        ],
      )),
      body: _buildBody(mapPoints),
    );
  }

  Widget _buildBody(List<MdoMapPosition> filtered) {
    if (!_isPerCommessaView && _loading && _positions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isPerCommessaView && _error != null && _positions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Errore caricamento: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(),
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    final compact = isLogisticaCompactLayout(context);
    final listH = (MediaQuery.sizeOf(context).height * 0.32).clamp(160.0, 320.0);
    final sidePanel = _isPerCommessaView
        ? SizedBox(width: compact ? double.infinity : 360, child: _buildPerCommessaListPanel())
        : (_showListPanel
            ? _buildSideList(filtered, fullWidth: compact)
            : null);

    return Column(
      children: [
        _buildSearchBar(filtered.length),
        Expanded(
          child: compact
              ? Column(
                  children: [
                    Expanded(child: _buildMainMapArea(filtered)),
                    if (sidePanel != null)
                      SizedBox(
                        height: _isPerCommessaView
                            ? (MediaQuery.sizeOf(context).height * 0.36)
                                .clamp(180.0, 360.0)
                            : listH,
                        child: sidePanel,
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildMainMapArea(filtered)),
                    ?sidePanel,
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMainMapArea(List<MdoMapPosition> filtered) {
    if (_isPerCommessaView) {
      if (_commesseOptions.isEmpty && !_loading) {
        return const Center(
          child: Text('Nessuna commessa attiva in anagrafica.'),
        );
      }
      if ((_selectedCommessaId ?? '').trim().isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Seleziona una commessa per vedere tutte le risorse abbinatе.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
      if (_loadingLinked && _linkedAssets == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (filtered.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _linkedAssets == null || _linkedAssets!.totalCount == 0
                  ? 'Nessuna risorsa abbinata a questa commessa.'
                  : 'Nessuna coordinata GPS tra le risorse di questa commessa.\n'
                      'Consulta l\'elenco a destra.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    }

    return _buildMapStack(filtered);
  }

  Widget _buildPerCommessaListPanel() {
    if ((_selectedCommessaId ?? '').trim().isEmpty) {
      return Material(
        elevation: 4,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Seleziona una commessa dall\'elenco in alto.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    if (_loadingLinked && _linkedAssets == null) {
      return Material(
        elevation: 4,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return _buildLinkedAssetsList(_linkedAssets);
  }

  Widget _buildMapStack(List<MdoMapPosition> filtered) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_canShowMap)
          IgnorePointer(
            ignoring: _blockMapPointer,
            child: _buildMapWidget(filtered),
          )
        else
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: _buildMissingApiKeyMessage(),
          ),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_canShowMap && filtered.isEmpty && !_isPerCommessaView)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Nessun punto con coordinate GPS per il filtro selezionato.\n'
                  'MDO: rileva GPS da MDO Ferroviari · Commesse: Gestione dati → Commesse.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        if (_selected != null)
          PointerInterceptor(
            intercepting: true,
            child: _buildDetailCard(_selected!),
          ),
      ],
    );
  }

  Widget _buildMapWidget(List<MdoMapPosition> filtered) {
    if (_useNativeGoogleMap) {
      return GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: _italyCenter,
          zoom: _italyZoom,
        ),
        markers: _markers,
        mapType: MapType.normal,
        myLocationButtonEnabled: false,
        myLocationEnabled: true,
        zoomControlsEnabled: !useMobileUi(context),
        onCameraMove: (pos) {
          _mapZoom = pos.zoom;
          final bucket = pos.zoom.round();
          if (bucket == _markerZoomBucket) return;
          _markerZoomBucket = bucket;
          _markerRebuildDebounce?.cancel();
          _markerRebuildDebounce = Timer(
            const Duration(milliseconds: 280),
            () {
              if (!mounted) return;
              unawaited(_rebuildMarkers());
            },
          );
        },
        onMapCreated: (c) {
          _nativeMapCtrl = c;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_applyUserCityFrame());
          });
        },
      );
    }

    if (_useEmbedMap) {
      return MdoGoogleMapEmbed(
        key: _embedMapKey,
        apiKey: GoogleMapsConfig.resolvedKey,
        positions: filtered,
        markerStyle: _markerStyle,
        onMarkerTap: _onMarkerTap,
      );
    }

    return const Center(
      child: Text('Mappa non disponibile su questa piattaforma.'),
    );
  }

  Widget _buildMissingApiKeyMessage() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.key_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chiave Google Maps mancante',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  kIsWeb
                      ? 'Web: chiave in web/index.html → '
                          'window.CRONOS_GOOGLE_MAPS_API_KEY\n\n'
                          'Abilita Maps JavaScript API in Google Cloud.'
                      : defaultTargetPlatform == TargetPlatform.android
                          ? 'Android: google.maps.api.key in '
                              'android/local.properties, poi rebuild.\n\n'
                              'Abilita Maps SDK for Android in Google Cloud.'
                          : defaultTargetPlatform == TargetPlatform.iOS
                              ? 'iOS: GMSApiKey in ios/Runner/Info.plist, '
                                  'poi rebuild.\n\n'
                                  'Abilita Maps SDK for iOS in Google Cloud.'
                              : 'Desktop: google.maps.api.key in '
                                  'android/local.properties oppure '
                                  '--dart-define=GOOGLE_MAPS_API_KEY=...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideList(List<MdoMapPosition> filtered, {bool fullWidth = false}) {
    return Material(
      elevation: 8,
      child: SizedBox(
        width: fullWidth ? double.infinity : 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'Elenco (${filtered.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Nessun punto con GPS'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final p = filtered[i];
                        final selected = _selected?.idUuid == p.idUuid &&
                            _selected?.kind == p.kind;
                        return ListTile(
                          selected: selected,
                          leading: CircleAvatar(
                            backgroundColor: _pointColor(p),
                            child: Text(
                              p.sigla.length > 4
                                  ? p.sigla.substring(0, 4)
                                  : p.sigla,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text('${p.kindLabel}: ${p.sigla}'),
                          subtitle: Text(
                            p.isCommessa
                                ? p.lastDetectedLabel
                                : '${p.descrizioneMezzo ?? ''}\n'
                                    '${p.lastDetectedLabel}',
                            maxLines: 3,
                          ),
                          isThreeLine: true,
                          onTap: () => _focusMezzo(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(int visibleCount) {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_MappaLayerFiltro>(
              segments: [
                const ButtonSegment(
                  value: _MappaLayerFiltro.tuttiMdo,
                  label: Text('Tutti MDO'),
                  icon: Icon(Icons.train, size: 18),
                ),
                const ButtonSegment(
                  value: _MappaLayerFiltro.tutteCommesse,
                  label: Text('Commesse'),
                  icon: Icon(Icons.business, size: 18),
                ),
                ButtonSegment(
                  value: _MappaLayerFiltro.box,
                  label: Text(
                    _boxPositions.isEmpty ? 'BOX' : 'BOX (${_boxPositions.length})',
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _MappaLayerFiltro.estintori,
                  label: Text(
                    _estintoriPositions.isEmpty
                        ? 'Estintori'
                        : 'Estintori (${_estintoriPositions.length})',
                  ),
                  icon: const Icon(Icons.fire_extinguisher_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _MappaLayerFiltro.casettePs,
                  label: Text(
                    _casettePsPositions.isEmpty
                        ? 'Cassette P.S.'
                        : 'Cassette P.S. (${_casettePsPositions.length})',
                  ),
                  icon: const Icon(Icons.medical_services_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _MappaLayerFiltro.strutture,
                  label: Text(
                    _strutturePositions.isEmpty
                        ? 'Strutture'
                        : 'Strutture (${_strutturePositions.length})',
                  ),
                  icon: const Icon(Icons.apartment_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _MappaLayerFiltro.officine,
                  label: Text(
                    _officinePositions.isEmpty
                        ? 'Officine'
                        : 'Officine (${_officinePositions.length})',
                  ),
                  icon: const Icon(Icons.garage_outlined, size: 18),
                ),
                const ButtonSegment(
                  value: _MappaLayerFiltro.perCommessa,
                  label: Text('Per commessa'),
                  icon: Icon(Icons.folder_open_outlined, size: 18),
                ),
              ],
              selected: {_layerFiltro},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() {
                  _layerFiltro = s.first;
                  _selected = null;
                  if (_isPerCommessaView) {
                    _searchCtrl.clear();
                    _search = '';
                  }
                });
                if (_isPerCommessaView) {
                  unawaited(_loadLinkedAssetsForSelected());
                } else {
                  unawaited(_rebuildMarkers());
                }
              },
            ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_isPerCommessaView) ...[
                  Expanded(child: _buildCommessaSelector()),
                ] else ...[
                  Expanded(
                    child: Autocomplete<MdoMapPosition>(
                    optionsBuilder: (text) {
                      final q = text.text.trim().toLowerCase();
                      final base = _layerFiltered;
                      if (q.isEmpty) return base;
                      return base.where(
                        (p) => p.sigla.toLowerCase().contains(q),
                      );
                    },
                    displayStringForOption: (p) =>
                        '${p.kindLabel}: ${p.sigla}',
                    onSelected: (p) => _focusMezzo(p),
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmitted) {
                      if (controller.text != _searchCtrl.text) {
                        controller.text = _searchCtrl.text;
                      }
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: _layerFiltro == _MappaLayerFiltro.officine
                              ? 'Cerca officina, città o marca…'
                              : 'Cerca sigla o commessa…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    _searchCtrl.clear();
                                  },
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (v) {
                          _searchCtrl.text = v;
                        },
                      );
                    },
                  ),
                ),
                ],
                const SizedBox(width: 12),
                Chip(
                  avatar: Icon(
                    switch (_layerFiltro) {
                      _MappaLayerFiltro.tutteCommesse => Icons.business,
                      _MappaLayerFiltro.box => Icons.inventory_2_outlined,
                      _MappaLayerFiltro.estintori =>
                        Icons.fire_extinguisher_outlined,
                      _MappaLayerFiltro.casettePs =>
                        Icons.medical_services_outlined,
                      _MappaLayerFiltro.strutture => Icons.apartment_outlined,
                      _MappaLayerFiltro.officine => Icons.garage_outlined,
                      _MappaLayerFiltro.perCommessa => Icons.folder_open_outlined,
                      _ => Icons.train,
                    },
                    size: 18,
                  ),
                  label: Text(
                    _isPerCommessaView
                        ? '${_linkedAssets?.totalCount ?? 0} risorse'
                        : '$visibleCount punti',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _isPerCommessaView
                  ? 'Seleziona una commessa per vedere MDO, BOX, estintori e altre risorse abbinatе.'
                  : 'Arancione = commessa · Blu = MDO tipo A · Marrone = BOX · '
                      'Rosso = estintore · Verde = cassetta P.S. · Viola = struttura · '
                      'Verde petrolio = officina',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Color _pointColor(MdoMapPosition p) {
    if (p.isCommessa) return Colors.orange.shade800;
    if (p.isBox) return const Color(0xFF6D4C41);
    if (p.isEstintore) return const Color(0xFFC62828);
    if (p.isCasettaPs) return const Color(0xFF2E7D32);
    if (p.isStruttura) return const Color(0xFF6A1B9A);
    if (p.isOfficina) return const Color(0xFF0F766E);
    return Colors.blue.shade800;
  }

  Widget _buildDetailCard(MdoMapPosition p) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _pointColor(p),
                        child: Text(
                          p.sigla,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${p.kindLabel}: ${p.descrizioneMezzo ?? p.sigla}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _selected = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (p.isStruttura && (p.tipologia ?? '').isNotEmpty)
                    Text(
                      'Tipologia: ${p.tipologia}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6A1B9A),
                          ),
                    ),
                  if (p.isOfficina && (p.tipologia ?? '').isNotEmpty)
                    Text(
                      p.tipologia!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F766E),
                          ),
                    ),
                  Text(p.lastDetectedLabel),
                  if (p.targaRfi != null) Text('Targa RFI: ${p.targaRfi}'),
                  if (p.cantiere != null) Text('Cantiere: ${p.cantiere}'),
                  if (p.commessa != null) Text('Commessa: ${p.commessa}'),
                  Text(
                    'Coordinate: ${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (p.isMdo)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInMdoLogistica(p),
                          icon: const Icon(Icons.train_outlined),
                          label: const Text('Vai a MDO Ferroviari'),
                        ),
                      if (p.isBox)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInBoxLogistica(p),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Vai a BOX logistica'),
                        ),
                      if (p.isEstintore)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInEstintori(p),
                          icon: const Icon(Icons.fire_extinguisher_outlined),
                          label: const Text('Vai a Estintori'),
                        ),
                      if (p.isCasettaPs)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInCasettePs(p),
                          icon: const Icon(Icons.medical_services_outlined),
                          label: const Text('Vai a Cassette P.S.'),
                        ),
                      if (p.isStruttura)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInStruttureAnagrafica(p),
                          icon: const Icon(Icons.apartment_outlined),
                          label: const Text('Vai ad anagrafica strutture'),
                        ),
                      if (p.isOfficina)
                        FilledButton.tonalIcon(
                          onPressed: () => _openInOfficine(p),
                          icon: const Icon(Icons.garage_outlined),
                          label: const Text('Vai a Officine convenzionate'),
                        ),
                      TextButton.icon(
                        onPressed: () => _openExternalMap(p),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Apri in Google Maps'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommessaSelector() {
    return DropdownSearch<String>(
      selectedItem: _selectedCommessaId,
      items: _commesseOptions.map((c) => c.idUuid).toList(growable: false),
      itemAsString: (id) {
        for (final c in _commesseOptions) {
          if (c.idUuid == id) return c.nome;
        }
        return id;
      },
      compareFn: (a, b) => a == b,
      dropdownDecoratorProps: const DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: 'Commessa (scrivi o seleziona)',
          prefixIcon: Icon(Icons.business_outlined),
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      popupProps: PopupProps.menu(
        showSearchBox: true,
        searchFieldProps: const TextFieldProps(
          decoration: InputDecoration(
            hintText: 'Cerca commessa…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        constraints: const BoxConstraints(maxHeight: 420),
      ),
      onChanged: (id) {
        setState(() => _selectedCommessaId = id);
        unawaited(_loadLinkedAssetsForSelected());
      },
    );
  }

  Widget _buildLinkedAssetsList(CommessaLinkedAssets? assets) {
    if (assets == null) {
      return const Center(child: Text('Caricamento…'));
    }
    if (assets.totalCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nessun MDO, BOX, estintore o altra risorsa abbinata a «${assets.commessaNome}».',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Material(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assets.commessaNome,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (assets.mdo.isNotEmpty)
                      Chip(label: Text('MDO ${assets.mdo.length}')),
                    if (assets.box.isNotEmpty)
                      Chip(label: Text('BOX ${assets.box.length}')),
                    if (assets.estintori.isNotEmpty)
                      Chip(label: Text('Estintori ${assets.estintori.length}')),
                    if (assets.attrezzature.isNotEmpty)
                      Chip(label: Text('Attrezz. ${assets.attrezzature.length}')),
                    if (assets.casettePs.isNotEmpty)
                      Chip(label: Text('Cassette PS ${assets.casettePs.length}')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (assets.mdo.isNotEmpty)
                  _buildLinkedSection(
                    title: 'MDO ferroviari',
                    icon: Icons.train,
                    color: Colors.blue.shade800,
                    items: assets.mdo,
                  ),
                if (assets.box.isNotEmpty)
                  _buildLinkedSection(
                    title: 'BOX',
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF6D4C41),
                    items: assets.box,
                  ),
                if (assets.estintori.isNotEmpty)
                  _buildLinkedSection(
                    title: 'Estintori',
                    icon: Icons.local_fire_department_outlined,
                    color: Colors.red.shade700,
                    items: assets.estintori,
                  ),
                if (assets.attrezzature.isNotEmpty)
                  _buildLinkedSection(
                    title: 'Attrezzature',
                    icon: Icons.build_outlined,
                    color: Colors.blueGrey.shade700,
                    items: assets.attrezzature,
                  ),
                if (assets.casettePs.isNotEmpty)
                  _buildLinkedSection(
                    title: 'Cassette PS',
                    icon: Icons.medical_services_outlined,
                    color: Colors.teal.shade700,
                    items: assets.casettePs,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<CommessaLinkedItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                '$title (${items.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        ...items.map(
          (item) => ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            title: Text(item.label),
            subtitle: Text(
              [
                if ((item.subtitle ?? '').trim().isNotEmpty) item.subtitle!,
                if (item.hasGps) 'GPS: ${item.lat!.toStringAsFixed(5)}, ${item.lon!.toStringAsFixed(5)}',
              ].join('\n'),
              maxLines: 3,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLinkedItem(item),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
