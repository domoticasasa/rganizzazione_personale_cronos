import 'package:flutter/material.dart';

import '../pages/video_gallery_page.dart';
import 'futuristic_navigation.dart';

/// Apre la galleria video da qualsiasi punto dell'app.
abstract final class VideoGalleryNavigation {
  VideoGalleryNavigation._();

  static Future<void> open(BuildContext context, {String? role}) {
    return FuturisticNavigation.pushPage(
      context,
      page: VideoGalleryPage(role: role),
      title: 'Video istruttivi',
    );
  }
}
