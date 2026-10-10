import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_device_unlock_gate.dart';
import '../services/video_links_service.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_adaptive_video_player.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';

class VideoGalleryPage extends StatefulWidget {
  final String? role;

  const VideoGalleryPage({super.key, this.role});

  @override
  State<VideoGalleryPage> createState() => _VideoGalleryPageState();
}

class _VideoGalleryPageState extends State<VideoGalleryPage> {
  bool _loading = true;
  bool _uploading = false;
  List<AppVideoLink> _videos = const [];
  AppVideoLink? _featured;
  final Map<String, String> _signedUrls = <String, String>{};

  bool get _canManage {
    final role = widget.role ?? GestoproSessionScope.maybeOf(context)?.role;
    return role != null && isAnyAdminRole(role);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await VideoLinksService.listActive();
      AppVideoLink? featured;
      for (final v in list) {
        if (v.featured) {
          featured = v;
          break;
        }
      }
      featured ??= list.isEmpty ? null : list.first;
      if (!mounted) return;
      setState(() {
        _videos = list;
        _featured = featured;
        _signedUrls.clear();
        _loading = false;
      });
      // Prefetch signed URL così il Play resta vicino al gesto utente.
      _prefetchSignedUrls(list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore caricamento video: $e');
    }
  }

  Future<void> _prefetchSignedUrls(List<AppVideoLink> list) async {
    for (final video in list.take(8)) {
      try {
        await _ensureSignedUrl(video);
      } catch (_) {}
    }
  }

  Future<String?> _ensureSignedUrl(AppVideoLink video) async {
    final path = (video.storagePath ?? '').trim();
    if (path.isEmpty) return null;
    final cached = _signedUrls[video.idUuid];
    if (cached != null && cached.isNotEmpty) return cached;
    final url = await VideoLinksService.signedPlayUrl(path);
    if (!mounted) return url;
    _signedUrls[video.idUuid] = url;
    return url;
  }

  Future<void> _openAddDialog() async {
    final titleCtrl = TextEditingController();
    final sectionCtrl = TextEditingController(text: 'Video');
    final descCtrl = TextEditingController();
    var featured = false;
    XFile? picked;
    Uint8List? bytes;
    String? pickError;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Carica video'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      setLocal(() => pickError = null);
                      try {
                        final file = await _pickVideoFile(ctx);
                        if (file == null) return;
                        final data = await file.readAsBytes();
                        if (data.isEmpty) {
                          setLocal(() => pickError = 'File vuoto');
                          return;
                        }
                        if (data.length > VideoLinksService.maxFileBytes) {
                          setLocal(() => pickError = 'Il video supera i 700 MB');
                          return;
                        }
                        if (!VideoLinksService.isAllowedFileName(file.name)) {
                          setLocal(
                            () => pickError =
                                'Formato non supportato (MP4, MOV, M4V, WEBM, 3GP)',
                          );
                          return;
                        }
                        setLocal(() {
                          picked = file;
                          bytes = data;
                          if (titleCtrl.text.trim().isEmpty) {
                            final n = file.name;
                            final i = n.lastIndexOf('.');
                            titleCtrl.text =
                                i > 0 ? n.substring(0, i) : n;
                          }
                        });
                      } catch (e) {
                        setLocal(() => pickError = '$e');
                      }
                    },
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(
                      picked == null
                          ? 'Scegli / registra video'
                          : 'Cambia video',
                    ),
                  ),
                  if (picked != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${picked!.name}'
                      '${bytes != null ? ' · ${_fmtBytes(bytes!.length)}' : ''}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  if (pickError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      pickError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titolo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sectionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sezione (es. Tutorial, Sicurezza)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione (opzionale)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('In evidenza in alto'),
                    value: featured,
                    onChanged: (v) => setLocal(() => featured = v == true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                if (picked == null || bytes == null || bytes!.isEmpty) {
                  setLocal(() => pickError = 'Seleziona un video');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Carica'),
            ),
          ],
        ),
      ),
    );

    final selected = picked;
    final data = bytes;
    final title = titleCtrl.text;
    final section = sectionCtrl.text;
    final desc = descCtrl.text;
    titleCtrl.dispose();
    sectionCtrl.dispose();
    descCtrl.dispose();

    if (ok != true || selected == null || data == null) return;

    setState(() => _uploading = true);
    try {
      await VideoLinksService.uploadAndInsert(
        bytes: data,
        fileName: selected.name,
        mimeType: selected.mimeType,
        title: title,
        sectionTitle: section,
        description: desc,
        featured: featured,
      );
      if (mounted) {
        ModifyFeedback.success(context, 'Video caricato.');
        await _load();
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<XFile?> _pickVideoFile(BuildContext dialogContext) {
    return AppDeviceUnlockGate.runWithExternalPicker(() async {
    final isMobile = !kIsWeb && useMobileUi(dialogContext);
    if (isMobile) {
      final choice = await showModalBottomSheet<String>(
        context: dialogContext,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Dalla galleria'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Registra con la fotocamera'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Scegli file'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return null;
      if (choice == 'gallery' || choice == 'camera') {
        final picker = ImagePicker();
        return picker.pickVideo(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        );
      }
    }

    const group = XTypeGroup(
      label: 'Video',
      extensions: <String>['mp4', 'mov', 'm4v', 'webm', '3gp'],
      mimeTypes: <String>[
        'video/mp4',
        'video/quicktime',
        'video/webm',
        'video/3gpp',
        'video/x-m4v',
      ],
    );
    return openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    });
  }

  static String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmDelete(AppVideoLink video) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina video'),
        content: Text('Rimuovere «${video.title}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await VideoLinksService.delete(video);
      if (mounted) {
        _signedUrls.remove(video.idUuid);
        ModifyFeedback.success(context, 'Video rimosso.');
        await _load();
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore: $e');
    }
  }

  Future<void> _play(AppVideoLink video) async {
    try {
      final url = await _ensureSignedUrl(video);
      if (!mounted) return;
      if (url == null) {
        ModifyFeedback.error(context, 'Video non disponibile');
        return;
      }
      await showAdaptiveVideoPlayer(
        context,
        url: url,
        title: video.title,
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore apertura video: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = VideoLinksService.groupBySection(_videos);
    final sections = grouped.keys.toList()..sort();

    final body = _loading || _uploading
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (_uploading) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Caricamento video in corso…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          )
        : _videos.isEmpty
            ? Center(
                child: Text(
                  _canManage
                      ? 'Nessun video. Usa + per caricare un video dal cellulare.'
                      : 'Nessun video disponibile.',
                  textAlign: TextAlign.center,
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    if (_featured != null) ...[
                      _FeaturedCard(
                        video: _featured!,
                        onPlay: () => _play(_featured!),
                        canManage: _canManage,
                        onDelete: () => _confirmDelete(_featured!),
                      ),
                      const SizedBox(height: 24),
                    ],
                    for (final section in sections) ...[
                      Text(
                        section,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: _VideoCard.listRowHeight,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: grouped[section]!.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (_, i) {
                            final v = grouped[section]![i];
                            if (_featured?.idUuid == v.idUuid) {
                              return const SizedBox.shrink();
                            }
                            return _VideoCard(
                              video: v,
                              onPlay: () => _play(v),
                              canManage: _canManage,
                              onDelete: () => _confirmDelete(v),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ],
                ),
              );

    const pageTitle = 'Video istruttivi';
    final toolbarActions = <Widget>[
      if (_canManage)
        IconButton(
          tooltip: 'Carica video',
          onPressed: _uploading ? null : _openAddDialog,
          icon: const Icon(Icons.upload_file_outlined),
        ),
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _uploading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ];

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: toolbarActions,
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const Text(pageTitle),
          actions: toolbarActions,
        ),
      ),
      body: body,
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.video,
    required this.onPlay,
    required this.canManage,
    required this.onDelete,
  });

  final AppVideoLink video;
  final VoidCallback onPlay;
  final bool canManage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final preview = _VideoThumb(
          width: wide ? 360 : constraints.maxWidth,
          height: wide ? 202 : (constraints.maxWidth * 9 / 16).clamp(160, 240),
          borderRadius: 12,
          onPlay: onPlay,
        );
        final meta = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              video.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if ((video.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(video.description!),
            ],
            const SizedBox(height: 8),
            Text(
              video.sectionTitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (canManage) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Elimina'),
              ),
            ],
          ],
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preview,
              const SizedBox(height: 12),
              meta,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            const SizedBox(width: 16),
            Expanded(child: meta),
          ],
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.onPlay,
    required this.canManage,
    required this.onDelete,
  });

  static const double previewHeight = 158;
  static const double listRowHeight = previewHeight + 8 + 40;

  final AppVideoLink video;
  final VoidCallback onPlay;
  final bool canManage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: listRowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _VideoThumb(
                width: 280,
                height: previewHeight,
                borderRadius: 10,
                onPlay: onPlay,
              ),
              if (canManage)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Elimina',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      color: Colors.white,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoThumb extends StatelessWidget {
  const _VideoThumb({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.onPlay,
  });

  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Container(
              width: width,
              height: height,
              color: Colors.black12,
              child: Icon(
                Icons.play_circle_outline,
                size: width > 300 ? 48 : 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white.withValues(alpha: 0.92),
              size: width > 300 ? 44 : 36,
            ),
          ),
        ],
      ),
    );
  }
}

