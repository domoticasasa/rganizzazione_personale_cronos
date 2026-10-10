import 'package:flutter/material.dart';

bool get useNativeHtmlVideoPlayer => false;

Widget buildNativeHtmlVideoPlayer({
  required String url,
  bool autoPlay = true,
}) {
  return const SizedBox.shrink();
}
