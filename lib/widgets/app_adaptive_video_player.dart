import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_inline_video_player.dart';

/// Apre il player a schermo intero: il video si adatta
/// (orizzontale 16:9 o verticale 9:16) con letterbox nero.
Future<void> showAdaptiveVideoPlayer(
  BuildContext context, {
  required String url,
  String? title,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chiudi video',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim, secondary) {
      return _AdaptiveVideoPlayerScaffold(
        url: url,
        title: title,
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

class _AdaptiveVideoPlayerScaffold extends StatefulWidget {
  const _AdaptiveVideoPlayerScaffold({
    required this.url,
    this.title,
  });

  final String url;
  final String? title;

  @override
  State<_AdaptiveVideoPlayerScaffold> createState() =>
      _AdaptiveVideoPlayerScaffoldState();
}

class _AdaptiveVideoPlayerScaffoldState
    extends State<_AdaptiveVideoPlayerScaffold> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').trim();
    final padding = MediaQuery.paddingOf(context);

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Il player riempie lo schermo; il video resta in contain
          // (si allunga in altezza se verticale, in larghezza se orizzontale).
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: padding.top + 48,
                bottom: padding.bottom + 8,
                left: padding.left + 4,
                right: padding.right + 4,
              ),
              child: AppInlineVideoPlayer(
                url: widget.url,
                autoPlay: true,
                expandToParent: true,
              ),
            ),
          ),
          Positioned(
            top: padding.top + 4,
            left: 4,
            right: 4,
            child: Row(
              children: [
                if (title.isNotEmpty)
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                Material(
                  color: Colors.white12,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Chiudi',
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
