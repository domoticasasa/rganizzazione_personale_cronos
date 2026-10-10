import 'dart:convert';

import '../models/mdo_map_marker_style.dart';
import '../services/logistica_mdo_map_service.dart';
import 'mdo_map_marker_icon.dart';

/// HTML condiviso per Google Maps JavaScript API (desktop WebView).
String mdoGoogleMapHtml(String apiKey) {
  final safeKey = apiKey.replaceAll("'", '').replaceAll('"', '');
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body, #map { height: 100%; width: 100%; margin: 0; padding: 0; }
    .cronos-map-marker {
      position: absolute;
      transform-origin: 50% 100%;
      font-size: 13px;
      /* punta (100%) ancorata al GPS; rotate sposta solo l'etichetta */
      cursor: pointer;
      display: flex;
      flex-direction: column;
      align-items: center;
      pointer-events: auto;
      user-select: none;
    }
    .cronos-map-marker__label {
      display: block;
      font-family: 'Segoe UI', Roboto, Arial, sans-serif;
      font-weight: 800;
      color: #fff;
      white-space: nowrap;
      border-radius: 10px;
      border: 2px solid #fff;
      box-shadow: 0 2px 10px rgba(0,0,0,0.38);
      letter-spacing: 0.04em;
      line-height: 1.15;
    }
    .cronos-map-marker__icon-bubble {
      width: 2.2em;
      height: 2.2em;
      border-radius: 50%;
      border: 2px solid #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 1.15em;
      box-shadow: 0 2px 8px rgba(0,0,0,0.35);
      margin-bottom: 2px;
    }
    .cronos-map-marker--icon-stack {
      gap: 0;
    }
    .cronos-map-marker--icon-stack .cronos-map-marker__label {
      font-size: 11px;
      padding: 4px 8px;
    }
    .cronos-map-marker__pin {
      width: 0;
      height: 0;
      margin-top: -1px;
      border-left: 9px solid transparent;
      border-right: 9px solid transparent;
    }
    .cronos-map-marker--commessa .cronos-map-marker__pin {
      border-top: 12px solid #E65100;
    }
    .cronos-map-marker--mdo .cronos-map-marker__pin {
      border-top: 10px solid #1565C0;
    }
    .cronos-map-marker--estintore .cronos-map-marker__label,
    .cronos-map-marker--casetta_ps .cronos-map-marker__label {
      font-size: 11px;
      padding: 4px 7px;
    }
    .cronos-map-marker--shape-pill .cronos-map-marker__label {
      border-radius: 999px;
    }
    .cronos-map-marker--shape-square .cronos-map-marker__label,
    .cronos-map-marker--shape-tag .cronos-map-marker__label {
      border-radius: 6px;
    }
    .cronos-map-marker--shape-roundedRect .cronos-map-marker__label,
    .cronos-map-marker--shape-notch .cronos-map-marker__label {
      border-radius: 14px;
    }
    .cronos-map-marker--shape-banner .cronos-map-marker__label {
      border-radius: 6px;
      padding: 6px 14px;
    }
    .cronos-map-marker--shape-circle .cronos-map-marker__label {
      border-radius: 50%;
      min-width: 2.8em;
      min-height: 2.8em;
      display: flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 10px;
    }
    .cronos-map-marker--shape-pill .cronos-map-marker__pin,
    .cronos-map-marker--shape-circle .cronos-map-marker__pin,
    .cronos-map-marker--shape-square .cronos-map-marker__pin,
    .cronos-map-marker--shape-roundedRect .cronos-map-marker__pin,
    .cronos-map-marker--shape-diamond .cronos-map-marker__pin,
    .cronos-map-marker--shape-hexagon .cronos-map-marker__pin,
    .cronos-map-marker--shape-shield .cronos-map-marker__pin,
    .cronos-map-marker--shape-teardrop .cronos-map-marker__pin,
    .cronos-map-marker--shape-star .cronos-map-marker__pin,
    .cronos-map-marker--shape-triangle .cronos-map-marker__pin,
    .cronos-map-marker--shape-octagon .cronos-map-marker__pin,
    .cronos-map-marker--shape-tag .cronos-map-marker__pin,
    .cronos-map-marker--shape-banner .cronos-map-marker__pin,
    .cronos-map-marker--shape-arch .cronos-map-marker__pin,
    .cronos-map-marker--shape-cross .cronos-map-marker__pin,
    .cronos-map-marker--shape-pentagon .cronos-map-marker__pin,
    .cronos-map-marker--shape-parallelogram .cronos-map-marker__pin,
    .cronos-map-marker--shape-notch .cronos-map-marker__pin,
    .cronos-map-marker--shape-mapPin .cronos-map-marker__pin,
    .cronos-map-marker--shape-bubble .cronos-map-marker__pin {
      display: none;
    }
    .cronos-map-marker--shape-iconStack .cronos-map-marker__pin {
      display: block;
      border-top-width: 8px;
    }
    .cronos-map-marker--shape-diamond .cronos-map-marker__label {
      clip-path: polygon(50% 0%, 92% 50%, 50% 100%, 8% 50%);
      border-radius: 0;
      padding: 10px 14px;
    }
    .cronos-map-marker--shape-hexagon .cronos-map-marker__label {
      clip-path: polygon(25% 0%, 75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%);
      border-radius: 0;
    }
    .cronos-map-marker--shape-octagon .cronos-map-marker__label {
      clip-path: polygon(30% 0%, 70% 0%, 100% 30%, 100% 70%, 70% 100%, 30% 100%, 0% 70%, 0% 30%);
      border-radius: 0;
    }
    .cronos-map-marker--shape-pentagon .cronos-map-marker__label {
      clip-path: polygon(50% 0%, 100% 38%, 82% 100%, 18% 100%, 0% 38%);
      border-radius: 0;
    }
    .cronos-map-marker--shape-triangle .cronos-map-marker__label {
      clip-path: polygon(50% 0%, 100% 100%, 0% 100%);
      border-radius: 0;
      padding: 12px 10px 8px;
    }
    .cronos-map-marker--shape-star .cronos-map-marker__label {
      clip-path: polygon(50% 0%, 61% 35%, 98% 35%, 68% 57%, 79% 91%, 50% 70%, 21% 91%, 32% 57%, 2% 35%, 39% 35%);
      border-radius: 0;
      min-width: 2.6em;
      min-height: 2.6em;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .cronos-map-marker--shape-shield .cronos-map-marker__label {
      border-radius: 8px 8px 14px 14px;
      padding-top: 10px;
    }
    .cronos-map-marker--shape-teardrop .cronos-map-marker__label {
      border-radius: 50% 50% 45% 45%;
      padding: 10px 12px 14px;
    }
    .cronos-map-marker--shape-arch .cronos-map-marker__label {
      border-radius: 50% 50% 8px 8px;
      padding: 12px 10px 8px;
    }
    .cronos-map-marker--shape-cross .cronos-map-marker__label {
      border-radius: 4px;
      min-width: 2.4em;
      min-height: 2.4em;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .cronos-map-marker--shape-parallelogram .cronos-map-marker__label {
      clip-path: polygon(18% 0%, 100% 0%, 82% 100%, 0% 100%);
      border-radius: 0;
    }
    .cronos-map-marker--shape-mapPin .cronos-map-marker__label {
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      min-width: 2.4em;
      min-height: 2.4em;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 8px;
    }
    .cronos-map-marker--shape-mapPin .cronos-map-marker__label span {
      transform: rotate(45deg);
      display: inline-block;
    }
    .cronos-map-marker--shape-bubble .cronos-map-marker__label {
      border-radius: 12px;
      position: relative;
      padding-bottom: 12px;
    }
    .cronos-map-marker--shape-bubble .cronos-map-marker__label::after {
      content: '';
      position: absolute;
      left: 50%;
      bottom: -6px;
      transform: translateX(-50%);
      border-left: 7px solid transparent;
      border-right: 7px solid transparent;
      border-top: 8px solid currentColor;
      filter: drop-shadow(0 1px 1px rgba(0,0,0,0.2));
    }
    .cronos-map-marker--shape-pin .cronos-map-marker__pin {
      border-left-width: 11px;
      border-right-width: 11px;
    }
    .cronos-map-marker--commessa.cronos-map-marker--shape-pin .cronos-map-marker__pin {
      border-top-width: 18px;
    }
    .cronos-map-marker--mdo.cronos-map-marker--shape-pin .cronos-map-marker__pin {
      border-top-width: 14px;
    }
    .cronos-map-marker--shape-estintore .cronos-map-marker__pin,
    .cronos-map-marker--shape-casettaPs .cronos-map-marker__pin {
      display: none;
    }
    .cronos-map-marker__estintore {
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .cronos-map-marker__estintore-handle {
      width: 1.15em;
      height: 0.55em;
      border: 2px solid var(--mk-color);
      border-bottom: none;
      border-radius: 0.55em 0.55em 0 0;
      margin-bottom: -2px;
      background: var(--mk-color);
    }
    .cronos-map-marker__estintore-body {
      width: 1.45em;
      height: 2.1em;
      background: var(--mk-color);
      border: 2px solid #fff;
      border-radius: 0.28em;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 2px 8px rgba(0,0,0,0.35);
    }
    .cronos-map-marker__estintore-body span {
      color: #fff;
      font-size: 0.55em;
      font-weight: 800;
    }
    .cronos-map-marker__estintore-nozzle {
      width: 0;
      height: 0;
      border-left: 0.35em solid transparent;
      border-right: 0.35em solid transparent;
      border-top: 0.45em solid var(--mk-color);
    }
    .cronos-map-marker__estintore-tip {
      width: 0;
      height: 0;
      border-left: 0.55em solid transparent;
      border-right: 0.55em solid transparent;
      border-top: 0.65em solid var(--mk-color);
    }
    .cronos-map-marker__casetta {
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .cronos-map-marker__casetta-box {
      width: 2.4em;
      height: 1.85em;
      background: #fff;
      border: 3px solid var(--mk-color);
      border-radius: 0.18em;
      position: relative;
      box-shadow: 0 2px 8px rgba(0,0,0,0.35);
    }
    .cronos-map-marker__casetta-cross-v,
    .cronos-map-marker__casetta-cross-h {
      position: absolute;
      background: var(--mk-color);
      border-radius: 1px;
    }
    .cronos-map-marker__casetta-cross-v {
      width: 0.28em;
      height: 1.05em;
      left: 50%;
      top: 50%;
      transform: translate(-50%, -50%);
    }
    .cronos-map-marker__casetta-cross-h {
      width: 1.05em;
      height: 0.28em;
      left: 50%;
      top: 50%;
      transform: translate(-50%, -50%);
    }
    .cronos-map-marker__casetta-label {
      margin-top: 0.18em;
      padding: 0.12em 0.35em;
      background: var(--mk-color);
      color: #fff;
      font-size: 0.55em;
      font-weight: 800;
      border-radius: 0.28em;
      border: 2px solid #fff;
      white-space: nowrap;
    }
    .cronos-map-marker__casetta-tip {
      width: 0;
      height: 0;
      margin-top: 0.12em;
      border-left: 0.55em solid transparent;
      border-right: 0.55em solid transparent;
      border-top: 0.65em solid var(--mk-color);
    }
  </style>
  <script>
    function gmError() {
      document.body.innerHTML = '<div style="padding:16px;font-family:sans-serif">'
        + 'Errore caricamento Google Maps. Verifica la chiave API e Maps JavaScript API.</div>';
    }
  </script>
  <script async defer
    src="https://maps.googleapis.com/maps/api/js?key=$safeKey&callback=initMap"
    onerror="gmError()"></script>
</head>
<body>
  <div id="map"></div>
  <script>
    let map;
    let markerObjs = [];
    let userMarker = null;
    let userCircle = null;
    let redrawScheduled = false;
    let centerWheelZoomInstalled = false;
    let CronosMapMarker = null;
    let markerStyle = {
      mapSizeScale: 1.0,
      commessa: { shape: 'pill', colorArgb: 4294947584, icon: 'none', sizeScale: 1.05 },
      mdo: { shape: 'pill', colorArgb: 4283215296, icon: 'none', sizeScale: 1.0 },
      box: { shape: 'iconStack', colorArgb: 4286540851, icon: 'container', sizeScale: 1.0 },
      estintore: { shape: 'estintore', colorArgb: 4290772992, icon: 'none', sizeScale: 1.0 },
      casetta_ps: { shape: 'casettaPs', colorArgb: 4283216690, icon: 'none', sizeScale: 1.0 },
      struttura: { shape: 'pill', colorArgb: 4286422410, icon: 'business', sizeScale: 1.0 },
      officina: { shape: 'pill', colorArgb: 4279203438, icon: 'garage', sizeScale: 1.0 }
    };
    const MARKER_SHAPES = [
      'badge','pill','circle','square','iconStack','pin','roundedRect','diamond',
      'hexagon','shield','teardrop','star','triangle','octagon','bubble','tag',
      'banner','mapPin','arch','cross','pentagon','parallelogram','notch',
      'estintore','casettaPs'
    ];
    const MARKER_ICON_CHAR = {
      train: '🚆', container: '📦', business: '🏢', place: '📍',
      warehouse: '🏭', garage: '🔧', none: ''
    };

    function escapeHtml(s) {
      return String(s || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    function userMarkerSizeScale() {
      const s = markerStyle && (markerStyle.mapSizeScale != null ? markerStyle.mapSizeScale : markerStyle.sizeScale);
      if (typeof s !== 'number' || isNaN(s)) return 1.0;
      return Math.max(0.35, Math.min(3.0, s));
    }

    function argbToCss(argb, opacityMul) {
      if (argb == null) return null;
      const n = Number(argb) >>> 0;
      let a = ((n >>> 24) & 255) / 255;
      if (typeof opacityMul === 'number') a = a * opacityMul;
      const r = (n >>> 16) & 255;
      const g = (n >>> 8) & 255;
      const b = n & 255;
      return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
    }

    function mergeKindStyle(prev, next) {
      if (!next || typeof next !== 'object') return prev || {};
      prev = prev || {};
      return {
        shape: next.shape || prev.shape,
        colorArgb: next.colorArgb != null ? next.colorArgb : prev.colorArgb,
        icon: next.icon || prev.icon,
        sizeScale: typeof next.sizeScale === 'number' ? next.sizeScale : prev.sizeScale
      };
    }

    function markerKindFromData(d) {
      var k = (d && (d.markerKind || d.kind || d.assetType || '')).toString().trim();
      if (k === 'casetta_ps' || k === 'casettaPs') return 'casetta_ps';
      if (k === 'struttura') return 'struttura';
      if (k === 'officina') return 'officina';
      if (k === 'estintore') return 'estintore';
      if (k === 'box') return 'box';
      if (k === 'commessa') return 'commessa';
      if (k === 'mdo') return 'mdo';
      var sn = (d && (d.snippet || d.title || '')).toString().toLowerCase();
      if (sn.indexOf('estintore') >= 0) return 'estintore';
      if (sn.indexOf('casetta') >= 0) return 'casetta_ps';
      if (sn.indexOf('struttura') >= 0) return 'struttura';
      if (sn.indexOf('officina') >= 0) return 'officina';
      return 'mdo';
    }

    function resolveKindStyle(kind) {
      const cssKind = markerCssKind(kind);
      const block = (markerStyle && markerStyle[cssKind]) || {};
      const defaults = {
        commessa: 4294947584, mdo: 4283215296, box: 4286540851,
        estintore: 4290772992, casetta_ps: 4283216690, struttura: 4286422410,
        officina: 4279203438
      };
      let shape = (block.shape || 'badge').toString();
      if (MARKER_SHAPES.indexOf(shape) < 0) shape = 'badge';
      const color = argbToCss(block.colorArgb != null ? block.colorArgb : defaults[cssKind])
        || '#1565C0';
      const icon = block.icon || 'none';
      const kindScale = typeof block.sizeScale === 'number' ? block.sizeScale : 1.0;
      return { shape: shape, color: color, icon: icon, kindScale: kindScale };
    }

    function markerScaleForZoom(zoom, kind) {
      var base = 0.76;
      if (kind === 'commessa') base = 1.32;
      else if (kind === 'box') base = 0.82;
      else if (kind === 'estintore' || kind === 'casetta_ps' || kind === 'struttura' || kind === 'officina') base = 0.68;
      const ks = resolveKindStyle(kind).kindScale;
      const size = Math.pow(1.10, zoom - 11) * base * userMarkerSizeScale() * ks;
      return Math.max(0.18, Math.min(2.15, size));
    }

    function markerCssKind(kind) {
      if (kind === 'commessa') return 'commessa';
      if (kind === 'box') return 'box';
      if (kind === 'estintore') return 'estintore';
      if (kind === 'casetta_ps') return 'casetta_ps';
      if (kind === 'struttura') return 'struttura';
      if (kind === 'officina') return 'officina';
      return 'mdo';
    }

    function setMarkerStyle(style) {
      if (!style) return;
      markerStyle = {
        mapSizeScale: style.mapSizeScale != null ? style.mapSizeScale
          : (style.sizeScale != null ? style.sizeScale : markerStyle.mapSizeScale),
        commessa: mergeKindStyle(markerStyle.commessa, style.commessa),
        mdo: mergeKindStyle(markerStyle.mdo, style.mdo),
        box: mergeKindStyle(markerStyle.box, style.box),
        estintore: mergeKindStyle(markerStyle.estintore, style.estintore),
        casetta_ps: mergeKindStyle(markerStyle.casetta_ps, style.casetta_ps),
        struttura: mergeKindStyle(markerStyle.struttura, style.struttura),
        officina: mergeKindStyle(markerStyle.officina, style.officina)
      };
      for (let k = 0; k < markerObjs.length; k++) {
        if (markerObjs[k].refreshAppearance) markerObjs[k].refreshAppearance();
      }
      scheduleMarkerRedraw();
    }

    function scheduleSpiderRelayout() {
      requestAnimationFrame(function() {
        relayoutSpiderGroups();
      });
    }

    function scheduleMarkerRedraw() {
      if (redrawScheduled) return;
      redrawScheduled = true;
      requestAnimationFrame(function() {
        redrawScheduled = false;
        for (let k = 0; k < markerObjs.length; k++) {
          markerObjs[k].draw();
        }
      });
    }

    function latLngKeyFromData(d) {
      return Number(d.lat).toFixed(5) + '|' + Number(d.lon).toFixed(5);
    }

    function haversineMeters(lat1, lon1, lat2, lon2) {
      const R = 6371000;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
      return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function spiderFind(parent, x) {
      while (parent[x] !== x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    function spiderUnite(parent, a, b) {
      const ra = spiderFind(parent, a);
      const rb = spiderFind(parent, b);
      if (ra !== rb) parent[rb] = ra;
    }

    function groupMarkerObjsByLocation() {
      const n = markerObjs.length;
      const parent = [];
      for (let i = 0; i < n; i++) parent[i] = i;
      for (let i = 0; i < n; i++) {
        for (let j = i + 1; j < n; j++) {
          const di = markerObjs[i].data;
          const dj = markerObjs[j].data;
          if (latLngKeyFromData(di) === latLngKeyFromData(dj) ||
              haversineMeters(di.lat, di.lon, dj.lat, dj.lon) <= 12) {
            spiderUnite(parent, i, j);
          }
        }
      }
      const map = {};
      for (let i = 0; i < n; i++) {
        const r = spiderFind(parent, i);
        if (!map[r]) map[r] = [];
        map[r].push(markerObjs[i]);
      }
      return Object.keys(map).map(function(k) { return map[k]; });
    }

    function layoutSpiderCluster(markers) {
      const n = markers.length;
      if (n <= 1) {
        markers[0].screenRotateDeg = 0;
        markers[0].spiderCenterLatLng = null;
        return;
      }
      markers.sort(function(a, b) {
        const rank = function(k) {
          if (k === 'commessa') return 0;
          if (k === 'mdo') return 1;
          if (k === 'box') return 2;
          if (k === 'estintore') return 3;
          if (k === 'casetta_ps') return 4;
          if (k === 'officina') return 5;
          return 6;
        };
        const ca = rank(markerKindFromData(a.data));
        const cb = rank(markerKindFromData(b.data));
        if (ca !== cb) return ca - cb;
        return String(a.data.sigla || '').localeCompare(String(b.data.sigla || ''));
      });
      let cLat = 0;
      let cLon = 0;
      for (let i = 0; i < n; i++) {
        cLat += Number(markers[i].data.lat);
        cLon += Number(markers[i].data.lon);
      }
      cLat /= n;
      cLon /= n;
      const center = new google.maps.LatLng(cLat, cLon);
      for (let i = 0; i < n; i++) {
        markers[i].screenRotateDeg = -90 + (360 * i / n);
        markers[i].spiderCenterLatLng = center;
      }
    }

    function relayoutSpiderGroups() {
      if (!map || !markerObjs.length) return;
      const groups = groupMarkerObjsByLocation();
      for (let g = 0; g < groups.length; g++) {
        layoutSpiderCluster(groups[g]);
      }
      scheduleMarkerRedraw();
    }

    /// Zoom con rotella sul centro mappa (evita deriva verso il mouse/iframe).
    function initCenterWheelZoom(m) {
      if (centerWheelZoomInstalled) return;
      centerWheelZoomInstalled = true;
      const div = m.getDiv();
      div.addEventListener('wheel', function(e) {
        e.preventDefault();
        e.stopPropagation();
        const zoom = m.getZoom();
        const delta = e.deltaY > 0 ? -1 : 1;
        const newZoom = Math.max(0, Math.min(21, zoom + delta));
        if (newZoom !== zoom) {
          m.setZoom(newZoom);
        }
      }, { passive: false });
    }

    function initCronosMapMarkerClass() {
      function MarkerOverlay(latLng, data) {
        this.latLng = latLng;
        this.data = data;
        this.div = null;
        this.infoWindow = null;
        this.screenRotateDeg = 0;
        this.spiderCenterLatLng = null;
      }
      MarkerOverlay.prototype = new google.maps.OverlayView();
      MarkerOverlay.prototype.refreshAppearance = function() {
        if (!this.div) return;
        const d = this.data;
        const mk = markerKindFromData(d);
        const st = resolveKindStyle(mk);
        const cssKind = markerCssKind(mk);
        const shape = st.shape;
        this.div.className = 'cronos-map-marker cronos-map-marker--' + cssKind +
          ' cronos-map-marker--shape-' + shape;
        this.div.innerHTML = '';
        this.div.style.removeProperty('--mk-color');
        if (shape === 'estintore') {
          const wrap = document.createElement('div');
          wrap.className = 'cronos-map-marker__estintore';
          wrap.style.setProperty('--mk-color', st.color);
          const handle = document.createElement('div');
          handle.className = 'cronos-map-marker__estintore-handle';
          wrap.appendChild(handle);
          const body = document.createElement('div');
          body.className = 'cronos-map-marker__estintore-body';
          const span = document.createElement('span');
          span.textContent = d.label || d.sigla || '?';
          body.appendChild(span);
          wrap.appendChild(body);
          const nozzle = document.createElement('div');
          nozzle.className = 'cronos-map-marker__estintore-nozzle';
          wrap.appendChild(nozzle);
          const tip = document.createElement('div');
          tip.className = 'cronos-map-marker__estintore-tip';
          wrap.appendChild(tip);
          this.div.appendChild(wrap);
          return;
        }
        if (shape === 'casettaPs') {
          const wrap = document.createElement('div');
          wrap.className = 'cronos-map-marker__casetta';
          wrap.style.setProperty('--mk-color', st.color);
          const box = document.createElement('div');
          box.className = 'cronos-map-marker__casetta-box';
          const cv = document.createElement('div');
          cv.className = 'cronos-map-marker__casetta-cross-v';
          const ch = document.createElement('div');
          ch.className = 'cronos-map-marker__casetta-cross-h';
          box.appendChild(cv);
          box.appendChild(ch);
          wrap.appendChild(box);
          const lbl = document.createElement('div');
          lbl.className = 'cronos-map-marker__casetta-label';
          lbl.textContent = d.label || d.sigla || '?';
          wrap.appendChild(lbl);
          const tip = document.createElement('div');
          tip.className = 'cronos-map-marker__casetta-tip';
          wrap.appendChild(tip);
          this.div.appendChild(wrap);
          return;
        }
        if (shape === 'iconStack') {
          const bubble = document.createElement('div');
          bubble.className = 'cronos-map-marker__icon-bubble';
          bubble.style.background = st.color;
          bubble.textContent = MARKER_ICON_CHAR[st.icon] || MARKER_ICON_CHAR.container;
          this.div.appendChild(bubble);
        }
        const label = document.createElement('span');
        label.className = 'cronos-map-marker__label';
        label.textContent = d.label || d.sigla || '?';
        label.style.background = st.color;
        if (st.icon !== 'none' && shape !== 'iconStack') {
          const ic = document.createElement('span');
          ic.textContent = (MARKER_ICON_CHAR[st.icon] || '') + ' ';
          label.prepend(ic);
        }
        this.div.appendChild(label);
        const pin = document.createElement('div');
        pin.className = 'cronos-map-marker__pin';
        pin.style.borderTopColor = st.color;
        const showPin = shape === 'badge' || shape === 'pin' || shape === 'iconStack';
        pin.style.display = showPin ? 'block' : 'none';
        this.div.appendChild(pin);
      };

      MarkerOverlay.prototype.onAdd = function() {
        const d = this.data;
        this.div = document.createElement('div');
        this.refreshAppearance();
        const self = this;
        this.div.addEventListener('click', function(e) {
          e.stopPropagation();
          if (self.infoWindow) {
            self.infoWindow.open({ map: self.getMap(), shouldFocus: false });
            self.infoWindow.setPosition(self.latLng);
          }
          notifyDart({ type: 'marker', id: d.id });
        });
        this.infoWindow = new google.maps.InfoWindow({
          content: '<b>' + escapeHtml(d.sigla) + '</b><br>' + escapeHtml(d.snippet || ''),
        });
        const panes = this.getPanes();
        if (panes && panes.overlayMouseTarget) {
          panes.overlayMouseTarget.appendChild(this.div);
        }
      };
      MarkerOverlay.prototype.draw = function() {
        const projection = this.getProjection();
        if (!projection || !this.div) return;
        const pos = projection.fromLatLngToDivPixel(this.latLng);
        if (!pos) return;
        const zoom = this.getMap().getZoom();
        const scale = markerScaleForZoom(zoom, markerKindFromData(this.data));
        let px = pos.x;
        let py = pos.y;
        if (this.spiderCenterLatLng) {
          const anchor = projection.fromLatLngToDivPixel(this.spiderCenterLatLng);
          if (anchor) {
            px = anchor.x;
            py = anchor.y;
          }
        }
        const rot = this.screenRotateDeg || 0;
        this.div.style.left = px + 'px';
        this.div.style.top = py + 'px';
        this.div.style.transformOrigin = '50% 100%';
        this.div.style.transform =
          'translate(-50%, -100%) rotate(' + rot + 'deg) scale(' + scale + ')';
      };
      MarkerOverlay.prototype.onRemove = function() {
        if (this.div && this.div.parentNode) {
          this.div.parentNode.removeChild(this.div);
        }
        this.div = null;
        if (this.infoWindow) this.infoWindow.close();
      };
      CronosMapMarker = MarkerOverlay;
    }

    function notifyDart(payload) {
      var s = JSON.stringify(payload);
      try {
        if (window.parent && window.parent !== window) {
          window.parent.postMessage(s, '*');
        }
      } catch (e) {}
      try {
        if (window.chrome && window.chrome.webview) {
          window.chrome.webview.postMessage(s);
        } else if (window.CronosMap) {
          window.CronosMap.postMessage(s);
        }
      } catch (e) {}
      try {
        window.location.href = 'cronosmap://' + encodeURIComponent(s);
      } catch (e2) {}
    }

    window.addEventListener('message', function(ev) {
      try {
        var msg = JSON.parse(ev.data);
        if (!msg || !msg.type) return;
        if (msg.type === 'updateMarkers') updateMarkersPayload(msg);
        if (msg.type === 'setMarkerStyle') setMarkerStyle(msg.style);
        if (msg.type === 'fitItaly') fitItaly();
        if (msg.type === 'fitAllMarkers') fitAllMarkers();
        if (msg.type === 'focusMarker') focusMarker(msg.lat, msg.lon, msg.zoom || 11);
        if (msg.type === 'setUserLocation') setUserLocation(msg.lat, msg.lon, msg.zoom || 12, msg.accuracy);
      } catch (e) {}
    });

    function initMap() {
      initCronosMapMarkerClass();
      map = new google.maps.Map(document.getElementById('map'), {
        center: { lat: 42.5, lng: 12.5 },
        zoom: 6,
        mapTypeControl: true,
        streetViewControl: false,
        fullscreenControl: true,
        zoomControl: true,
        gestureHandling: 'greedy',
        scrollwheel: false,
      });
      initCenterWheelZoom(map);
      map.addListener('zoom_changed', scheduleMarkerRedraw);
      notifyDart({ type: 'ready' });
    }

    function clearMarkers() {
      markerObjs.forEach(function(m) { m.setMap(null); });
      markerObjs = [];
    }

    function updateMarkersPayload(msg) {
      if (msg && msg.style) setMarkerStyle(msg.style);
      const list = (msg && msg.markers) ? msg.markers : (Array.isArray(msg) ? msg : (msg && msg.data));
      updateMarkers(list);
    }

    function updateMarkers(list) {
      if (!map || !CronosMapMarker) return;
      clearMarkers();
      if (!list || !list.length) return;
      list.forEach(function(d) {
        const latLng = new google.maps.LatLng(d.lat, d.lon);
        const overlay = new CronosMapMarker(latLng, d);
        overlay.setMap(map);
        markerObjs.push(overlay);
      });
      scheduleSpiderRelayout();
    }

    function fitItaly() {
      if (!map) return;
      map.setCenter({ lat: 42.5, lng: 12.5 });
      map.setZoom(6);
    }

    function fitAllMarkers() {
      if (!map || !markerObjs.length) { fitItaly(); return; }
      const bounds = new google.maps.LatLngBounds();
      markerObjs.forEach(function(m) { bounds.extend(m.latLng); });
      map.fitBounds(bounds, 48);
    }

    function focusMarker(lat, lon, zoom) {
      if (!map) return;
      map.setCenter({ lat: lat, lng: lon });
      map.setZoom(zoom || 11);
    }

    function setUserLocation(lat, lon, zoom, accuracy) {
      if (!map || lat == null || lon == null) return;
      const pos = { lat: lat, lng: lon };
      const acc = (typeof accuracy === 'number' && accuracy > 0)
        ? Math.max(35, Math.min(accuracy, 30000))
        : 80;
      if (!userMarker) {
        userMarker = new google.maps.Marker({
          map: map,
          position: pos,
          title: 'La tua posizione',
          zIndex: 999999,
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 8,
            fillColor: '#1565C0',
            fillOpacity: 1,
            strokeColor: '#ffffff',
            strokeWeight: 2,
          },
        });
        userCircle = new google.maps.Circle({
          map: map,
          center: pos,
          radius: acc,
          fillColor: '#1565C0',
          fillOpacity: 0.12,
          strokeColor: '#1565C0',
          strokeOpacity: 0.45,
          strokeWeight: 1,
          clickable: false,
        });
      } else {
        userMarker.setPosition(pos);
        if (userCircle) {
          userCircle.setCenter(pos);
          userCircle.setRadius(acc);
        }
      }
      map.panTo(pos);
      map.setZoom(zoom || 12);
    }
  </script>
</body>
</html>
''';
}

List<Map<String, dynamic>> mdoMarkersList(List<MdoMapPosition> positions) =>
    positions
        .map(
          (p) => <String, dynamic>{
            'id': p.idUuid,
            'sigla': p.sigla,
            'label': p.isCommessa
                ? commessaMapDisplayLabel(p.sigla)
                : p.sigla.trim().toUpperCase(),
            'lat': p.lat,
            'lon': p.lon,
            'kind': p.mapMarkerKind,
            'markerKind': p.mapMarkerKind,
            'assetType': p.mapMarkerKind,
            'snippet': '${p.kindLabel} · ${p.coordsLabel}',
            'title': switch (p.kind) {
              MapPointKind.commessa => 'Commessa ${p.sigla}',
              MapPointKind.box => 'BOX ${p.sigla}',
              MapPointKind.estintore => 'Estintore ${p.sigla}',
              MapPointKind.casettaPs => 'Cassetta P.S. ${p.sigla}',
              MapPointKind.struttura => 'Struttura ${p.sigla}',
              MapPointKind.officina => 'Officina ${p.sigla}',
              MapPointKind.mdo => p.descrizioneMezzo ?? p.sigla,
            },
          },
        )
        .toList();

String mdoMarkersJson(List<MdoMapPosition> positions) =>
    jsonEncode(mdoMarkersList(positions));

/// Payload per `updateMarkersPayload` (marker + stile utente).
String mdoMapMarkersPayloadJson(
  List<MdoMapPosition> positions,
  MdoMapMarkerStyle style,
) =>
    jsonEncode(<String, dynamic>{
      'markers': mdoMarkersList(positions),
      'style': style.toJson(),
    });

String mdoMapUpdateMarkersJs(
  List<MdoMapPosition> positions,
  MdoMapMarkerStyle style,
) =>
    'updateMarkersPayload(${mdoMapMarkersPayloadJson(positions, style)});';

String mdoMapSetMarkerStyleJs(MdoMapMarkerStyle style) =>
    'setMarkerStyle(${jsonEncode(style.toJson())});';
