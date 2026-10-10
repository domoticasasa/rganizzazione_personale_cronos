// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../utils/youtube_utils.dart';

int _nextId = 0;

Widget buildYoutubeEmbed({
  required String videoId,
  bool autoplay = true,
}) {
  final viewType = 'youtube-embed-${_nextId++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final iframe = html.IFrameElement()
      ..src = YoutubeUtils.embedUrl(videoId, autoplay: autoplay)
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow =
          'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
      ..allowFullscreen = true;
    return iframe;
  });
  return HtmlElementView(viewType: viewType);
}
