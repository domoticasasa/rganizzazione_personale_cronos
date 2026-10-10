import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_sender.dart';
import 'supabase_service.dart';

const String kAppBachecaBucket = 'app_bacheca';

class BachecaPost {
  const BachecaPost({
    required this.id,
    required this.titolo,
    this.corpo = '',
    this.filePath = '',
    this.fileName = '',
    this.mimeType = '',
    this.fileSize,
    this.attivo = true,
    this.publishedAt,
    this.createdByUserUuid = '',
  });

  final String id;
  final String titolo;
  final String corpo;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int? fileSize;
  final bool attivo;
  final DateTime? publishedAt;
  final String createdByUserUuid;

  bool get hasAttachment =>
      filePath.isNotEmpty && filePath != 'pending' && fileName.isNotEmpty;

  bool get isImage {
    final m = mimeType.toLowerCase();
    final n = fileName.toLowerCase();
    return m.startsWith('image/') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp');
  }

  bool get isPdf {
    final m = mimeType.toLowerCase();
    final n = fileName.toLowerCase();
    return m.contains('pdf') || n.endsWith('.pdf');
  }

  factory BachecaPost.fromMap(Map<String, dynamic> m) {
    DateTime? ts(Object? v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    return BachecaPost(
      id: (m['id'] ?? '').toString(),
      titolo: (m['titolo'] ?? '').toString().trim(),
      corpo: (m['corpo'] ?? '').toString(),
      filePath: (m['file_path'] ?? '').toString().trim(),
      fileName: (m['file_name'] ?? '').toString().trim(),
      mimeType: (m['mime_type'] ?? '').toString().trim(),
      fileSize: m['file_size'] is num ? (m['file_size'] as num).toInt() : null,
      attivo: m['attivo'] != false,
      publishedAt: ts(m['published_at'] ?? m['created_at']),
      createdByUserUuid: (m['created_by_user_uuid'] ?? '').toString(),
    );
  }
}

abstract final class BachecaService {
  BachecaService._();

  static const int maxFileBytes = 200 * 1024 * 1024;
  static const Set<String> allowedExtensions = {
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  static SupabaseClient get _supa => SupabaseService.client;

  static bool isAllowedFileName(String name) {
    final lower = name.toLowerCase().trim();
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return false;
    return allowedExtensions.contains(lower.substring(dot + 1));
  }

  static String mimeForFileName(String name, String? pickedMime) {
    final picked = (pickedMime ?? '').trim();
    if (picked.isNotEmpty) return picked;
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  static String _sanitizeFileName(String name) {
    final trimmed = name.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    if (trimmed.isEmpty) return 'allegato.bin';
    return trimmed.replaceAll(RegExp(r'[^\w.\- ()]+'), '_');
  }

  static Future<String?> _currentUserUuid() async {
    final authId = _supa.auth.currentUser?.id;
    if (authId == null || authId.isEmpty) return null;
    try {
      final me = await _supa
          .from('users')
          .select('id_uuid')
          .eq('auth_id', authId)
          .maybeSingle();
      final id = (me?['id_uuid'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _seenPrefsKey() async {
    final uuid = await _currentUserUuid();
    final authId = _supa.auth.currentUser?.id ?? 'anon';
    return 'bacheca_last_seen_ms_${uuid ?? authId}';
  }

  static Future<int?> latestPublishedAtMs() async {
    try {
      final row = await _supa
          .from('app_bacheca_posts')
          .select('published_at')
          .eq('attivo', true)
          .order('published_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final ts = DateTime.tryParse((row['published_at'] ?? '').toString());
      return ts?.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// True se c'è almeno un avviso più recente dell'ultima lettura.
  static Future<bool> hasUnread() async {
    final latest = await latestPublishedAtMs();
    if (latest == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _seenPrefsKey();
      if (!prefs.containsKey(key)) return true;
      final seen = prefs.getInt(key) ?? 0;
      return latest > seen;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _seenPrefsKey();
      final latest = await latestPublishedAtMs();
      final ms = latest ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(key, ms);
    } catch (_) {}
  }

  static Future<List<BachecaPost>> list({bool onlyActive = true}) async {
    var q = _supa.from('app_bacheca_posts').select();
    if (onlyActive) q = q.eq('attivo', true);
    final res = await q.order('published_at', ascending: false);
    return (res as List)
        .map((e) => BachecaPost.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  static Future<String?> signedUrl(String filePath) async {
    final path = filePath.trim();
    if (path.isEmpty || path == 'pending') return null;
    final res = await _supa.storage
        .from(kAppBachecaBucket)
        .createSignedUrl(path, 3600);
    return res;
  }

  static Future<BachecaPost> create({
    required String titolo,
    required String corpo,
    String? originalFileName,
    String? mimeType,
    Uint8List? bytes,
    bool notify = true,
  }) async {
    final t = titolo.trim();
    if (t.isEmpty) throw StateError('Inserisci un titolo');
    final createdBy = await _currentUserUuid();
    final fileBytes = bytes;
    final fileName = (originalFileName ?? '').trim();
    final hasFile =
        fileBytes != null && fileBytes.isNotEmpty && fileName.isNotEmpty;
    if (hasFile) {
      if (fileBytes.length > maxFileBytes) {
        throw StateError('Il file supera i 200 MB');
      }
      if (!isAllowedFileName(fileName)) {
        throw StateError('Formato non supportato. Usa PDF, JPG, PNG o WEBP.');
      }
    }

    final inserted = await _supa
        .from('app_bacheca_posts')
        .insert({
          'titolo': t,
          'corpo': corpo.trim(),
          'file_path': hasFile ? 'pending' : null,
          'file_name': hasFile
              ? fileName.replaceAll(RegExp(r'[\\/]+'), '_')
              : null,
          'mime_type':
              hasFile ? mimeForFileName(fileName, mimeType) : null,
          'file_size': hasFile ? fileBytes.length : null,
          'created_by_user_uuid': createdBy,
          'updated_by_user_uuid': createdBy,
          'attivo': true,
        })
        .select()
        .single();

    var post = BachecaPost.fromMap(Map<String, dynamic>.from(inserted));
    if (hasFile) {
      final safeName = _sanitizeFileName(fileName);
      final path = '${post.id}/$safeName';
      try {
        await _supa.storage.from(kAppBachecaBucket).uploadBinary(
              path,
              fileBytes,
              fileOptions: FileOptions(
                contentType: mimeForFileName(fileName, mimeType),
                upsert: false,
              ),
            );
        final updated = await _supa
            .from('app_bacheca_posts')
            .update({'file_path': path})
            .eq('id', post.id)
            .select()
            .single();
        post = BachecaPost.fromMap(Map<String, dynamic>.from(updated));
      } catch (e) {
        try {
          await _supa.from('app_bacheca_posts').delete().eq('id', post.id);
        } catch (_) {}
        rethrow;
      }
    }

    if (notify) {
      await _notifyNewPost(post);
    }
    return post;
  }

  static Future<BachecaPost> update({
    required BachecaPost existing,
    required String titolo,
    required String corpo,
    bool removeAttachment = false,
    String? originalFileName,
    String? mimeType,
    Uint8List? bytes,
  }) async {
    final t = titolo.trim();
    if (t.isEmpty) throw StateError('Inserisci un titolo');
    final updatedBy = await _currentUserUuid();
    final fileBytes = bytes;
    final fileName = (originalFileName ?? '').trim();
    final hasNewFile =
        fileBytes != null && fileBytes.isNotEmpty && fileName.isNotEmpty;
    if (hasNewFile) {
      if (fileBytes.length > maxFileBytes) {
        throw StateError('Il file supera i 200 MB');
      }
      if (!isAllowedFileName(fileName)) {
        throw StateError('Formato non supportato. Usa PDF, JPG, PNG o WEBP.');
      }
    }

    final payload = <String, dynamic>{
      'titolo': t,
      'corpo': corpo.trim(),
      'updated_by_user_uuid': updatedBy,
    };

    if (removeAttachment && !hasNewFile) {
      payload['file_path'] = null;
      payload['file_name'] = null;
      payload['mime_type'] = null;
      payload['file_size'] = null;
    }

    if (hasNewFile) {
      payload['file_path'] = 'pending';
      payload['file_name'] = fileName.replaceAll(RegExp(r'[\\/]+'), '_');
      payload['mime_type'] = mimeForFileName(fileName, mimeType);
      payload['file_size'] = fileBytes.length;
    }

    final updated = await _supa
        .from('app_bacheca_posts')
        .update(payload)
        .eq('id', existing.id)
        .select()
        .single();
    var post = BachecaPost.fromMap(Map<String, dynamic>.from(updated));

    final oldPath = existing.filePath.trim();
    if ((removeAttachment || hasNewFile) &&
        oldPath.isNotEmpty &&
        oldPath != 'pending') {
      try {
        await _supa.storage.from(kAppBachecaBucket).remove([oldPath]);
      } catch (_) {}
    }

    if (hasNewFile) {
      final safeName = _sanitizeFileName(fileName);
      final path = '${existing.id}/$safeName';
      await _supa.storage.from(kAppBachecaBucket).uploadBinary(
            path,
            fileBytes,
            fileOptions: FileOptions(
              contentType: mimeForFileName(fileName, mimeType),
              upsert: true,
            ),
          );
      final refreshed = await _supa
          .from('app_bacheca_posts')
          .update({'file_path': path})
          .eq('id', existing.id)
          .select()
          .single();
      post = BachecaPost.fromMap(Map<String, dynamic>.from(refreshed));
    }

    return post;
  }

  static Future<void> delete(BachecaPost post) async {
    final path = post.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage.from(kAppBachecaBucket).remove([path]);
      } catch (_) {}
    }
    await _supa.from('app_bacheca_posts').delete().eq('id', post.id);
  }

  static Future<void> _notifyNewPost(BachecaPost post) async {
    try {
      final ids = await NotificationSender.resolveRecipientsFromTargets(
        targets: const [
          'role:dipendente',
          'role:user',
          'role:caposquadra',
          'role:dt',
          'role:assistente_dt',
          'role:logistica',
          'role:uqsa',
        ],
      );
      if (ids.isEmpty) return;
      final preview = post.corpo.trim().isEmpty
          ? 'Apri la Bacheca per leggere il messaggio.'
          : (post.corpo.trim().length > 140
              ? '${post.corpo.trim().substring(0, 140)}…'
              : post.corpo.trim());
      await NotificationSender.sendToUserIds(
        userIds: ids,
        bookingId: NotificationSender.assenzaNotificationBookingId(post.id),
        action: 'bacheca_new',
        title: 'Nuovo avviso in Bacheca',
        message: '${post.titolo}\n$preview',
        bookingType: 'bacheca',
      );
    } catch (_) {}
  }
}
