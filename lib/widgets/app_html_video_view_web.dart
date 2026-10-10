import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _nextId = 0;

bool get useNativeHtmlVideoPlayer => true;

Widget buildNativeHtmlVideoPlayer({
  required String url,
  bool autoPlay = true,
}) {
  final viewType = 'cronos-html-video-${_nextId++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final video = web.HTMLVideoElement()
      ..src = url
      ..controls = true
      ..autoplay = autoPlay
      ..playsInline = true
      ..preload = 'metadata'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000';
    // muted=true permette l'autoplay dopo await async; poi togliamo mute.
    if (autoPlay) {
      video.muted = true;
      video.onPlay.listen((_) {
        // Ripristina audio al primo play riuscito (gesto / autoplay muted).
        if (video.muted) {
          video.muted = false;
        }
      });
    }
    return video;
  });
  return HtmlElementView(viewType: viewType);
}
