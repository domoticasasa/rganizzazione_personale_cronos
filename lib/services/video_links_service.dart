import 'dart:typed_data';

import 'supabase_service.dart';
import 'supabase_tus_upload.dart';

const String kAppInstructionalVideosBucket = 'app_instructional_videos';

class AppVideoLink {
  final String idUuid;
  final String sectionTitle;
  final String title;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final String? description;
  final bool featured;
  final int sortOrder;
  final bool active;

  const AppVideoLink({
    required this.idUuid,
    required this.sectionTitle,
    required this.title,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.description,
    this.featured = false,
    this.sortOrder = 0,
    this.active = true,
  });

  bool get hasPlayableFile =>
      (storagePath ?? '').trim().isNotEmpty;

  factory AppVideoLink.fromMap(Map<String, dynamic> m) {
    return AppVideoLink(
      idUuid: (m['id_uuid'] ?? '').toString(),
      sectionTitle: (m['section_title'] ?? 'Video').toString().trim(),
      title: (m['title'] ?? '').toString().trim(),
      storagePath: (m['storage_path'] ?? '').toString().trim().isEmpty
          ? null
          : (m['storage_path'] ?? '').toString().trim(),
      fileName: (m['file_name'] ?? '').toString().trim().isEmpty
          ? null
          : (m['file_name'] ?? '').toString().trim(),
      mimeType: (m['mime_type'] ?? '').toString().trim().isEmpty
          ? null
          : (m['mime_type'] ?? '').toString().trim(),
      fileSize: int.tryParse((m['file_size'] ?? '').toString()),
      description: (m['description'] ?? '').toString().trim().isEmpty
          ? null
          : (m['description'] ?? '').toString().trim(),
      featured: m['featured'] == true,
      sortOrder: int.tryParse((m['sort_order'] ?? '0').toString()) ?? 0,
      active: m['active'] != false,
    );
  }
}

class VideoLinksService {
  static const String table = 'app_video_links';
  static const int maxFileBytes = 700 * 1024 * 1024; // 700 MiB
  static const Set<String> allowedExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
    'webm',
    '3gp',
  };

  static bool isAllowedFileName(String fileName) {
    final ext = _extensionOf(fileName);
    return ext != null && allowedExtensions.contains(ext);
  }

  static String mimeForFileName(String fileName, [String? hint]) {
    final h = (hint ?? '').trim().toLowerCase();
    if (h.startsWith('video/')) return h;
    switch (_extensionOf(fileName)) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'video/mp4';
    }
  }

  static String? _extensionOf(String fileName) {
    final name = fileName.trim().toLowerCase();
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return null;
    return name.substring(i + 1);
  }

  static String _sanitizeFileName(String fileName) {
    final cleaned = fileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    if (cleaned.isEmpty) return 'video.mp4';
    return cleaned.length > 120 ? cleaned.substring(cleaned.length - 120) : cleaned;
  }

  static Future<List<AppVideoLink>> listActive() async {
    final res = await SupabaseService.client
        .from(table)
        .select()
        .eq('active', true)
        .neq('storage_path', 'pending')
        .not('storage_path', 'is', null)
        .order('section_title')
        .order('sort_order')
        .order('title');
    return (res as List)
        .map((e) => AppVideoLink.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((v) => v.hasPlayableFile)
        .toList(growable: false);
  }

  static Future<String> signedPlayUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw StateError('Percorso video mancante');
    }
    // 4 ore: video grandi possono restare in riproduzione a lungo.
    return SupabaseService.client.storage
        .from(kAppInstructionalVideosBucket)
        .createSignedUrl(path, 60 * 60 * 4);
  }

  static Future<AppVideoLink> uploadAndInsert({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required String title,
    String sectionTitle = 'Video',
    String? description,
    bool featured = false,
    int sortOrder = 0,
  }) async {
    final name = fileName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Nome file mancante');
    }
    if (!isAllowedFileName(name)) {
      throw ArgumentError(
        'Formato non supportato. Usa MP4, MOV, M4V, WEBM o 3GP.',
      );
    }
    if (bytes.isEmpty) {
      throw ArgumentError('File video vuoto');
    }
    if (bytes.length > maxFileBytes) {
      throw StateError('Il video supera i 700 MB');
    }

    final cleanTitle =
        title.trim().isEmpty ? _defaultTitleFromFileName(name) : title.trim();
    final contentType = mimeForFileName(name, mimeType);

    final inserted = await SupabaseService.client
        .from(table)
        .insert({
          'section_title':
              sectionTitle.trim().isEmpty ? 'Video' : sectionTitle.trim(),
          'title': cleanTitle,
          'youtube_url': null,
          'youtube_video_id': null,
          'storage_path': 'pending',
          'file_name': _sanitizeFileName(name),
          'mime_type': contentType,
          'file_size': bytes.length,
          'description':
              (description ?? '').trim().isEmpty ? null : description!.trim(),
          'featured': featured,
          'sort_order': sortOrder,
          'active': true,
        })
        .select()
        .single();

    var row = AppVideoLink.fromMap(Map<String, dynamic>.from(inserted));
    final safeName = _sanitizeFileName(name);
    final path = '${row.idUuid}/$safeName';
    try {
      // TUS a chunk da 6 MiB: evita 413 Payload too large sull'upload standard.
      await SupabaseTusUpload.uploadBinary(
        bucket: kAppInstructionalVideosBucket,
        objectPath: path,
        bytes: bytes,
        contentType: contentType,
        upsert: false,
      );
      final updated = await SupabaseService.client
          .from(table)
          .update({'storage_path': path})
          .eq('id_uuid', row.idUuid)
          .select()
          .single();
      row = AppVideoLink.fromMap(Map<String, dynamic>.from(updated));
    } catch (e) {
      try {
        await SupabaseService.client.from(table).delete().eq('id_uuid', row.idUuid);
      } catch (_) {}
      rethrow;
    }
    return row;
  }

  static String _defaultTitleFromFileName(String fileName) {
    final base = fileName.trim();
    final i = base.lastIndexOf('.');
    final withoutExt = i > 0 ? base.substring(0, i) : base;
    final cleaned = withoutExt.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return cleaned.isEmpty ? 'Video istruttivo' : cleaned;
  }

  static Future<void> delete(AppVideoLink video) async {
    final path = (video.storagePath ?? '').trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await SupabaseService.client.storage
            .from(kAppInstructionalVideosBucket)
            .remove([path]);
      } catch (_) {}
    }
    await SupabaseService.client.from(table).delete().eq('id_uuid', video.idUuid);
  }

  static Map<String, List<AppVideoLink>> groupBySection(List<AppVideoLink> items) {
    final map = <String, List<AppVideoLink>>{};
    for (final v in items) {
      final key = v.sectionTitle.isEmpty ? 'Video' : v.sectionTitle;
      map.putIfAbsent(key, () => <AppVideoLink>[]).add(v);
    }
    return map;
  }
}
