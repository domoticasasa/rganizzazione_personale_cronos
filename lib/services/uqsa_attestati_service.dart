import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import '../utils/users_directory.dart';

const String kUqsaAttestatiBucket = 'uqsa_attestati';

const String kUqsaAttestatoTipoRfi = 'rfi';
const String kUqsaAttestatoTipoL81 = 'l81';

/// Corsi canonici D.Lgs. 81/08 (stessa anagrafica della pagina Formazione).
const List<String> kUqsaCorsiDlgs81 = <String>[
  'ASR ART.37 RISCHIO ALTO',
  'ANTINCENDIO',
  'ATTESTATO VVF',
  'PREPOSTO',
  'PRIMO SOCCORSO',
  'PES PAV PEI',
  'DPI III',
  'PLE',
  'O.M.S. TERNE ESCAVATORI',
  'SEGNALETICA STRADALE',
  'GRU SU AUTOCARRO',
  'CARRELLI SEMOVENTI',
  'BOBCAT',
  'CARRELLI ELEVATORI',
  'RLS',
  'FIBRA',
];

class UqsaCorsoFormazione {
  const UqsaCorsoFormazione({
    required this.nome,
    this.scadenzaDipendente,
    this.delDipendente = false,
  });

  final String nome;
  final DateTime? scadenzaDipendente;
  final bool delDipendente;
}

class UqsaAttestato {
  const UqsaAttestato({
    required this.id,
    required this.personaleId,
    required this.tipo,
    required this.titolo,
    required this.filePath,
    required this.fileName,
    this.mimeType,
    this.fileSize,
    this.dataScadenza,
    required this.uploadedAt,
    this.uploadedByUserId,
  });

  final String id;
  final String personaleId;
  final String tipo;
  final String titolo;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? fileSize;
  final DateTime? dataScadenza;
  final DateTime uploadedAt;
  final int? uploadedByUserId;

  bool get isRfi => tipo == kUqsaAttestatoTipoRfi;
  bool get isL81 => tipo == kUqsaAttestatoTipoL81;

  bool get isImage {
    final m = (mimeType ?? '').toLowerCase();
    final n = fileName.toLowerCase();
    return m.startsWith('image/') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp');
  }

  bool get isPdf {
    final m = (mimeType ?? '').toLowerCase();
    return m.contains('pdf') || fileName.toLowerCase().endsWith('.pdf');
  }

  factory UqsaAttestato.fromMap(Map<String, dynamic> m) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return DateTime(v.year, v.month, v.day);
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      final d = DateTime.tryParse(s);
      if (d == null) return null;
      return DateTime(d.year, d.month, d.day);
    }

    DateTime parseTs(dynamic v) {
      if (v is DateTime) return v.toUtc();
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return DateTime.now().toUtc();
      final normalized = s.contains('T') && !s.endsWith('Z') && !s.contains('+')
          ? '${s}Z'
          : s;
      return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.now().toUtc();
    }

    return UqsaAttestato(
      id: (m['id'] ?? '').toString(),
      personaleId: (m['personale_id'] ?? '').toString(),
      tipo: (m['tipo'] ?? '').toString(),
      titolo: (m['titolo'] ?? '').toString(),
      filePath: (m['file_path'] ?? '').toString(),
      fileName: (m['file_name'] ?? '').toString(),
      mimeType: (m['mime_type'] as String?)?.trim(),
      fileSize: (m['file_size'] as num?)?.toInt(),
      dataScadenza: parseDate(m['data_scadenza']),
      uploadedAt: parseTs(m['uploaded_at'] ?? m['created_at']),
      uploadedByUserId: (m['uploaded_by_user_id'] as num?)?.toInt(),
    );
  }
}

class UqsaAttestatiService {
  UqsaAttestatiService._();

  static const int maxFileBytes = 20 * 1024 * 1024;
  static const Set<String> allowedExtensions = <String>{
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  static SupabaseClient get _supa => SupabaseService.client;

  static String tipoLabel(String tipo) {
    switch (tipo) {
      case kUqsaAttestatoTipoRfi:
        return 'RFI';
      case kUqsaAttestatoTipoL81:
        return 'D.Lgs. 81/08';
      default:
        return tipo.toUpperCase();
    }
  }

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

  /// Nome file per Storage: niente spazi né caratteri speciali
  /// (Supabase rifiuta la chiave con `InvalidKey` / 400).
  static String _sanitizeFileName(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final dot = trimmed.lastIndexOf('.');
    var stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    var ext = dot > 0 ? trimmed.substring(dot).toLowerCase() : '';
    stem = stem.replaceAll(RegExp(r'\s+'), '_');
    stem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    stem = stem.replaceAll(RegExp(r'_+'), '_');
    stem = stem.replaceAll(RegExp(r'^_+|_+$'), '');
    if (stem.isEmpty) stem = 'attestato';
    if (stem.length > 80) stem = stem.substring(stem.length - 80);
    if (ext.isEmpty || !RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(ext)) {
      ext = '.bin';
    }
    return '$stem$ext';
  }

  static Future<int?> _currentUsersId() async {
    final authId = _supa.auth.currentUser?.id;
    if (authId == null) return null;
    final row = await _supa
        .from('users')
        .select('id')
        .eq('auth_id', authId)
        .maybeSingle();
    return (row?['id'] as num?)?.toInt();
  }

  static Future<List<Map<String, dynamic>>> loadPersonale() async {
    List rows;
    try {
      rows = await _supa
          .from('personale')
          .select(
            'id, id_uuid, full_name, matricola, active, email, user_id, '
            'hidden_from_directory',
          )
          .order('full_name', ascending: true) as List;
    } catch (_) {
      rows = await _supa
          .from('personale')
          .select('id, id_uuid, full_name, matricola, active, email, user_id')
          .order('full_name', ascending: true) as List;
    }
    final list = await UsersDirectory.visiblePersonale(rows);
    return list
        .where((p) => (p['id_uuid'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  static String _normCorsoKey(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_./\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _pidIsOwn(
    String owner,
    String personaleUuid,
    int? personaleId,
  ) {
    final o = owner.trim();
    if (o.isEmpty) return false;
    if (personaleUuid.isNotEmpty && o == personaleUuid) return true;
    if (personaleId != null && o == personaleId.toString()) return true;
    return false;
  }

  static Future<int?> _resolvePersonaleIntId({
    required String personaleUuid,
    int? personaleId,
  }) async {
    if (personaleId != null) return personaleId;
    if (personaleUuid.isEmpty) return null;
    try {
      final row = await _supa
          .from('personale')
          .select('id')
          .eq('id_uuid', personaleUuid)
          .maybeSingle();
      return (row?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static bool _isRfiScadenzaField(String field) {
    final n = field.toLowerCase().replaceAll('_', ' ').trim();
    if (n.contains('mantenimento 2') || n.contains('mantenimento 3')) {
      return false;
    }
    return n.contains('scadenza');
  }

  static int _rfiScadenzaPriority(String field) {
    final n = field.toLowerCase().replaceAll('_', ' ').trim();
    if (n.contains('prossima') && n.contains('scadenza')) return 0;
    if (n == 'scadenza' || n.startsWith('scadenza ')) return 1;
    if (n.contains('rinnovo')) return 2;
    return 3;
  }

  /// Elenco corsi da Formazione RFI o D.Lgs. 81/08.
  /// I corsi già assegnati al dipendente vengono prima e possono portare la scadenza.
  static Future<List<UqsaCorsoFormazione>> loadCorsiFormazione({
    required String tipo,
    required String personaleUuid,
    int? personaleId,
  }) async {
    if (tipo == kUqsaAttestatoTipoL81) {
      return _loadCorsiDlgs81(personaleUuid);
    }
    return _loadCorsiRfi(
      personaleUuid: personaleUuid,
      personaleId: personaleId,
    );
  }

  /// Solo i corsi già presenti in Formazione per quel dipendente (riepilogo).
  static Future<List<UqsaCorsoFormazione>> loadCorsiAssegnati({
    required String tipo,
    required String personaleUuid,
    int? personaleId,
  }) async {
    if (tipo == kUqsaAttestatoTipoL81) {
      final all = await _loadCorsiDlgs81(personaleUuid);
      return all.where((c) => c.delDipendente).toList();
    }
    return _loadCorsiRfiAssegnati(
      personaleUuid: personaleUuid,
      personaleId: personaleId,
    );
  }

  static Future<List<UqsaCorsoFormazione>> _loadCorsiDlgs81(
    String personaleUuid,
  ) async {
    final rows = await _supa
        .from('formazione_corsi')
        .select('corso, personale_id, scadenza_attestato');
    final byName = <String, UqsaCorsoFormazione>{};
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final nome = (m['corso'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final isOwn = _pidIsOwn(
        (m['personale_id'] ?? '').toString(),
        personaleUuid,
        null,
      );
      final scad = _parseDate(m['scadenza_attestato']);
      final prev = byName[nome];
      if (prev == null) {
        byName[nome] = UqsaCorsoFormazione(
          nome: nome,
          scadenzaDipendente: isOwn ? scad : null,
          delDipendente: isOwn,
        );
        continue;
      }
      if (isOwn && (!prev.delDipendente || prev.scadenzaDipendente == null)) {
        byName[nome] = UqsaCorsoFormazione(
          nome: nome,
          scadenzaDipendente: scad ?? prev.scadenzaDipendente,
          delDipendente: true,
        );
      }
    }
    for (final nome in kUqsaCorsiDlgs81) {
      byName.putIfAbsent(nome, () => UqsaCorsoFormazione(nome: nome));
    }
    return _sortCorsi(byName.values, kUqsaCorsiDlgs81);
  }

  static Future<List<UqsaCorsoFormazione>> _loadCorsiRfi({
    required String personaleUuid,
    int? personaleId,
  }) async {
    final assigned = await _loadCorsiRfiAssegnati(
      personaleUuid: personaleUuid,
      personaleId: personaleId,
    );
    final byNorm = <String, UqsaCorsoFormazione>{};
    for (final c in assigned) {
      byNorm[_normCorsoKey(c.nome)] = c;
    }
    try {
      final catalog =
          await _supa.from('formazione_rfi_records').select('track_key');
      for (final raw in catalog as List) {
        final nome = (raw['track_key'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        byNorm.putIfAbsent(
          _normCorsoKey(nome),
          () => UqsaCorsoFormazione(nome: nome),
        );
      }
    } catch (_) {}
    try {
      final corsi = await _supa.from('formazione_rfi_corsi').select('corso');
      for (final raw in corsi as List) {
        final nome = (raw['corso'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        byNorm.putIfAbsent(
          _normCorsoKey(nome),
          () => UqsaCorsoFormazione(nome: nome),
        );
      }
    } catch (_) {}
    return _sortCorsi(byNorm.values, const <String>[]);
  }

  static Future<List<UqsaCorsoFormazione>> _loadCorsiRfiAssegnati({
    required String personaleUuid,
    int? personaleId,
  }) async {
    final pid = await _resolvePersonaleIntId(
      personaleUuid: personaleUuid,
      personaleId: personaleId,
    );
    final byNorm = <String, UqsaCorsoFormazione>{};

    void put(String nome, {DateTime? scad, bool preferName = false}) {
      final n = nome.trim();
      if (n.isEmpty) return;
      final k = _normCorsoKey(n);
      final prev = byNorm[k];
      if (prev == null) {
        byNorm[k] = UqsaCorsoFormazione(
          nome: n,
          scadenzaDipendente: scad,
          delDipendente: true,
        );
        return;
      }
      byNorm[k] = UqsaCorsoFormazione(
        nome: preferName ? n : prev.nome,
        scadenzaDipendente: prev.scadenzaDipendente ?? scad,
        delDipendente: true,
      );
    }

    try {
      final corsi = await _supa
          .from('formazione_rfi_corsi')
          .select('corso, personale_id, scadenza_attestato');
      for (final raw in corsi as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (!_pidIsOwn(
          (m['personale_id'] ?? '').toString(),
          personaleUuid,
          pid,
        )) {
          continue;
        }
        put(
          (m['corso'] ?? '').toString(),
          scad: _parseDate(m['scadenza_attestato']),
        );
      }
    } catch (_) {}

    if (pid != null) {
      try {
        final own = await _supa
            .from('formazione_rfi_records')
            .select('track_key, field_key, value_date')
            .eq('personale_id', pid);
        final bestScad = <String, ({int prio, DateTime date})>{};
        for (final raw in own as List) {
          final m = Map<String, dynamic>.from(raw as Map);
          final nome = (m['track_key'] ?? '').toString().trim();
          if (nome.isEmpty) continue;
          put(nome, preferName: true);
          if (!_isRfiScadenzaField((m['field_key'] ?? '').toString())) continue;
          final d = _parseDate(m['value_date']);
          if (d == null) continue;
          final prio = _rfiScadenzaPriority((m['field_key'] ?? '').toString());
          final cur = bestScad[_normCorsoKey(nome)];
          if (cur == null || prio < cur.prio) {
            bestScad[_normCorsoKey(nome)] = (prio: prio, date: d);
          }
        }
        for (final e in bestScad.entries) {
          final prev = byNorm[e.key];
          if (prev == null) continue;
          byNorm[e.key] = UqsaCorsoFormazione(
            nome: prev.nome,
            scadenzaDipendente: prev.scadenzaDipendente ?? e.value.date,
            delDipendente: true,
          );
        }
      } catch (_) {}
    }

    return _sortCorsi(byNorm.values, const <String>[]);
  }

  static List<UqsaCorsoFormazione> _sortCorsi(
    Iterable<UqsaCorsoFormazione> values,
    List<String> canonical,
  ) {
    final list = values.toList();
    int canonIdx(String n) {
      final i = canonical.indexOf(n);
      return i < 0 ? canonical.length + 1 : i;
    }

    list.sort((a, b) {
      if (a.delDipendente != b.delDipendente) {
        return a.delDipendente ? -1 : 1;
      }
      final ca = canonIdx(a.nome);
      final cb = canonIdx(b.nome);
      if (ca != cb) return ca.compareTo(cb);
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
    return list;
  }

  static Future<List<UqsaAttestato>> loadAll() async {
    final rows = await _supa
        .from('uqsa_attestati')
        .select(
          'id, personale_id, tipo, titolo, file_path, file_name, mime_type, '
          'file_size, data_scadenza, uploaded_at, uploaded_by_user_id',
        )
        .order('uploaded_at', ascending: false);
    return (rows as List)
        .map((e) => UqsaAttestato.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Attestati del dipendente (RFI + D.Lgs. 81/08). RLS limita comunque ai propri.
  static Future<List<UqsaAttestato>> loadForPersonale(String personaleUuid) async {
    final pid = personaleUuid.trim();
    if (pid.isEmpty) return const <UqsaAttestato>[];
    final rows = await _supa
        .from('uqsa_attestati')
        .select(
          'id, personale_id, tipo, titolo, file_path, file_name, mime_type, '
          'file_size, data_scadenza, uploaded_at, uploaded_by_user_id',
        )
        .eq('personale_id', pid)
        .order('uploaded_at', ascending: false);
    return (rows as List)
        .map((e) => UqsaAttestato.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<UqsaAttestato> upload({
    required String personaleId,
    required String tipo,
    required String titolo,
    required DateTime? dataScadenza,
    required String originalFileName,
    required String? mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw StateError('File vuoto');
    if (bytes.length > maxFileBytes) {
      throw StateError('Il file supera i 20 MB');
    }
    if (!isAllowedFileName(originalFileName)) {
      throw StateError('Formato non supportato. Usa PDF, JPG, PNG o WEBP.');
    }
    final title = titolo.trim();
    if (title.isEmpty) throw StateError('Inserisci il titolo dell\'attestato');
    if (tipo != kUqsaAttestatoTipoRfi && tipo != kUqsaAttestatoTipoL81) {
      throw StateError('Tipo attestato non valido');
    }

    final mime = mimeForFileName(originalFileName, mimeType);
    final displayName = originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizeFileName(originalFileName);
    final uploadedBy = await _currentUsersId();
    final inserted = await _supa
        .from('uqsa_attestati')
        .insert({
          'personale_id': personaleId,
          'tipo': tipo,
          'titolo': title,
          'file_path': 'pending',
          'file_name': displayName.isEmpty ? safeName : displayName,
          'mime_type': mime,
          'file_size': bytes.length,
          'data_scadenza': dataScadenza == null
              ? null
              : '${dataScadenza.year.toString().padLeft(4, '0')}-'
                  '${dataScadenza.month.toString().padLeft(2, '0')}-'
                  '${dataScadenza.day.toString().padLeft(2, '0')}',
          'uploaded_by_user_id': uploadedBy,
        })
        .select()
        .single();
    final id = (inserted['id'] ?? '').toString();
    final path = '$personaleId/$id/$safeName';
    try {
      await _supa.storage.from(kUqsaAttestatiBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      final updated = await _supa
          .from('uqsa_attestati')
          .update({'file_path': path})
          .eq('id', id)
          .select()
          .single();
      return UqsaAttestato.fromMap(Map<String, dynamic>.from(updated));
    } catch (e) {
      try {
        await _supa.from('uqsa_attestati').delete().eq('id', id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> updateMeta({
    required String id,
    required String titolo,
    required DateTime? dataScadenza,
  }) async {
    final title = titolo.trim();
    if (title.isEmpty) throw StateError('Inserisci il titolo dell\'attestato');
    await _supa.from('uqsa_attestati').update({
      'titolo': title,
      'data_scadenza': dataScadenza == null
          ? null
          : '${dataScadenza.year.toString().padLeft(4, '0')}-'
              '${dataScadenza.month.toString().padLeft(2, '0')}-'
              '${dataScadenza.day.toString().padLeft(2, '0')}',
    }).eq('id', id);
  }

  static Future<void> delete(UqsaAttestato row) async {
    final path = row.filePath.trim();
    if (path.isNotEmpty && path != 'pending') {
      try {
        await _supa.storage.from(kUqsaAttestatiBucket).remove([path]);
      } catch (_) {}
    }
    await _supa.from('uqsa_attestati').delete().eq('id', row.id);
  }

  static Future<Uint8List> downloadBytes(UqsaAttestato row) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    final bytes = await _supa.storage.from(kUqsaAttestatiBucket).download(path);
    return Uint8List.fromList(bytes);
  }

  static Future<String> signedUrl(UqsaAttestato row, {int expiresIn = 3600}) async {
    final path = row.filePath.trim();
    if (path.isEmpty || path == 'pending') {
      throw StateError('File non ancora disponibile');
    }
    return _supa.storage.from(kUqsaAttestatiBucket).createSignedUrl(path, expiresIn);
  }
}
