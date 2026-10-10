// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/services.dart';

import 'gestopro_splash_sound.dart';

html.AudioElement? _element;
String? _objectUrl;
Completer<void>? _prepareCompleter;

Future<void> prepareSplashIntro() async {
  if (_element != null) return;
  if (_prepareCompleter != null) {
    await _prepareCompleter!.future;
    return;
  }
  _prepareCompleter = Completer<void>();
  try {
    final data = await rootBundle.load(GestoproSplashSound.assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (_objectUrl != null) {
      html.Url.revokeObjectUrl(_objectUrl!);
    }
    final blob = html.Blob(<Object>[Uint8List.fromList(bytes)], 'audio/mpeg');
    _objectUrl = html.Url.createObjectUrlFromBlob(blob);
    _element = html.AudioElement(_objectUrl!)
      ..preload = 'auto'
      ..volume = 1.0;
    debugSplashSound('preparato da rootBundle (${bytes.length} byte)');
  } catch (e) {
    debugSplashSound('rootBundle fallito: $e — fallback URL');
    _element = html.AudioElement(
      Uri.base.resolve('assets/assets/gestopro_splash_intro.mp3').toString(),
    )
      ..preload = 'auto'
      ..volume = 1.0;
  } finally {
    _prepareCompleter!.complete();
    _prepareCompleter = null;
  }
}

Future<bool> _playViaPwaHelper() async {
  try {
    final pwa = js.context['cronosPwa'];
    if (pwa == null) return false;
    final fn = (pwa as dynamic).playSplashIntro;
    if (fn == null) return false;
    final result = fn();
    final ok = result is Future ? await result : result;
    if (ok == true) {
      debugSplashSound('play via pwa_helper');
      return true;
    }
    return false;
  } catch (e) {
    debugSplashSound('pwa_helper fallito: $e');
    return false;
  }
}

Future<void> playSplashIntro() async {
  await prepareSplashIntro();

  final el = _element;
  if (el != null) {
    try {
      el.volume = 1.0;
      try {
        el.currentTime = 0;
      } catch (_) {}
      await el.play();
      debugSplashSound('play ok (html)');
      return;
    } catch (e) {
      debugSplashSound('html play fallito: $e');
    }
  }

  if (await _playViaPwaHelper()) return;
  throw StateError('splash audio play blocked');
}

Future<void> stopSplashIntro() async {
  try {
    _element?.pause();
    if (_element != null) _element!.currentTime = 0;
  } catch (_) {}
}
