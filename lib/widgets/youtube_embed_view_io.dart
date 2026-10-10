import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/youtube_utils.dart';

Widget buildYoutubeEmbed({
  required String videoId,
  bool autoplay = true,
}) {
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(
      Uri.parse(YoutubeUtils.embedUrl(videoId, autoplay: autoplay)),
    );
  return WebViewWidget(controller: controller);
}
