import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logistica_multicard_mezzo_sync.dart';
import 'supabase_service.dart';

const String kLogisticaMulticardMdoAssegnazioniBucket =
    'logistica_multicard_mdo_assegnazioni';

class MulticardMdoRef {
  const MulticardMdoRef({
    required this.id,
    required this.multicard,
    required this.assegnatario,
    this.limiteSpesa,
    this.scadenzaCarta,
  });

  final String id;
  final String multicard;
  final String assegnatario;
  final String? limiteSpesa;
  final String? scadenzaCarta;

  String get title {
    if (multicard.isNotEmpty) return multicard;
    return 'Multicard';
  }

  String get subtitle {
    final parts = <String>[
      'Assegnazione: MDO',
      if (assegnatario.isNotEmpty) 'Dipendente: $assegnatario',
      if ((limiteSpesa ?? '').trim().isNotEmpty) 'Limite: ${limiteSpesa!.trim()}',
    ];
    return parts.join(' · ');
  }

  factory MulticardMdoRef.fromMap(Map<String, dynamic> m) {
    final limite = (m['limite_spesa_giornaliero'] ?? '').toString().trim();
    final scadenza = (m['scadenza_carta'] ?? '').toString().trim();
    return MulticardMdoRef(
      id: (m['id_uuid'] ?? '').toString().trim(),
      multicard: (m['multicard'] ?? '').toString().trim(),
      assegnatario: (m['assegnatario_attuale'] ?? '').toString().trim(),
      limiteSpesa: limite.isEmpty ? null : limite,
      scadenzaCarta: scadenza.isEmpty ? null : scadenza,
    );
  }
}

class MulticardMdoAssegnazioneFile {
  const MulticardMdoAssegnazioneFile({
    required this.id,
    required this.multicardId,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.note,
    required this.uploadedAt,
    this.uploadedByUserUuid,
  });

  final String id;
  final String multicardId;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final String? note;
  final DateTime uploadedAt;
  final String? uploadedByUserUuid;

  factory MulticardMdoAssegnazioneFile.fromMap(Map<String, dynamic> m) {
    return MulticardMdoAssegnazioneFile(
      id: (m['id'] ?? '').toString(),
      multicardId: (m['multicard_id'] ?? '').toString(),
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

class LogisticaMulticardMdoAssegnazioniService {
  LogisticaMulticardMdoAssegnazioniService._();

  static const int maxFileBytes = 50 * 1024 * 1024;
  static const Set<String> allowedExtensions = {'pdf'};

  static SupabaseClient get _supa => SupabaseService.client;

  static bool isAllowedFileName(String name) {
    final lower = name.toLowerCase().trim();
    return lower.endsWith('.pdf');
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
    if (stem.isEmpty) stem = 'assegnazione_mdo';
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

  /// Solo multicard con `mezzo_targa = MDO` (compaiono/spariscono in automatico).
  static Future<List<MulticardMdoRef>> listMulticardMdo() async {
    final res = await _supa
        .from('logistica_multicard')
        .select(
          'id_uuid,multicard,assegnatario_attuale,'
          'limite_spesa_giornaliero,scadenza_carta,mezzo_targa',
        )
        .eq('mezzo_targa', kMulticardAssegnazioneMdo)
        .order('multicard', ascending: true);
    return [
      for (final raw in (res as List))
        MulticardMdoRef.fromMap(Map<String, dynamic>.from(raw as Map)),
    ].where((m) => m.id.isNotEmpty).toList(growable: false);
  }

  static Future<List<MulticardMdoAssegnazioneFile>> listForMulticard(
    String multicardId,
  ) async {
    final res = await _supa
        .from('logistica_multicard_mdo_assegnazioni')
        .select()
        .eq('multicard_id', multicardId)
        .order('uploaded_at', ascending: false);
    return [
      for (final raw in (res as List))
        MulticardMdoAssegnazioneFile.fromMap(
          Map<String, dynamic>.from(raw as Map),
        ),
    ];
  }

  static Future<Map<String, int>> countByMulticard() async {
    final res =
        await _supa.from('logistica_multicard_mdo_assegnazioni').select(
              'multicard_id',
            );
    final out = <String, int>{};
    for (final raw in (res as List)) {
      final id = (Map<String, dynamic>.from(raw as Map)['multicard_id'] ?? '')
          .toString();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  static Future<void> _assertStillMdo(String multicardId) async {
    final row = await _supa
        .from('logistica_multicard')
        .select('mezzo_targa')
        .eq('id_uuid', multicardId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Multicard non trovata');
    }
    if (!isMulticardMdoAssignment(row['mezzo_targa']?.toString())) {
      throw StateError(
        'La multicard non è più assegnata a MDO: non è possibile caricare PDF.',
      );
    }
  }

  static Future<MulticardMdoAssegnazioneFile> upload({
    required String multicardId,
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
    await _assertStillMdo(multicardId);

    final displayName =
        originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizeFileName(originalFileName);
    final uploadedBy = await _currentUserUuid();
    final inserted = await _supa
        .from('logistica_multicard_mdo_assegnazioni')
        .insert({
          'multicard_id': multicardId,
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
    final path = '$multicardId/$id/$safeName';
    try {
      await _supa.storage
          .from(kLogisticaMulticardMdoAssegnazioniBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
      final updated = await _supa
          .from('logistica_multicard_mdo_assegnazioni')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return MulticardMdoAssegnazioneFile.fromMap(
        Map<String, dynamic>.from(updated),
      );
    } catch (e) {
      try {
        await _supa
            .from('logistica_multicard_mdo_assegnazioni')
            .delete()
            .eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> delete(MulticardMdoAssegnazioneFile row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage
            .from(kLogisticaMulticardMdoAssegnazioniBucket)
            .remove([path]);
      } catch (_) {}
    }
    await _supa
        .from('logistica_multicard_mdo_assegnazioni')
        .delete()
        .eq('id', row.id);
  }

  static Future<String> signedUrl(
    MulticardMdoAssegnazioneFile row, {
    int expiresIn = 3600,
  }) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaMulticardMdoAssegnazioniBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadBytes(
    MulticardMdoAssegnazioneFile row,
  ) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaMulticardMdoAssegnazioniBucket)
        .download(path);
  }
}
