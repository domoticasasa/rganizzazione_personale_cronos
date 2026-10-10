import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

const String kLogisticaMdoDocumentiBucket = 'logistica_mdo_documenti';

class MdoDocumentoTipo {
  const MdoDocumentoTipo({
    required this.key,
    required this.label,
    this.description,
  });

  final String key;
  final String label;
  final String? description;
}

const String kMdoDocTipoAltro = 'altro';

/// Tipi documento per mezzo ferroviario (ordine di visualizzazione).
const List<MdoDocumentoTipo> kMdoDocumentoTipi = <MdoDocumentoTipo>[
  MdoDocumentoTipo(key: 'cdc_allegato_j', label: 'CDC (Allegato J)'),
  MdoDocumentoTipo(
    key: 'libro_bordo_allegato_l',
    label: 'Libro di Bordo (Allegato L)',
  ),
  MdoDocumentoTipo(
    key: 'diario_manutenzione_allegato_k',
    label: 'Diario di Manutenzione (Allegato K)',
  ),
  MdoDocumentoTipo(
    key: 'targa_identificativa',
    label: 'Targa Identificativa',
  ),
  MdoDocumentoTipo(key: 'certificato_va', label: 'Certificato VA'),
  MdoDocumentoTipo(
    key: 'verifica_quinquennale_allegato_p',
    label: 'Allegato P',
  ),
  MdoDocumentoTipo(key: 'mum', label: 'MUM'),
  MdoDocumentoTipo(key: 'inail_terrazzino', label: 'Inail Terrazzino'),
  MdoDocumentoTipo(key: 'inail_gru', label: 'Inail GRU'),
  MdoDocumentoTipo(key: 'inail_cestello', label: 'Inail Cestello'),
  MdoDocumentoTipo(
    key: 'verifica_strutturale_gru',
    label: 'Verifica Strutturale GRU',
  ),
];

class MdoFerroviarioRef {
  const MdoFerroviarioRef({
    required this.id,
    required this.matricolaInterna,
    required this.targaRfi,
    required this.descrizione,
    required this.modello,
  });

  final String id;
  final String matricolaInterna;
  final String targaRfi;
  final String descrizione;
  final String modello;

  String get title {
    if (matricolaInterna.isNotEmpty) return matricolaInterna;
    if (targaRfi.isNotEmpty) return targaRfi;
    if (descrizione.isNotEmpty) return descrizione;
    return 'Mezzo';
  }

  String get subtitle {
    final parts = <String>[
      if (targaRfi.isNotEmpty && targaRfi != title) 'Targa RFI: $targaRfi',
      if (descrizione.isNotEmpty) descrizione,
      if (modello.isNotEmpty) modello,
    ];
    return parts.join(' · ');
  }

  factory MdoFerroviarioRef.fromMap(Map<String, dynamic> m) {
    return MdoFerroviarioRef(
      id: (m['id_uuid'] ?? '').toString().trim(),
      matricolaInterna: (m['matricola_interna'] ?? '').toString().trim(),
      targaRfi:
          (m['codice_identificativo_targa_rfi'] ?? '').toString().trim(),
      descrizione: (m['descrizione_mezzo'] ?? '').toString().trim(),
      modello: (m['modello'] ?? '').toString().trim(),
    );
  }
}

class MdoDocumentoFile {
  const MdoDocumentoFile({
    required this.id,
    required this.mdoId,
    required this.docTipo,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.note,
    this.customTitolo,
    this.customDescrizione,
    required this.uploadedAt,
    this.uploadedByUserUuid,
  });

  final String id;
  final String mdoId;
  final String docTipo;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final String? note;
  final String? customTitolo;
  final String? customDescrizione;
  final DateTime uploadedAt;
  final String? uploadedByUserUuid;

  bool get isAltro => docTipo == kMdoDocTipoAltro;

  factory MdoDocumentoFile.fromMap(Map<String, dynamic> m) {
    return MdoDocumentoFile(
      id: (m['id'] ?? '').toString(),
      mdoId: (m['mdo_id'] ?? '').toString(),
      docTipo: (m['doc_tipo'] ?? '').toString(),
      filePath: (m['file_path'] ?? '').toString(),
      fileName: (m['file_name'] ?? '').toString(),
      mimeType: (m['mime_type'] as String?)?.trim(),
      fileSize: m['file_size'] is num ? (m['file_size'] as num).toInt() : null,
      note: (m['note'] as String?)?.trim(),
      customTitolo: (m['custom_titolo'] as String?)?.trim(),
      customDescrizione: (m['custom_descrizione'] as String?)?.trim(),
      uploadedAt: DateTime.tryParse((m['uploaded_at'] ?? '').toString())
              ?.toLocal() ??
          DateTime.now(),
      uploadedByUserUuid:
          (m['uploaded_by_user_uuid'] as String?)?.trim(),
    );
  }
}

class LogisticaMdoDocumentiService {
  LogisticaMdoDocumentiService._();

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

  static String _sanitizeFileName(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final dot = trimmed.lastIndexOf('.');
    var stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    var ext = dot > 0 ? trimmed.substring(dot).toLowerCase() : '';
    stem = stem.replaceAll(RegExp(r'\s+'), '_');
    stem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    stem = stem.replaceAll(RegExp(r'_+'), '_');
    stem = stem.replaceAll(RegExp(r'^_+|_+$'), '');
    if (stem.isEmpty) stem = 'documento';
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

  static Future<List<MdoFerroviarioRef>> listMezzi() async {
    final res = await _supa
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid, matricola_interna, codice_identificativo_targa_rfi, '
          'descrizione_mezzo, modello',
        )
        .order('matricola_interna', ascending: true);
    return [
      for (final raw in (res as List))
        MdoFerroviarioRef.fromMap(Map<String, dynamic>.from(raw as Map)),
    ].where((m) => m.id.isNotEmpty).toList();
  }

  static Future<List<MdoDocumentoFile>> listDocumenti(String mdoId) async {
    final res = await _supa
        .from('logistica_mdo_documenti')
        .select()
        .eq('mdo_id', mdoId)
        .order('uploaded_at', ascending: false);
    return [
      for (final raw in (res as List))
        MdoDocumentoFile.fromMap(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  static Future<Map<String, int>> countByMezzo() async {
    final res = await _supa.from('logistica_mdo_documenti').select('mdo_id');
    final out = <String, int>{};
    for (final raw in (res as List)) {
      final id = (Map<String, dynamic>.from(raw as Map)['mdo_id'] ?? '')
          .toString();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  static Future<MdoDocumentoFile> upload({
    required String mdoId,
    required String docTipo,
    required String originalFileName,
    required String? mimeType,
    required Uint8List bytes,
    String? note,
    String? customTitolo,
    String? customDescrizione,
  }) async {
    if (bytes.isEmpty) throw StateError('File vuoto');
    if (bytes.length > maxFileBytes) {
      throw StateError('Il file supera i 200 MB');
    }
    if (!isAllowedFileName(originalFileName)) {
      throw StateError('Formato non supportato. Usa PDF, JPG, PNG o WEBP.');
    }
    if (!kMdoDocumentoTipi.any((t) => t.key == docTipo) &&
        docTipo != kMdoDocTipoAltro) {
      throw StateError('Tipo documento non valido');
    }
    final titoloAltro = (customTitolo ?? '').trim();
    if (docTipo == kMdoDocTipoAltro && titoloAltro.isEmpty) {
      throw StateError('Inserisci il nome del documento');
    }

    final mime = mimeForFileName(originalFileName, mimeType);
    final displayName =
        originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizeFileName(originalFileName);
    final uploadedBy = await _currentUserUuid();
    final inserted = await _supa
        .from('logistica_mdo_documenti')
        .insert({
          'mdo_id': mdoId,
          'doc_tipo': docTipo,
          'file_path': 'pending',
          'file_name': displayName.isEmpty ? safeName : displayName,
          'mime_type': mime,
          'file_size': bytes.length,
          'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
          'custom_titolo': docTipo == kMdoDocTipoAltro ? titoloAltro : null,
          'custom_descrizione': docTipo == kMdoDocTipoAltro
              ? (((customDescrizione ?? '').trim().isEmpty)
                  ? null
                  : customDescrizione!.trim())
              : null,
          'uploaded_by_user_uuid': uploadedBy,
        })
        .select()
        .single();
    final id = (inserted['id'] ?? '').toString();
    final path = '$mdoId/$docTipo/$id/$safeName';
    try {
      await _supa.storage.from(kLogisticaMdoDocumentiBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final updated = await _supa
          .from('logistica_mdo_documenti')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return MdoDocumentoFile.fromMap(Map<String, dynamic>.from(updated));
    } catch (e) {
      try {
        await _supa.from('logistica_mdo_documenti').delete().eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> delete(MdoDocumentoFile row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage.from(kLogisticaMdoDocumentiBucket).remove([path]);
      } catch (_) {}
    }
    await _supa.from('logistica_mdo_documenti').delete().eq('id', row.id);
  }

  static Future<String> signedUrl(
    MdoDocumentoFile row, {
    int expiresIn = 3600,
  }) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage
        .from(kLogisticaMdoDocumentiBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadBytes(MdoDocumentoFile row) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage.from(kLogisticaMdoDocumentiBucket).download(path);
  }
}
