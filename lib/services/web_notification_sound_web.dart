// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';

/// Suono notifiche su Web (HTML5 Audio + sblocco autoplay al primo gesto utente).
abstract final class WebNotificationSound {
  static html.AudioElement? _element;
  static bool _unlocked = false;
  static String? _resolvedUrl;

  static List<String> get _candidateUrls => <String>[
        Uri.base.resolve('assets/assets/notification.mp3').toString(),
        Uri.base.resolve('assets/notification.mp3').toString(),
      ];

  static void prepare() {
    _resolvedUrl ??= _candidateUrls.first;
    _element ??= html.AudioElement(_resolvedUrl)
      ..preload = 'auto'
      ..volume = 1.0;
    _element!.onError.listen((_) {
      _tryNextAssetUrl();
    });
  }

  static void _tryNextAssetUrl() {
    final current = _resolvedUrl;
    for (final url in _candidateUrls) {
      if (url == current) continue;
      _resolvedUrl = url;
      _element = html.AudioElement(url)
        ..preload = 'auto'
        ..volume = 1.0;
      return;
    }
  }

  static Future<bool> _playViaPwaHelper() async {
    try {
      final pwa = js.context['cronosPwa'];
      if (pwa == null) return false;
      final fn = (pwa as dynamic).playNotificationSound;
      if (fn == null) return false;
      final result = fn();
      if (result is Future) {
        await result;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _unlockViaPwaHelper() async {
    try {
      final pwa = js.context['cronosPwa'];
      if (pwa == null) return false;
      final fn = (pwa as dynamic).unlockNotificationSound;
      if (fn == null) return false;
      final result = fn();
      if (result is Future) {
        return await result == true;
      }
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Chiamare dopo login o al primo tap: sblocca la riproduzione con tab aperta.
  static Future<bool> unlock() async {
    if (_unlocked) return true;

    final viaJs = await _unlockViaPwaHelper();
    if (viaJs) {
      _unlocked = true;
      return true;
    }

    prepare();
    final el = _element!;
    try {
      el.volume = 0.01;
      await el.play();
      el.pause();
      el.currentTime = 0;
      el.volume = 1.0;
      _unlocked = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web audio sbloccato ($_resolvedUrl)');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web audio unlock fallito: $e');
      }
      return false;
    }
  }

  static Future<void> play() async {
    if (!_unlocked) {
      await unlock();
    }

    if (await _playViaPwaHelper()) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web notification sound (pwa_helper.js)');
      }
      return;
    }

    prepare();
    final el = _element!;
    try {
      el.currentTime = 0;
      await el.play();
      if (kDebugMode) {
        // ignore: avoid_print
        print('>>> Web notification sound played ($_resolvedUrl)');
      }
    } catch (e) {
      final ok = await unlock();
      if (ok) {
        try {
          el.currentTime = 0;
          await el.play();
          return;
        } catch (_) {}
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '>>> Web notification sound blocked: $e '
          '(clicca una volta nella pagina per abilitare notification.mp3)',
        );
      }
    }
  }
}
