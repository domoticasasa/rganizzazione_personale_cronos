import 'package:flutter/material.dart';

import 'app_html_video_view_web.dart'
    if (dart.library.io) 'app_html_video_view_stub.dart' as html_video;

/// True su web: usa il tag HTML `<video>` nativo (più affidabile del plugin).
bool get useNativeHtmlVideoPlayer => html_video.useNativeHtmlVideoPlayer;

Widget buildNativeHtmlVideoPlayer({
  required String url,
  bool autoPlay = true,
}) {
  return html_video.buildNativeHtmlVideoPlayer(
    url: url,
    autoPlay: autoPlay,
  );
}
