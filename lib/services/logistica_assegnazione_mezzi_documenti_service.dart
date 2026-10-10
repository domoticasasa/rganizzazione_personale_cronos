import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

const String kLogisticaAssegnazioneMezziDocumentiBucket =
    'logistica_assegnazione_mezzi_stradali_documenti';

class MezzoStradaleRef {
  const MezzoStradaleRef({
    required this.id,
    required this.targa,
    required this.marca,
    required this.modello,
    required this.tipologia,
    required this.assegnatario,
    this.numerazione,
  });

  final String id;
  final String targa;
  final String marca;
  final String modello;
  final String tipologia;
  final String assegnatario;
  final int? numerazione;

  String get label {
    final parts = <String>[
      if (targa.isNotEmpty) targa,
      if (marca.isNotEmpty || modello.isNotEmpty)
        [marca, modello].where((s) => s.isNotEmpty).join(' '),
    ];
    if (parts.isEmpty) {
      return numerazione != null ? 'Mezzo n. $numerazione' : 'Mezzo';
    }
    return parts.join(' · ');
  }

  String get subtitle {
    final parts = <String>[
      if (tipologia.isNotEmpty) tipologia,
      if (assegnatario.isNotEmpty) 'Assegnatario: $assegnatario',
      if (assegnatario.isEmpty) 'Non assegnato',
    ];
    return parts.join(' · ');
  }

  factory MezzoStradaleRef.fromMap(Map<String, dynamic> m) {
    final numRaw = m['numerazione'];
    int? numerazione;
    if (numRaw is int) {
      numerazione = numRaw;
    } else {
      numerazione = int.tryParse((numRaw ?? '').toString());
    }
    return MezzoStradaleRef(
      id: (m['id_uuid'] ?? '').toString().trim(),
      targa: (m['targa'] ?? '').toString().trim(),
      marca: (m['marca'] ?? '').toString().trim(),
      modello: (m['modello'] ?? '').toString().trim(),
      tipologia: (m['tipologia_mezzo'] ?? '').toString().trim(),
      assegnatario: (m['assegnatario_attuale'] ?? '').toString().trim(),
      numerazione: numerazione,
    );
  }
}

class AssegnazioneMezzoDocumento {
  const AssegnazioneMezzoDocumento({
    required this.id,
    required this.mezzoId,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.note,
    required this.uploadedAt,
    this.uploadedByUserUuid,
  });

  final String id;
  final String mezzoId;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final String? note;
  final DateTime uploadedAt;
  final String? uploadedByUserUuid;

  factory AssegnazioneMezzoDocumento.fromMap(Map<String, dynamic> m) {
    return AssegnazioneMezzoDocumento(
      id: (m['id'] ?? '').toString(),
      mezzoId: (m['mezzo_id'] ?? '').toString(),
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

class LogisticaAssegnazioneMezziDocumentiService {
  LogisticaAssegnazioneMezziDocumentiService._();

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
    if (stem.isEmpty) stem = 'assegnazione';
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

  static Future<List<MezzoStradaleRef>> listMezzi() async {
    final res = await _supa
        .from('logistica_mezzi_stradali')
        .select(
          'id_uuid,numerazione,targa,marca,modello,tipologia_mezzo,'
          'assegnatario_attuale',
        )
        .order('numerazione', ascending: true);
    return [
      for (final raw in (res as List))
        MezzoStradaleRef.fromMap(Map<String, dynamic>.from(raw as Map)),
    ].where((m) => m.id.isNotEmpty).toList(growable: false);
  }

  static Future<List<AssegnazioneMezzoDocumento>> listForMezzo(
    String mezzoId,
  ) async {
    final res = await _supa
        .from('logistica_assegnazione_mezzi_stradali_documenti')
        .select()
        .eq('mezzo_id', mezzoId)
        .order('uploaded_at', ascending: false);
    return [
      for (final raw in (res as List))
        AssegnazioneMezzoDocumento.fromMap(
          Map<String, dynamic>.from(raw as Map),
        ),
    ];
  }

  static Future<Map<String, int>> countByMezzo() async {
    final res = await _supa
        .from('logistica_assegnazione_mezzi_stradali_documenti')
        .select('mezzo_id');
    final out = <String, int>{};
    for (final raw in (res as List)) {
      final id =
          (Map<String, dynamic>.from(raw as Map)['mezzo_id'] ?? '').toString();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  static Future<AssegnazioneMezzoDocumento> upload({
    required String mezzoId,
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
        .from('logistica_assegnazione_mezzi_stradali_documenti')
        .insert({
          'mezzo_id': mezzoId,
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
    final path = '$mezzoId/$id/$safeName';
    try {
      await _supa.storage
          .from(kLogisticaAssegnazioneMezziDocumentiBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
      final updated = await _supa
          .from('logistica_assegnazione_mezzi_stradali_documenti')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return AssegnazioneMezzoDocumento.fromMap(
        Map<String, dynamic>.from(updated),
      );
    } catch (e) {
      try {
        await _supa
            .from('logistica_assegnazione_mezzi_stradali_documenti')
            .delete()
            .eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> delete(AssegnazioneMezzoDocumento row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage
            .from(kLogisticaAssegnazioneMezziDocumentiBucket)
            .remove([path]);
      } catch (_) {}
    }
    await _supa
        .from('logistica_assegnazione_mezzi_stradali_documenti')
        .delete()
        .eq('id', row.id);
  }

  static Future<String> signedUrl(
    AssegnazioneMezzoDocumento row, {
    int expiresIn = 3600,
  }) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaAssegnazioneMezziDocumentiBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadBytes(AssegnazioneMezzoDocumento row) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaAssegnazioneMezziDocumentiBucket)
        .download(path);
  }
}
