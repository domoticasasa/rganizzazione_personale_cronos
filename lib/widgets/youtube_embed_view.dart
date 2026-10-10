import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/youtube_utils.dart';
import 'youtube_embed_view_web.dart'
    if (dart.library.io) 'youtube_embed_view_io.dart' as embed_impl;

/// Player YouTube incorporato (web iframe / WebView / link esterno).
class YoutubeEmbedView extends StatelessWidget {
  const YoutubeEmbedView({
    super.key,
    required this.videoId,
    this.autoplay = true,
  });

  final String videoId;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    return embed_impl.buildYoutubeEmbed(
      videoId: videoId,
      autoplay: autoplay,
    );
  }

  static Future<void> openFullscreen(
    BuildContext context, {
    required String videoId,
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Apri su YouTube',
                      onPressed: () => launchUrl(
                        Uri.parse(YoutubeUtils.watchUrl(videoId)),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: YoutubeEmbedView(videoId: videoId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
