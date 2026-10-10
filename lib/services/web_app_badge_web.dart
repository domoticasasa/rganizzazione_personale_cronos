import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'app_branding_service.dart';

/// Badge chat su web — ottimizzato per **Chrome Android PWA installata**:
/// - Badging API dalla pagina + dal Service Worker (più affidabile in background)
/// - Ripristino a resume/visibility
/// - Favicon + titolo scheda (utile in tab browser / PC)
abstract final class WebAppBadge {
  WebAppBadge._();

  static String? _baseTitle;
  static String? _baseFaviconHref;
  static bool _faviconBaseCaptured = false;
  static bool _lifecycleHooked = false;
  static int _lastCount = 0;

  static String get _fallbackTitle =>
      AppBrandingService.instance.appTitle.trim().isEmpty
          ? 'Cronos Gestopro'
          : AppBrandingService.instance.appTitle.trim();

  static Future<void> setCount(int count) async {
    final n = count < 0 ? 0 : count;
    _lastCount = n;
    _persistLocal(n);
    // Su Android il SW aggiorna l'icona Home anche a app chiusa/background.
    _notifyServiceWorker(n);
    // Non bloccare: su alcuni device setAppBadge può restare appeso.
    unawaited(_setAppBadgeApi(n));
    _updateDocumentTitle(n);
    _updateFavicon(n);
    _ensureLifecycleHooks();
  }

  static Future<void> clear() => setCount(0);

  static Future<void> _setAppBadgeApi(int n) async {
    try {
      final nav = web.window.navigator as JSObject;
      if (n <= 0) {
        final clear = nav['clearAppBadge'];
        if (clear == null) return;
        final r = nav.callMethod('clearAppBadge'.toJS);
        if (r != null && r.isA<JSPromise>()) {
          await (r as JSPromise).toDart;
        }
        return;
      }
      final set = nav['setAppBadge'];
      if (set == null) return;
      final r = nav.callMethod('setAppBadge'.toJS, n.toJS);
      if (r != null && r.isA<JSPromise>()) {
        await (r as JSPromise).toDart;
      }
    } catch (_) {
      // Tab non installata / API assente: resta SW + favicon.
    }
  }

  static void _ensureLifecycleHooks() {
    if (_lifecycleHooked) return;
    _lifecycleHooked = true;
    try {
      web.document.addEventListener(
        'visibilitychange',
        (web.Event _) {
          if (web.document.visibilityState != 'visible') return;
          _reapplyLast();
        }.toJS,
      );
      web.window.addEventListener(
        'pageshow',
        (web.Event _) {
          _reapplyLast();
        }.toJS,
      );
      web.window.addEventListener(
        'focus',
        (web.Event _) {
          _reapplyLast();
        }.toJS,
      );
    } catch (_) {}
  }

  static void _reapplyLast() {
    final n = _lastCount;
    _persistLocal(n);
    _notifyServiceWorker(n);
    unawaited(_setAppBadgeApi(n));
  }

  static void _updateDocumentTitle(int n) {
    try {
      _baseTitle ??= web.document.title;
      final base = (_baseTitle ?? _fallbackTitle).trim();
      final clean = base.replaceFirst(RegExp(r'^\(\d+\+?\)\s*'), '');
      if (n <= 0) {
        web.document.title = clean.isEmpty ? _fallbackTitle : clean;
      } else {
        final label = n > 99 ? '99+' : '$n';
        web.document.title = '($label) $clean';
      }
    } catch (_) {}
  }

  static void _captureFaviconBase() {
    if (_faviconBaseCaptured) return;
    _faviconBaseCaptured = true;
    try {
      final links = web.document.querySelectorAll('link[rel*="icon"]');
      if (links.length > 0) {
        final first = links.item(0);
        if (first != null) {
          final el = first as web.HTMLLinkElement;
          _baseFaviconHref = el.href;
        }
      }
      _baseFaviconHref ??= 'icons/Icon-192.png';
    } catch (_) {
      _baseFaviconHref = 'icons/Icon-192.png';
    }
  }

  static void _setFaviconHref(String href) {
    try {
      final links = web.document.querySelectorAll('link[rel*="icon"]');
      if (links.length > 0) {
        for (var i = 0; i < links.length; i++) {
          final node = links.item(i);
          if (node == null) continue;
          (node as web.HTMLLinkElement).href = href;
        }
        return;
      }
      final link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'icon';
      link.type = 'image/png';
      link.href = href;
      web.document.head?.append(link);
    } catch (_) {}
  }

  static void _updateFavicon(int n) {
    _captureFaviconBase();
    final baseHref = _baseFaviconHref;
    if (baseHref == null || baseHref.isEmpty) return;

    if (n <= 0) {
      _setFaviconHref(baseHref);
      return;
    }

    try {
      final img = web.HTMLImageElement();
      img.crossOrigin = 'anonymous';
      img.onload = (web.Event _) {
        try {
          final canvas = web.document.createElement('canvas')
              as web.HTMLCanvasElement;
          canvas.width = 64;
          canvas.height = 64;
          final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
          if (ctx == null) return;
          ctx.clearRect(0, 0, 64, 64);
          ctx.drawImage(img, 0, 0, 64, 64);

          ctx.beginPath();
          ctx.arc(48, 16, 14, 0, 6.283185307179586);
          ctx.fillStyle = '#E53935'.toJS;
          ctx.fill();
          ctx.lineWidth = 2;
          ctx.strokeStyle = '#FFFFFF'.toJS;
          ctx.stroke();

          final label = n > 99 ? '99+' : '$n';
          ctx.fillStyle = '#FFFFFF'.toJS;
          ctx.font = 'bold ${label.length > 2 ? 12 : 16}px sans-serif';
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(label, 48, 17);

          _setFaviconHref(canvas.toDataURL('image/png'));
        } catch (_) {}
      }.toJS;
      img.onerror = (web.Event _) {}.toJS;
      img.src = baseHref;
    } catch (_) {}
  }

  static void _persistLocal(int n) {
    try {
      web.window.localStorage.setItem('cronos_chat_app_badge', '$n');
    } catch (_) {}
  }

  static void _notifyServiceWorker(int n) {
    try {
      final sw = web.window.navigator.serviceWorker;
      final ctrl = sw.controller;
      final msg = JSObject()
        ..['type'] = 'cronos-set-chat-badge'.toJS
        ..['count'] = n.toJS;
      if (ctrl != null) {
        ctrl.postMessage(msg);
        return;
      }
      // Android: controller assente subito dopo install — ritenta a ready.
      sw.ready.toDart.then((reg) {
        try {
          final r = reg;
          r.active?.postMessage(msg);
        } catch (_) {}
      });
    } catch (_) {}
  }
}
