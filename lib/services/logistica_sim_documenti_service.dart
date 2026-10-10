import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

const String kLogisticaSimDocumentiBucket = 'logistica_sim_documenti';

class SimAssegnazioneDocumento {
  const SimAssegnazioneDocumento({
    required this.id,
    required this.simId,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.note,
    required this.uploadedAt,
    this.uploadedByUserUuid,
  });

  final String id;
  final String simId;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final String? note;
  final DateTime uploadedAt;
  final String? uploadedByUserUuid;

  factory SimAssegnazioneDocumento.fromMap(Map<String, dynamic> m) {
    return SimAssegnazioneDocumento(
      id: (m['id'] ?? '').toString(),
      simId: (m['sim_id'] ?? '').toString(),
      filePath: (m['file_path'] ?? '').toString(),
      fileName: (m['file_name'] ?? '').toString(),
      mimeType: (m['mime_type'] as String?)?.trim(),
      fileSize: m['file_size'] is num ? (m['file_size'] as num).toInt() : null,
      note: (m['note'] as String?)?.trim(),
      uploadedAt: DateTime.tryParse((m['uploaded_at'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
      uploadedByUserUuid: (m['uploaded_by_user_uuid'] as String?)?.trim(),
    );
  }
}

class LogisticaSimDocumentiService {
  LogisticaSimDocumentiService._();

  static const int maxFileBytes = 50 * 1024 * 1024;

  static SupabaseClient get _supa => SupabaseService.client;

  static bool isAllowedFileName(String name) {
    return name.toLowerCase().trim().endsWith('.pdf');
  }

  static String _sanitizeFileName(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final dot = trimmed.lastIndexOf('.');
    var stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    var ext = dot > 0 ? trimmed.substring(dot).toLowerCase() : '.pdf';
    if (ext != '.pdf') ext = '.pdf';
    stem = stem.replaceAll(RegExp(r'\s+'), '_');
    stem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    stem = stem.replaceAll(RegExp(r'_+'), '_');
    stem = stem.replaceAll(RegExp(r'^_+|_+$'), '');
    if (stem.isEmpty) stem = 'assegnazione_sim';
    return '$stem$ext';
  }

  static Future<String?> _currentUserUuid() async {
    final authId = _supa.auth.currentUser?.id;
    if (authId == null || authId.isEmpty) return null;
    final me = await _supa
        .from('users')
        .select('id_uuid')
        .eq('auth_id', authId)
        .maybeSingle();
    final id = (me?['id_uuid'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  static Future<List<SimAssegnazioneDocumento>> listForSim(String simId) async {
    final res = await _supa
        .from('logistica_sim_documenti')
        .select()
        .eq('sim_id', simId)
        .order('uploaded_at', ascending: false);
    return [
      for (final raw in (res as List))
        SimAssegnazioneDocumento.fromMap(
          Map<String, dynamic>.from(raw as Map),
        ),
    ];
  }

  static Future<Map<String, int>> countBySim() async {
    final res = await _supa.from('logistica_sim_documenti').select('sim_id');
    final out = <String, int>{};
    for (final raw in (res as List)) {
      final id =
          (Map<String, dynamic>.from(raw as Map)['sim_id'] ?? '').toString();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  static Future<SimAssegnazioneDocumento> upload({
    required String simId,
    required String originalFileName,
    required Uint8List bytes,
    String? note,
  }) async {
    if (bytes.isEmpty) throw StateError('File vuoto');
    if (bytes.length > maxFileBytes) {
      throw StateError('Il PDF supera i 50 MB');
    }
    if (!isAllowedFileName(originalFileName)) {
      throw StateError('Formato non supportato. Carica un PDF.');
    }

    final displayName =
        originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizeFileName(originalFileName);
    final uploadedBy = await _currentUserUuid();
    final inserted = await _supa
        .from('logistica_sim_documenti')
        .insert({
          'sim_id': simId,
          'file_path': 'pending',
          'file_name': displayName.isEmpty ? safeName : displayName,
          'mime_type': 'application/pdf',
          'file_size': bytes.length,
          'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
          'uploaded_by_user_uuid': uploadedBy,
        })
        .select()
        .single();
    final id = (inserted['id'] ?? '').toString();
    final path = '$simId/$id/$safeName';
    try {
      await _supa.storage.from(kLogisticaSimDocumentiBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
      final updated = await _supa
          .from('logistica_sim_documenti')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return SimAssegnazioneDocumento.fromMap(
        Map<String, dynamic>.from(updated),
      );
    } catch (e) {
      try {
        await _supa.from('logistica_sim_documenti').delete().eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> delete(SimAssegnazioneDocumento row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage.from(kLogisticaSimDocumentiBucket).remove([path]);
      } catch (_) {}
    }
    await _supa.from('logistica_sim_documenti').delete().eq('id', row.id);
  }

  static Future<String> signedUrl(
    SimAssegnazioneDocumento row, {
    int expiresIn = 3600,
  }) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaSimDocumentiBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadBytes(SimAssegnazioneDocumento row) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage.from(kLogisticaSimDocumentiBucket).download(path);
  }
}
