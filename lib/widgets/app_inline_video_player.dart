import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'app_html_video_view.dart';

/// Player video in-app (file da storage, URL firmato).
class AppInlineVideoPlayer extends StatefulWidget {
  const AppInlineVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = true,
    this.expandToParent = false,
  });

  final String url;
  final bool autoPlay;

  /// Se true, riempie il parent: il video si adatta (16:9 / 9:16) con contain.
  final bool expandToParent;

  @override
  State<AppInlineVideoPlayer> createState() => _AppInlineVideoPlayerState();
}

class _AppInlineVideoPlayerState extends State<AppInlineVideoPlayer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _initializing = true;
  bool _autoplayBlocked = false;

  @override
  void initState() {
    super.initState();
    if (!useNativeHtmlVideoPlayer) {
      _init();
    }
  }

  @override
  void didUpdateWidget(covariant AppInlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && !useNativeHtmlVideoPlayer) {
      _disposeController();
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
      _autoplayBlocked = false;
    });
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = c;
      await c.initialize();
      c.setLooping(false);
      c.addListener(_onTick);

      if (widget.autoPlay) {
        // Su web/mobile l'autoplay con audio fallisce se il gesto utente
        // è stato “perso” (es. dopo await della signed URL). Non trattarlo
        // come errore fatale: il video resta pronto e l'utente preme Play.
        try {
          await c.play();
        } catch (_) {
          _autoplayBlocked = true;
          try {
            await c.setVolume(0);
            await c.play();
            await c.setVolume(1);
          } catch (_) {
            // Resta in pausa; i controlli sotto bastano.
          }
        }
      }

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('src_not_supported') ||
        raw.contains('not supported') ||
        raw.contains('format')) {
      return 'Formato non supportato da questo browser/dispositivo. '
          'Prova MP4 (H.264) oppure aprilo fuori dall\'app.';
    }
    if (raw.contains('network') || raw.contains('403') || raw.contains('404')) {
      return 'Impossibile scaricare il video (rete o link scaduto). Riprova.';
    }
    return 'Impossibile riprodurre il video.';
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (useNativeHtmlVideoPlayer) {
      return ColoredBox(
        color: Colors.black,
        child: buildNativeHtmlVideoPlayer(
          url: widget.url,
          autoPlay: widget.autoPlay,
        ),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _openExternal,
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  label: const Text(
                    'Apri fuori dall\'app',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = _controller;
    if (_initializing || c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black87,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final playing = c.value.isPlaying;
    final pos = c.value.position;
    final dur = c.value.duration;
    final progress = dur.inMilliseconds <= 0
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: c.value.size.width <= 0 ? 16 : c.value.size.width,
                height: c.value.size.height <= 0 ? 9 : c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          ),
          if (!playing)
            Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Play',
                iconSize: 48,
                color: Colors.white,
                onPressed: () async {
                  try {
                    await c.play();
                    if (_autoplayBlocked && mounted) {
                      setState(() => _autoplayBlocked = false);
                    }
                  } catch (_) {}
                },
                icon: const Icon(Icons.play_arrow),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 28, 8, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_autoplayBlocked && !playing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Tocca Play per avviare',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (v) {
                          final ms = (dur.inMilliseconds * v).round();
                          c.seekTo(Duration(milliseconds: ms));
                        },
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: playing ? 'Pausa' : 'Play',
                          color: Colors.white,
                          onPressed: () async {
                            if (playing) {
                              await c.pause();
                            } else {
                              try {
                                await c.play();
                              } catch (_) {}
                            }
                          },
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        Text(
                          '${_fmt(pos)} / ${_fmt(dur)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Apri fuori dall\'app',
                          color: Colors.white70,
                          onPressed: _openExternal,
                          icon: const Icon(Icons.open_in_new, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
