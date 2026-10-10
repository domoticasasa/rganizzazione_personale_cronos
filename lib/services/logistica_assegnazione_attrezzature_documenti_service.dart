import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

const String kLogisticaAssegnazioneAttrezzatureDocumentiBucket =
    'logistica_assegnazione_attrezzature_documenti';

class AttrezzaturaRef {
  const AttrezzaturaRef({
    required this.id,
    required this.codiceCronos,
    required this.descrizione,
    required this.assegnatario,
    required this.marca,
    required this.modello,
  });

  final String id;
  final String codiceCronos;
  final String descrizione;
  final String assegnatario;
  final String marca;
  final String modello;

  String get label {
    final parts = <String>[
      if (codiceCronos.isNotEmpty) codiceCronos,
      if (descrizione.isNotEmpty) descrizione,
      if (marca.isNotEmpty || modello.isNotEmpty)
        [marca, modello].where((s) => s.isNotEmpty).join(' '),
    ];
    if (parts.isEmpty) return 'Attrezzatura';
    return parts.join(' · ');
  }

  String get subtitle {
    if (assegnatario.isEmpty) return 'Senza assegnatario';
    return 'Assegnatario: $assegnatario';
  }

  factory AttrezzaturaRef.fromMap(Map<String, dynamic> m) {
    return AttrezzaturaRef(
      id: (m['id_uuid'] ?? '').toString().trim(),
      codiceCronos: (m['codice_cronos'] ?? '').toString().trim(),
      descrizione: (m['descrizione_articolo'] ?? '').toString().trim(),
      assegnatario: (m['assegnatario'] ?? '').toString().trim(),
      marca: (m['marca'] ?? '').toString().trim(),
      modello: (m['modello'] ?? '').toString().trim(),
    );
  }
}

class AssegnazioneAttrezzaturaDocumento {
  const AssegnazioneAttrezzaturaDocumento({
    required this.id,
    required this.titolo,
    this.attrezzaturaId,
    this.attrezzaturaLabel,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.note,
    required this.uploadedAt,
    this.uploadedByUserUuid,
  });

  final String id;
  final String titolo;
  final String? attrezzaturaId;
  final String? attrezzaturaLabel;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final String? note;
  final DateTime uploadedAt;
  final String? uploadedByUserUuid;

  String get displayTitle {
    final att = (attrezzaturaLabel ?? '').trim();
    if (att.isNotEmpty) return att;
    final t = titolo.trim();
    if (t.isNotEmpty) return t;
    return fileName.trim().isEmpty ? 'PDF' : fileName.trim();
  }

  factory AssegnazioneAttrezzaturaDocumento.fromMap(Map<String, dynamic> m) {
    String? attLabel;
    final nested = m['logistica_attrezzature'];
    if (nested is Map) {
      final ref = AttrezzaturaRef.fromMap(Map<String, dynamic>.from(nested));
      attLabel = ref.label;
    }
    return AssegnazioneAttrezzaturaDocumento(
      id: (m['id'] ?? '').toString(),
      titolo: (m['titolo'] ?? '').toString(),
      attrezzaturaId: (m['attrezzatura_id'] ?? '').toString().trim().isEmpty
          ? null
          : (m['attrezzatura_id'] ?? '').toString().trim(),
      attrezzaturaLabel: attLabel,
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

class LogisticaAssegnazioneAttrezzatureDocumentiService {
  LogisticaAssegnazioneAttrezzatureDocumentiService._();

  static const int maxFileBytes = 50 * 1024 * 1024;

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
    if (stem.isEmpty) stem = 'assegnazione_attrezzature';
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

  static Future<List<AttrezzaturaRef>> listAttrezzature() async {
    final res = await _supa
        .from('logistica_attrezzature')
        .select(
          'id_uuid,codice_cronos,descrizione_articolo,assegnatario,marca,modello',
        )
        .eq('active', true)
        .order('codice_cronos', ascending: true);
    return [
      for (final raw in (res as List))
        AttrezzaturaRef.fromMap(Map<String, dynamic>.from(raw as Map)),
    ].where((a) => a.id.isNotEmpty).toList(growable: false);
  }

  static List<AssegnazioneAttrezzaturaDocumento> _mapDocs(List res) {
    return [
      for (final raw in res)
        AssegnazioneAttrezzaturaDocumento.fromMap(
          Map<String, dynamic>.from(raw as Map),
        ),
    ];
  }

  static Future<List<AssegnazioneAttrezzaturaDocumento>> listAll() async {
    try {
      final res = await _supa
          .from('logistica_assegnazione_attrezzature_documenti')
          .select(
            '*, logistica_attrezzature('
            'id_uuid,codice_cronos,descrizione_articolo,assegnatario,marca,modello'
            ')',
          )
          .order('uploaded_at', ascending: false);
      return _mapDocs(res as List);
    } catch (_) {
      final res = await _supa
          .from('logistica_assegnazione_attrezzature_documenti')
          .select()
          .order('uploaded_at', ascending: false);
      return _mapDocs(res as List);
    }
  }

  static Future<List<AssegnazioneAttrezzaturaDocumento>> listForAttrezzatura(
    String attrezzaturaId,
  ) async {
    final id = attrezzaturaId.trim();
    if (id.isEmpty) return const [];
    final res = await _supa
        .from('logistica_assegnazione_attrezzature_documenti')
        .select()
        .eq('attrezzatura_id', id)
        .order('uploaded_at', ascending: false);
    return _mapDocs(res as List);
  }

  static Future<Map<String, int>> countByAttrezzatura() async {
    final res = await _supa
        .from('logistica_assegnazione_attrezzature_documenti')
        .select('attrezzatura_id');
    final out = <String, int>{};
    for (final raw in (res as List)) {
      final id = (Map<String, dynamic>.from(raw as Map)['attrezzatura_id'] ??
              '')
          .toString()
          .trim();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  static Future<AssegnazioneAttrezzaturaDocumento> upload({
    required String originalFileName,
    required Uint8List bytes,
    required String attrezzaturaId,
    required String attrezzaturaLabel,
    String? note,
  }) async {
    if (bytes.isEmpty) throw StateError('File vuoto');
    if (bytes.length > maxFileBytes) {
      throw StateError('Il PDF supera i 50 MB');
    }
    if (!isAllowedFileName(originalFileName)) {
      throw StateError('Formato non supportato. Carica un PDF.');
    }
    final attId = attrezzaturaId.trim();
    if (attId.isEmpty) {
      throw StateError('Seleziona un’attrezzatura dalla lista.');
    }

    final displayName =
        originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizeFileName(originalFileName);
    final uploadedBy = await _currentUserUuid();
    final title = attrezzaturaLabel.trim().isEmpty
        ? (displayName.isEmpty ? safeName : displayName)
        : attrezzaturaLabel.trim();

    final inserted = await _supa
        .from('logistica_assegnazione_attrezzature_documenti')
        .insert({
          'titolo': title,
          'attrezzatura_id': attId,
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
    final path = '$attId/$id/$safeName';
    try {
      await _supa.storage
          .from(kLogisticaAssegnazioneAttrezzatureDocumentiBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
      final updated = await _supa
          .from('logistica_assegnazione_attrezzature_documenti')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return AssegnazioneAttrezzaturaDocumento.fromMap(
        Map<String, dynamic>.from(updated),
      );
    } catch (e) {
      try {
        await _supa
            .from('logistica_assegnazione_attrezzature_documenti')
            .delete()
            .eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> delete(AssegnazioneAttrezzaturaDocumento row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage
            .from(kLogisticaAssegnazioneAttrezzatureDocumentiBucket)
            .remove([path]);
      } catch (_) {}
    }
    await _supa
        .from('logistica_assegnazione_attrezzature_documenti')
        .delete()
        .eq('id', row.id);
  }

  static Future<String> signedUrl(
    AssegnazioneAttrezzaturaDocumento row, {
    int expiresIn = 3600,
  }) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaAssegnazioneAttrezzatureDocumentiBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadBytes(
    AssegnazioneAttrezzaturaDocumento row,
  ) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaAssegnazioneAttrezzatureDocumentiBucket)
        .download(path);
  }
}
