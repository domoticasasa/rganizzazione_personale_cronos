import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/users_directory.dart';

class DocFirmaBatch {
  DocFirmaBatch(this.raw);
  final Map<String, dynamic> raw;
  String get id => (raw['id'] ?? '').toString();
  String get title => (raw['title'] ?? '').toString();
  String get originalFileName => (raw['original_file_name'] ?? '').toString();
  String get pdfPath => (raw['pdf_path'] ?? '').toString();
  String get pdfSha256 => (raw['pdf_sha256'] ?? '').toString();
  DateTime? get createdAt => DateTime.tryParse((raw['created_at'] ?? '').toString());
  bool get hasAccessPassword => raw['has_access_password'] == true;
}

class DocFirmaAssignment {
  DocFirmaAssignment(this.raw);
  final Map<String, dynamic> raw;

  String get id => (raw['id'] ?? '').toString();
  String get batchId => (raw['batch_id'] ?? '').toString();
  String get status => (raw['status'] ?? '').toString();
  int get recipientUserId =>
      int.tryParse((raw['recipient_user_id'] ?? '').toString()) ?? 0;
  String? get personaleId =>
      (raw['personale_id'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['personale_id'] ?? '').toString();
  DateTime? get sentAt => DateTime.tryParse((raw['sent_at'] ?? '').toString());
  DateTime? get signDeadline =>
      DateTime.tryParse((raw['sign_deadline'] ?? '').toString());
  DateTime? get signedAt =>
      DateTime.tryParse((raw['signed_at'] ?? '').toString());
  DateTime? get downloadUntil =>
      DateTime.tryParse((raw['download_until'] ?? '').toString());
  String? get signedPdfPath {
    final p = (raw['signed_pdf_path'] ?? '').toString().trim();
    return p.isEmpty ? null : p;
  }

  Map<String, dynamic>? get batch {
    final b = raw['doc_firma_batches'];
    if (b is Map) return Map<String, dynamic>.from(b);
    return null;
  }

  String get title => (batch?['title'] ?? 'Documento').toString();
  String get originalFileName =>
      (batch?['original_file_name'] ?? '').toString();
  bool get requiresAccessPassword => batch?['has_access_password'] == true;

  Map<String, dynamic>? get recipientUser {
    final u = raw['users'];
    if (u is Map) return Map<String, dynamic>.from(u);
    return null;
  }

  String get recipientLabel {
    final name = (recipientUser?['full_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (recipientUser?['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'User #$recipientUserId';
  }

  bool get canDownload {
    if (status != 'signed') return false;
    final until = downloadUntil;
    if (until == null) return false;
    return until.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool get canSign {
    if (status != 'pending') return false;
    final d = signDeadline;
    if (d == null) return false;
    return d.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool get canCancelAdmin =>
      status == 'pending' || (status == 'signed' && canDownload);

  Map<String, dynamic> get signatureMeta {
    final rawMeta = raw['signature_meta'];
    if (rawMeta is Map) return Map<String, dynamic>.from(rawMeta);
    return const <String, dynamic>{};
  }

  String get signerName =>
      (signatureMeta['signer_name'] ?? recipientLabel).toString();
}

/// Servizio documenti da firmare (admin + dipendente).
abstract final class DocFirmaService {
  DocFirmaService._();

  static final _supa = SupabaseService.client;
  static const bucket = 'doc_firma';

  static String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Giorni per firmare / per scaricare (allineati al DB).
  static const int signWindowDays = 3;
  static const int downloadWindowDays = 3;

  /// Scade pending e elimina documenti oltre la finestra download.
  static Future<void> expirePending() async {
    try {
      final res = await _supa.rpc('doc_firma_expire_pending');
      final paths = <String>[];
      if (res is Map) {
        final raw = res['storage_paths'];
        if (raw is List) {
          for (final p in raw) {
            final s = p?.toString().trim() ?? '';
            if (s.isNotEmpty) paths.add(s);
          }
        }
      }
      if (paths.isEmpty) return;
      // Storage API (delete diretto su storage.objects è bloccato in DB).
      const chunk = 50;
      for (var i = 0; i < paths.length; i += chunk) {
        final end = (i + chunk > paths.length) ? paths.length : i + chunk;
        try {
          await _supa.storage.from(bucket).remove(paths.sublist(i, end));
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Registra verifica Passkey (alternativa OTP) per l'assegnazione.
  static Future<void> recordPasskeyAuth(String assignmentId) async {
    await _supa.rpc(
      'doc_firma_record_passkey_auth',
      params: {'p_assignment_id': assignmentId},
    );
  }

  static Future<List<DocFirmaAssignment>> listAdminAssignments() async {
    await expirePending();
    // Evita di scaricare i PNG firma (base64) in lista: bloccano UI/web.
    final rows = await _supa
        .from('doc_firma_assignments')
        .select(
          'id, batch_id, personale_id, recipient_user_id, status, sent_at, '
          'sign_deadline, signed_at, download_until, signed_pdf_path, '
          'signed_pdf_sha256, cancelled_at, cancelled_by_user_id, created_at, '
          'doc_firma_batches(id, title, original_file_name, pdf_path, pdf_sha256, created_at, has_access_password), '
          'users!recipient_user_id(id, full_name, email)',
        )
        .order('sent_at', ascending: false);
    return (rows as List)
        .map((e) => DocFirmaAssignment(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<DocFirmaAssignment>> listBatchAssignmentsForExport(
    String batchId,
  ) async {
    // Evita di scaricare signature_png_base64 (mega-stringhe): per l'export
    // bastano i campi meta testuali; la grafica arriva da Storage.
    final rows = await _supa
        .from('doc_firma_assignments')
        .select(
          'id, batch_id, personale_id, recipient_user_id, status, sent_at, '
          'sign_deadline, signed_at, download_until, signed_pdf_path, '
          'signed_pdf_sha256, cancelled_at, cancelled_by_user_id, created_at, '
          'signer_name:signature_meta->>signer_name, '
          'signer_email:signature_meta->>signer_email, '
          'otp_verified:signature_meta->otp_verified, '
          'passkey_verified:signature_meta->passkey_verified, '
          'auth_method:signature_meta->>auth_method, '
          'protections:signature_meta->protections, '
          'device_unlock:signature_meta->device_unlock, '
          'original_sha256:signature_meta->>original_sha256, '
          'signed_sha256:signature_meta->>signed_sha256, '
          'disclaimer:signature_meta->>disclaimer, '
          'signed_at_italy:signature_meta->>signed_at_italy, '
          'signature_png_path:signature_meta->>signature_png_path, '
          'signature_png_base64:signature_meta->>signature_png_base64, '
          'page_codes:signature_meta->page_codes, '
          'document_seal:signature_meta->>document_seal, '
          'server_timestamp:signature_meta->>server_timestamp, '
          'ts_nonce:signature_meta->>ts_nonce, '
          'evidence_id:signature_meta->>evidence_id, '
          'evidence_hmac:signature_meta->>evidence_hmac, '
          'pdf_locked:signature_meta->pdf_locked, '
          'doc_firma_batches(id, title, original_file_name, pdf_path, pdf_sha256, created_at, has_access_password), '
          'users!recipient_user_id(id, full_name, email)',
        )
        .eq('batch_id', batchId)
        .order('signed_at', ascending: true);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      m['signature_meta'] = <String, dynamic>{
        'signer_name': m.remove('signer_name'),
        'signer_email': m.remove('signer_email'),
        'otp_verified': m.remove('otp_verified'),
        'passkey_verified': m.remove('passkey_verified'),
        'auth_method': m.remove('auth_method'),
        'protections': m.remove('protections'),
        'device_unlock': m.remove('device_unlock'),
        'original_sha256': m.remove('original_sha256'),
        'signed_sha256': m.remove('signed_sha256'),
        'disclaimer': m.remove('disclaimer'),
        'signed_at_italy': m.remove('signed_at_italy'),
        'signature_png_path': m.remove('signature_png_path'),
        'signature_png_base64': m.remove('signature_png_base64'),
        'page_codes': m.remove('page_codes'),
        'document_seal': m.remove('document_seal'),
        'server_timestamp': m.remove('server_timestamp'),
        'ts_nonce': m.remove('ts_nonce'),
        'evidence_id': m.remove('evidence_id'),
        'evidence_hmac': m.remove('evidence_hmac'),
        'pdf_locked': m.remove('pdf_locked'),
      };
      return DocFirmaAssignment(m);
    }).toList();
  }

  static Future<List<DocFirmaAssignment>> listMyAssignments() async {
    await expirePending();
    final uid = await _currentUsersId();
    if (uid == null) return const [];
    final rows = await _supa
        .from('doc_firma_assignments')
        .select(
          '*, doc_firma_batches(id, title, original_file_name, pdf_path, pdf_sha256, created_at, has_access_password)',
        )
        .eq('recipient_user_id', uid)
        .order('sent_at', ascending: false);
    return (rows as List)
        .map((e) => DocFirmaAssignment(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<int?> _currentUsersId() async {
    final authId = _supa.auth.currentUser?.id;
    if (authId == null) return null;
    final row = await _supa
        .from('users')
        .select('id')
        .eq('auth_id', authId)
        .maybeSingle();
    if (row == null) return null;
    return int.tryParse((row['id'] ?? '').toString());
  }

  static Future<List<Map<String, dynamic>>> loadSelectableDipendenti() async {
    final hidden = await UsersDirectory.loadHiddenLinkKeys();
    final personale = await _supa
        .from('personale')
        .select('id, id_uuid, full_name, email, user_id, active, matricola')
        .eq('active', true)
        .order('full_name');
    final users = await _supa
        .from('users')
        .select('id, auth_id, id_uuid, email, full_name, hidden_from_directory');

    final byAuth = <String, Map<String, dynamic>>{};
    final byId = <String, Map<String, dynamic>>{};
    final byEmail = <String, Map<String, dynamic>>{};
    for (final raw in (users as List)) {
      final u = Map<String, dynamic>.from(raw as Map);
      if (UsersDirectory.isHiddenFromDirectory(u)) continue;
      final auth = (u['auth_id'] ?? '').toString().trim().toLowerCase();
      final idUuid = (u['id_uuid'] ?? '').toString().trim().toLowerCase();
      final email = (u['email'] ?? '').toString().trim().toLowerCase();
      final id = (u['id'] ?? '').toString();
      if (auth.isNotEmpty) byAuth[auth] = u;
      if (idUuid.isNotEmpty) byAuth[idUuid] = u;
      if (id.isNotEmpty) byId[id] = u;
      if (email.isNotEmpty) byEmail[email] = u;
    }

    final out = <Map<String, dynamic>>[];
    for (final raw in (personale as List)) {
      final p = Map<String, dynamic>.from(raw as Map);
      final link = (p['user_id'] ?? '').toString().trim().toLowerCase();
      final email = (p['email'] ?? '').toString().trim().toLowerCase();
      if (hidden.contains(link) || (email.isNotEmpty && hidden.contains(email))) {
        continue;
      }
      Map<String, dynamic>? u;
      if (link.isNotEmpty) {
        u = byAuth[link] ?? byId[link];
      }
      u ??= email.isNotEmpty ? byEmail[email] : null;
      if (u == null) continue;
      out.add({
        ...p,
        'recipient_user_id': u['id'],
        'users_email': u['email'],
        'users_full_name': u['full_name'],
      });
    }
    return out;
  }

  static Future<Uint8List> ensurePdfBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final lower = fileName.toLowerCase();
    final isPdf = lower.endsWith('.pdf') || _looksLikePdf(bytes);
    if (isPdf) return bytes;

    final res = await _supa.functions.invoke(
      'convert-office-pdf',
      body: {
        'fileBase64': base64Encode(bytes),
        'fileName': fileName,
      },
    );
    final data = res.data;
    if (data is Map) {
      final err = (data['error'] ?? '').toString().trim();
      if (err.isNotEmpty) {
        final details = (data['details'] ?? '').toString().trim();
        if (err == 'gotenberg_not_configured' ||
            err.contains('GOTENBERG_URL')) {
          throw StateError(
            details.isNotEmpty
                ? details
                : 'Per Word/Excel serve la conversione PDF (Gotenberg). '
                    'Per ora carica un file PDF.',
          );
        }
        throw StateError('Conversione PDF fallita: $err $details'.trim());
      }
      final b64 = (data['pdfBase64'] ?? '').toString();
      if (b64.isEmpty) throw StateError('Conversione PDF: output vuoto');
      return base64Decode(b64);
    }
    throw StateError('Conversione PDF: HTTP ${res.status}');
  }

  static bool _looksLikePdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  static Future<DocFirmaBatch> createAndSend({
    required String title,
    required String originalFileName,
    required String? originalMime,
    required Uint8List fileBytes,
    required List<Map<String, dynamic>> recipients,
    String? accessPassword,
  }) async {
    final adminId = await _currentUsersId();
    if (adminId == null) throw StateError('Utente non autenticato');
    if (recipients.isEmpty) throw StateError('Seleziona almeno un dipendente');

    final pdfBytes = await ensurePdfBytes(
      bytes: fileBytes,
      fileName: originalFileName,
    );
    final hash = sha256Hex(pdfBytes);
    final pwd = (accessPassword ?? '').trim();
    final hasPwd = pwd.isNotEmpty;
    final pwdHash = hasPwd ? sha256Hex(Uint8List.fromList(utf8.encode(pwd))) : null;

    // Pre-insert batch id via uuid from DB
    final inserted = await _supa
        .from('doc_firma_batches')
        .insert({
          'title': title.trim(),
          'created_by_user_id': adminId,
          'original_file_name': originalFileName,
          'original_mime': originalMime,
          'pdf_path': 'pending',
          'pdf_sha256': hash,
          'has_access_password': hasPwd,
          'access_password_hash': pwdHash,
        })
        .select('id')
        .single();
    final id = (inserted['id'] ?? '').toString();
    if (id.isEmpty) throw StateError('Creazione batch fallita');

    final pdfPath = 'batch/$id/original.pdf';
    final sourcePath = 'batch/$id/source_${_safeName(originalFileName)}';

    await _supa.storage.from(bucket).uploadBinary(
          pdfPath,
          pdfBytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    final lower = originalFileName.toLowerCase();
    if (!lower.endsWith('.pdf')) {
      try {
        await _supa.storage.from(bucket).uploadBinary(
              sourcePath,
              fileBytes,
              fileOptions: FileOptions(
                contentType: originalMime ?? 'application/octet-stream',
                upsert: true,
              ),
            );
      } catch (_) {}
    }

    await _supa.from('doc_firma_batches').update({
      'pdf_path': pdfPath,
      'source_path': lower.endsWith('.pdf') ? null : sourcePath,
    }).eq('id', id);

    final deadline =
        DateTime.now().toUtc().add(const Duration(days: signWindowDays));
    final assignRows = <Map<String, dynamic>>[];
    final notifyIds = <int>[];
    for (final r in recipients) {
      final uid = int.tryParse((r['recipient_user_id'] ?? '').toString());
      if (uid == null || uid <= 0) continue;
      assignRows.add({
        'batch_id': id,
        'personale_id': r['id_uuid'],
        'recipient_user_id': uid,
        'status': 'pending',
        'sign_deadline': deadline.toIso8601String(),
      });
      notifyIds.add(uid);
    }
    if (assignRows.isEmpty) {
      throw StateError('Nessun destinatario valido con login');
    }
    await _supa.from('doc_firma_assignments').insert(assignRows);

    // Web Push / canale push (la notifica in-app è già creata dal trigger DB).
    try {
      final res = await _supa.functions.invoke(
        'doc-firma-notify',
        body: {
          'user_ids': notifyIds,
          'batch_id': id,
          'title': 'Documento da firmare',
          'message':
              'Hai ricevuto «${title.trim()}». Hai $signWindowDays giorni per firmarlo '
              '(Passkey + OTP email + firma grafica).',
          'skip_in_app': true,
        },
      );
      if (res.status >= 400) {
        // ignore: avoid_print
        print('doc-firma-notify HTTP ${res.status}: ${res.data}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('doc-firma-notify error: $e');
    }

    final batch = await _supa
        .from('doc_firma_batches')
        .select()
        .eq('id', id)
        .single();
    return DocFirmaBatch(Map<String, dynamic>.from(batch));
  }

  static String _safeName(String name) {
    return name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
  }

  static Future<bool> verifyAccessPassword({
    required String batchId,
    required String password,
  }) async {
    final raw = await _supa.rpc(
      'doc_firma_verify_access_password',
      params: {
        'p_batch_id': batchId,
        'p_password': password.trim(),
      },
    );
    return raw == true;
  }

  static Future<void> cancelAssignment(String assignmentId) async {
    await _supa.rpc(
      'doc_firma_cancel_assignment',
      params: {'p_assignment_id': assignmentId},
    );
  }

  static Future<Map<String, dynamic>> requestOtp(String assignmentId) async {
    final res = await _supa.functions.invoke(
      'doc-firma-send-otp',
      body: {'assignment_id': assignmentId},
    );
    final data = res.data;
    if (data is Map) {
      final err = (data['error'] ?? '').toString().trim();
      if (err.isNotEmpty) throw StateError(err);
      return Map<String, dynamic>.from(data);
    }
    throw StateError('Invio OTP fallito (HTTP ${res.status})');
  }

  static Future<bool> verifyOtp(String assignmentId, String code) async {
    final raw = await _supa.rpc(
      'doc_firma_verify_otp',
      params: {
        'p_assignment_id': assignmentId,
        'p_code': code.trim(),
      },
    );
    return raw == true;
  }

  static Future<Uint8List> downloadOriginalPdf(DocFirmaAssignment a) async {
    final path = (a.batch?['pdf_path'] ?? '').toString();
    if (path.isEmpty) throw StateError('PDF non trovato');
    return _supa.storage.from(bucket).download(path);
  }

  static Future<Uint8List> downloadSignedPdf(
    DocFirmaAssignment a, {
    bool allowAdminOverride = false,
  }) async {
    final path = a.signedPdfPath;
    if (path == null || path.isEmpty) {
      throw StateError('PDF firmato assente');
    }
    if (!a.canDownload) {
      if (!(allowAdminOverride && a.status == 'signed')) {
        throw StateError('Download non disponibile (scaduto o non firmato)');
      }
    }
    return _supa.storage.from(bucket).download(path);
  }

  static Future<Uint8List> downloadBatchFullySignedPdf({
    required String batchId,
  }) async {
    final batchRows = await listBatchAssignmentsForExport(batchId);
    if (batchRows.isEmpty) {
      throw StateError('Nessuna assegnazione trovata per questo documento');
    }
    final notSigned = batchRows.where((a) => a.status != 'signed').toList();
    if (notSigned.isNotEmpty) {
      throw StateError('Export disponibile solo quando hanno firmato tutti');
    }

    // Stesso PDF del dipendente: niente ricostruzione "vecchia" dall'originale.
    final signedCopies = <Uint8List>[];
    for (final a in batchRows) {
      signedCopies.add(
        await downloadSignedPdf(a, allowAdminOverride: true),
      );
    }
    if (signedCopies.length == 1) {
      return signedCopies.first;
    }

    // Multi-firma: copertina riepilogo + concatenazione dei PDF firmati reali.
    final merged = PdfDocument();
    merged.pageSettings.setMargins(0);
    final cover = merged.pages.add();
    final cg = cover.graphics;
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      14,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    var cy = 36.0;
    void coverLine(String t, {PdfFont? f}) {
      cg.drawString(
        _pdfSafe(t),
        f ?? bodyFont,
        bounds: Rect.fromLTWH(36, cy, cover.getClientSize().width - 72, 18),
      );
      cy += 18;
    }

    coverLine('Export multi-firma Cronos GESTOPRO', f: titleFont);
    cy += 6;
    coverLine('Documento: ${batchRows.first.title}');
    coverLine('Firmatari: ${batchRows.length}');
    coverLine(
      'Ogni sezione successiva e il PDF firmato reale del dipendente '
      '(codici pagina + attestato + blocco).',
    );
    cy += 8;
    for (var i = 0; i < batchRows.length; i++) {
      final a = batchRows[i];
      coverLine(
        '${i + 1}) ${a.signerName} · ${a.recipientLabel} · '
        'seal ${(a.signatureMeta['document_seal'] ?? '-')}',
      );
    }
    for (final bytes in signedCopies) {
      _appendOriginalPdfPages(target: merged, originalPdf: bytes);
    }
    final mergedOut = await merged.save();
    merged.dispose();
    return Uint8List.fromList(mergedOut);
  }

  /// Fallback legacy (non usato dall'export principale).

  /// Helvetica Syncfusion non gestisce bene accenti/unicode: evita freeze/crash.
  static void _appendOriginalPdfPages({
    required PdfDocument target,
    required Uint8List originalPdf,
  }) {
    PdfDocument? src;
    try {
      src = PdfDocument(inputBytes: originalPdf);
      for (var i = 0; i < src.pages.count; i++) {
        final template = src.pages[i].createTemplate();
        final page = target.pages.add();
        final size = page.getClientSize();
        page.graphics.drawPdfTemplate(
          template,
          const Offset(0, 0),
          Size(size.width, size.height),
        );
      }
    } catch (_) {
      // Se il PDF firmato non e' importabile, salta quella copia.
    } finally {
      src?.dispose();
    }
  }

  static String _pdfSafe(String input) {
    return input
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('í', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ó', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ú', 'u')
        .replaceAll('À', 'A')
        .replaceAll('È', 'E')
        .replaceAll('É', 'E')
        .replaceAll('Ì', 'I')
        .replaceAll('Ò', 'O')
        .replaceAll('Ù', 'U')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E]'), '?');
  }

  static Uint8List _compactPngForPdf(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      final resized = decoded.width > 480
          ? img.copyResize(decoded, width: 480)
          : decoded;
      return Uint8List.fromList(img.encodePng(resized, level: 6));
    } catch (_) {
      return raw;
    }
  }

  /// Codice multinumerico casuale (es. 847291-038514-762093).
  static String _randomPageCode([Random? rng]) {
    final r = rng ?? Random.secure();
    String block() =>
        List.generate(6, (_) => r.nextInt(10)).join();
    return '${block()}-${block()}-${block()}';
  }

  static String _randomOwnerPassword([Random? rng]) {
    final r = rng ?? Random.secure();
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    return List.generate(28, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Marca temporale server (non TSA) da includere nel PDF prima del mark_signed.
  static Future<DocFirmaTimestampToken> issueTimestampToken(
    String assignmentId,
  ) async {
    final res = await _supa.rpc(
      'doc_firma_issue_timestamp',
      params: {'p_assignment_id': assignmentId},
    );
    if (res is! Map) {
      throw StateError('Timestamp server non disponibile');
    }
    return DocFirmaTimestampToken(Map<String, dynamic>.from(res));
  }

  /// Verifica integrita di un PDF rispetto ad hash + ledger evidenze (admin).
  static Future<DocFirmaIntegrityResult> verifyIntegrity(
    Uint8List pdfBytes,
  ) async {
    final hash = sha256Hex(pdfBytes);
    final res = await _supa.rpc(
      'doc_firma_verify_integrity',
      params: {'p_sha256': hash},
    );
    if (res is! Map) {
      throw StateError('Verifica integrita non disponibile');
    }
    return DocFirmaIntegrityResult(Map<String, dynamic>.from(res));
  }

  static Future<List<Map<String, dynamic>>> listEvidence({
    String? batchId,
    String? assignmentId,
  }) async {
    final res = await _supa.rpc(
      'doc_firma_list_evidence',
      params: {
        'p_batch_id': batchId,
        'p_assignment_id': assignmentId,
      },
    );
    if (res is! List) return const [];
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Pacchetto JSON evidenze (ledger + meta firme) per conservazione light.
  static Future<Uint8List> buildEvidencePackJson({
    required String batchId,
  }) async {
    final rows = await listBatchAssignmentsForExport(batchId);
    final evidence = await listEvidence(batchId: batchId);
    final pack = <String, dynamic>{
      'format': 'cronos_doc_firma_evidence_v1',
      'note':
          'Pacchetto evidenze interne CRONOS. Non costituisce conservazione a norma AgID, '
          'né marca temporale TSA RFC3161, né firma PAdES/CAdES.',
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'batch_id': batchId,
      'title': rows.isEmpty ? null : rows.first.title,
      'signers': rows.map((a) {
        final meta = a.signatureMeta;
        return <String, dynamic>{
          'assignment_id': a.id,
          'status': a.status,
          'recipient': a.recipientLabel,
          'signed_at': a.signedAt?.toUtc().toIso8601String(),
          'download_until': a.downloadUntil?.toUtc().toIso8601String(),
          'signed_pdf_sha256': a.raw['signed_pdf_sha256'],
          'signature_meta': {
            'auth_method': meta['auth_method'],
            'protections': meta['protections'],
            'otp_verified': meta['otp_verified'],
            'passkey_verified': meta['passkey_verified'],
            'original_sha256': meta['original_sha256'],
            'signed_sha256': meta['signed_sha256'],
            'page_codes': meta['page_codes'],
            'document_seal': meta['document_seal'],
            'server_timestamp': meta['server_timestamp'],
            'ts_nonce': meta['ts_nonce'],
            'evidence_id': meta['evidence_id'],
            'evidence_hmac': meta['evidence_hmac'],
            'pdf_locked': meta['pdf_locked'],
            'signer_name': meta['signer_name'],
            'signer_email': meta['signer_email'],
          },
        };
      }).toList(),
      'evidence_ledger': evidence,
    };
    const encoder = JsonEncoder.withIndent('  ');
    return Uint8List.fromList(utf8.encode(encoder.convert(pack)));
  }

  static Future<DocFirmaAssignment> completeSign({
    required DocFirmaAssignment assignment,
    required Uint8List signaturePng,
    required String signerName,
    required String signerEmail,
    Map<String, dynamic>? deviceUnlock,
  }) async {
    final tsToken = await issueTimestampToken(assignment.id);
    final original = await downloadOriginalPdf(assignment);
    final preHash = sha256Hex(original);
    final stamped = await stampSignedPdf(
      originalPdf: original,
      signaturePng: signaturePng,
      signerName: signerName,
      signerEmail: signerEmail,
      assignmentId: assignment.id,
      originalSha256: preHash,
      deviceUnlockMethod: (deviceUnlock?['method'] ?? '').toString().trim().isEmpty
          ? null
          : (deviceUnlock?['method'] ?? '').toString(),
      serverTimestampUtc: tsToken.serverTs,
      tsNonce: tsToken.nonce,
    );
    final postHash = sha256Hex(stamped.bytes);
    final path = 'assignment/${assignment.id}/signed.pdf';
    final sigPath = 'assignment/${assignment.id}/signature.png';
    final compactSig = _compactPngForPdf(signaturePng);
    await _supa.storage.from(bucket).uploadBinary(
          path,
          stamped.bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );
    try {
      await _supa.storage.from(bucket).uploadBinary(
            sigPath,
            compactSig,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );
    } catch (_) {}

    final meta = <String, dynamic>{
      'auth_method': 'passkey+otp+signature',
      'otp_verified': true,
      'passkey_verified': true,
      'protections': const [
        'passkey',
        'otp',
        'signature',
        'server_timestamp',
        'evidence_hmac',
        'pdf_lock',
      ],
      'signed_at_italy': DateFormat('dd/MM/yyyy HH:mm').format(italyNow()),
      'signer_name': signerName,
      'signer_email': signerEmail,
      'signature_png_path': sigPath,
      'original_sha256': preHash,
      'signed_sha256': postHash,
      'page_codes': stamped.pageCodes,
      'document_seal': stamped.documentSeal,
      'ts_token_id': tsToken.tokenId,
      'ts_nonce': tsToken.nonce,
      'server_timestamp': tsToken.serverTs.toUtc().toIso8601String(),
      'timestamp_kind': 'cronos_server_timestamp',
      'pdf_locked': true,
      'pdf_lock':
          'no_edit,no_copy,no_extract,no_assemble; print allowed; owner sealed',
      'disclaimer':
          'Firma elettronica semplice Cronos (non firma qualificata eIDAS). '
          'Marca temporale server interna (non TSA). '
          'PDF bloccato contro modifica/estrazione/assemblaggio pagine.',
      'device_unlock': deviceUnlock,
    };

    final row = await _supa.rpc(
      'doc_firma_mark_signed',
      params: {
        'p_assignment_id': assignment.id,
        'p_signed_pdf_path': path,
        'p_signed_pdf_sha256': postHash,
        'p_signature_meta': meta,
      },
    );
    if (row is Map) {
      return DocFirmaAssignment(Map<String, dynamic>.from(row));
    }
    final refreshed = await _supa
        .from('doc_firma_assignments')
        .select(
          '*, doc_firma_batches(id, title, original_file_name, pdf_path, pdf_sha256, created_at, has_access_password)',
        )
        .eq('id', assignment.id)
        .single();
    return DocFirmaAssignment(Map<String, dynamic>.from(refreshed));
  }

  /// Applica codice pagina, attestato (con timestamp server) e blocco PDF.
  static Future<StampedSignedPdf> stampSignedPdf({
    required Uint8List originalPdf,
    required Uint8List signaturePng,
    required String signerName,
    required String signerEmail,
    required String assignmentId,
    required String originalSha256,
    String? deviceUnlockMethod,
    DateTime? serverTimestampUtc,
    String? tsNonce,
  }) async {
    final rng = Random.secure();
    final doc = PdfDocument(inputBytes: originalPdf);
    if (doc.pages.count == 0) {
      doc.pages.add();
    }

    final sig = PdfBitmap(signaturePng);
    final fontTinyBold = PdfStandardFont(
      PdfFontFamily.helvetica,
      7.5,
      style: PdfFontStyle.bold,
    );
    final pageCodes = <String, String>{};
    final contentPageCount = doc.pages.count;

    for (var i = 0; i < contentPageCount; i++) {
      final page = doc.pages[i];
      final size = page.getClientSize();
      final code = _randomPageCode(rng);
      pageCodes['${i + 1}'] = code;

      // Sul documento originale: solo codice + scritta, niente grafica firma.
      page.graphics.drawString(
        _pdfSafe('firma digitale  $code'),
        fontTinyBold,
        brush: PdfSolidBrush(PdfColor(20, 60, 140)),
        bounds: Rect.fromLTWH(24, size.height - 18, size.width - 48, 12),
      );
    }

    final documentSeal = _randomPageCode(rng);
    final fontTitle = PdfStandardFont(PdfFontFamily.helvetica, 16,
        style: PdfFontStyle.bold);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 9);

    // Attestato multipagina: con 100+ codici va a capo su fogli nuovi; firma mai tagliata.
    PdfPage certPage = doc.pages.add();
    var certIndex = 1;
    var certCode = _randomPageCode(rng);
    pageCodes['attestato_$certIndex'] = certCode;
    pageCodes['attestato'] = certCode;
    PdfGraphics g = certPage.graphics;
    Size certSize = certPage.getClientSize();
    var y = 40.0;
    const topY = 40.0;
    const footerH = 22.0;
    const sigBlockH = 96.0;
    const lineStep = 16.0;

    void paintCertFooter() {
      g.drawString(
        _pdfSafe('COD ATTESTATO $certIndex: $certCode'),
        fontTinyBold,
        brush: PdfSolidBrush(PdfColor(20, 60, 140)),
        bounds: Rect.fromLTWH(24, certSize.height - 18, certSize.width - 48, 12),
      );
    }

    void newCertPage() {
      paintCertFooter();
      certPage = doc.pages.add();
      certIndex += 1;
      certCode = _randomPageCode(rng);
      pageCodes['attestato_$certIndex'] = certCode;
      g = certPage.graphics;
      certSize = certPage.getClientSize();
      y = topY;
      g.drawString(
        _pdfSafe('Attestato firma (continua) — foglio $certIndex'),
        fontSmall,
        bounds: Rect.fromLTWH(40, y, certSize.width - 80, 14),
      );
      y += 20;
    }

    void ensureSpace(double need) {
      final limit = certSize.height - footerH - 8;
      if (y + need > limit) {
        newCertPage();
      }
    }

    void line(String t, {PdfFont? f, double step = lineStep}) {
      ensureSpace(step + 2);
      g.drawString(
        _pdfSafe(t),
        f ?? font,
        bounds: Rect.fromLTWH(40, y, certSize.width - 80, step + 2),
      );
      y += step;
    }

    final serverTs = (serverTimestampUtc ?? DateTime.now().toUtc()).toUtc();
    final serverTsLabel =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(serverTs.toLocal());
    line('Attestato di firma Cronos GESTOPRO', f: fontTitle, step: 22);
    y += 4;
    line('Documento firmato elettronicamente (firma semplice SES).');
    line('Non costituisce firma elettronica qualificata (eIDAS).');
    line('Non e marca temporale TSA RFC3161 ne firma PAdES/CAdES-LTV.');
    y += 4;
    line('Firmatario: $signerName');
    line('Email: $signerEmail');
    line(
      'Data/ora client (Italia): ${DateFormat('dd/MM/yyyy HH:mm:ss').format(italyNow())}',
    );
    line('Marca temporale server UTC: ${serverTs.toIso8601String()}');
    line('Marca temporale server (locale): $serverTsLabel');
    if (tsNonce != null && tsNonce.trim().isNotEmpty) {
      line('Nonce timestamp: ${tsNonce.trim()}', f: fontSmall, step: 14);
    }
    line('ID assegnazione: $assignmentId');
    line('Sigillo documento: $documentSeal');
    line('SHA-256 PDF originale: $originalSha256', f: fontSmall, step: 14);
    y += 4;
    line('Protezioni applicate (in ordine):');
    line('1) Passkey account CRONOS');
    line('2) OTP email monouso');
    line('3) Firma grafica digitale (in fondo all\'attestato)');
    line('4) Marca temporale server CRONOS + ledger evidenze HMAC');
    line('5) Blocco PDF anti-modifica / anti-estrazione / anti-assemblaggio');
    if (deviceUnlockMethod != null && deviceUnlockMethod.isNotEmpty) {
      final label = switch (deviceUnlockMethod) {
        'webauthn' => 'impronta / Face ID (WebAuthn)',
        'passkey' => 'Passkey account',
        'passkey+otp' => 'Passkey + OTP',
        'pin' => 'PIN dispositivo',
        'pattern' => 'segno di sblocco',
        _ => deviceUnlockMethod,
      };
      line('Meta dispositivo: $label');
    }
    y += 4;
    line('Codici pagina (univoci, casuali) — $contentPageCount pagine:');
    // Due colonne; a fine foglio va a capo su un nuovo attestato.
    final colW = (certSize.width - 80) / 2;
    for (var i = 1; i <= contentPageCount; i += 2) {
      ensureSpace(14);
      g.drawString(
        _pdfSafe('Pag.$i: ${pageCodes['$i']}'),
        fontSmall,
        bounds: Rect.fromLTWH(40, y, colW - 8, 14),
      );
      if (i + 1 <= contentPageCount) {
        g.drawString(
          _pdfSafe('Pag.${i + 1}: ${pageCodes['${i + 1}']}'),
          fontSmall,
          bounds: Rect.fromLTWH(40 + colW, y, colW - 8, 14),
        );
      }
      y += 14;
    }
    y += 4;
    line('Ogni foglio attestato ha in basso il proprio COD ATTESTATO.');
    line('Blocco PDF: modifica, copia/estrazione e assemblaggio disabilitati.');
    line('Apertura libera in sola lettura; stampa consentita.');
    line('Evidenze HMAC restano nel ledger anche dopo scadenza download.');

    // Firma sempre intera: se non c'e' spazio, nuovo foglio dedicato.
    ensureSpace(sigBlockH);
    line('Firma grafica del firmatario:', f: fontSmall, step: 14);
    ensureSpace(80);
    g.drawRectangle(
      pen: PdfPen(PdfColor(180, 190, 210), width: 0.6),
      bounds: Rect.fromLTWH(38, y - 2, 244, 84),
    );
    g.drawImage(sig, Rect.fromLTWH(40, y, 240, 80));
    y += 88;
    ensureSpace(16);
    line('Firmatario: $signerName', f: fontSmall, step: 14);
    paintCertFooter();

    // Blocco: owner password + permessi solo stampa (niente edit/copy/assemble).
    final ownerPwd = _randomOwnerPassword(rng);
    final security = doc.security;
    security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
    security.ownerPassword = ownerPwd;
    security.permissions.add(PdfPermissionsFlags.print);
    security.permissions.add(PdfPermissionsFlags.fullQualityPrint);

    final out = await doc.save();
    doc.dispose();
    return StampedSignedPdf(
      bytes: Uint8List.fromList(out),
      pageCodes: pageCodes,
      documentSeal: documentSeal,
    );
  }

  /// Cattura widget firma (RepaintBoundary) in PNG.
  static Future<Uint8List?> captureSignaturePng(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) return null;
    return bd.buffer.asUint8List();
  }
}

class StampedSignedPdf {
  const StampedSignedPdf({
    required this.bytes,
    required this.pageCodes,
    required this.documentSeal,
  });

  final Uint8List bytes;
  final Map<String, String> pageCodes;
  final String documentSeal;
}

class DocFirmaTimestampToken {
  DocFirmaTimestampToken(this.raw);
  final Map<String, dynamic> raw;

  String get tokenId => (raw['token_id'] ?? '').toString();
  String get nonce => (raw['nonce'] ?? '').toString();
  DateTime get serverTs {
    final parsed = DateTime.tryParse((raw['server_ts'] ?? '').toString());
    return (parsed ?? DateTime.now()).toUtc();
  }
}

class DocFirmaIntegrityResult {
  DocFirmaIntegrityResult(this.raw);
  final Map<String, dynamic> raw;

  bool get ok => raw['ok'] == true;
  String get verdict => (raw['verdict'] ?? '').toString();
  String get fileSha256 => (raw['file_sha256'] ?? '').toString();
  String get message => (raw['message'] ?? '').toString();

  List<Map<String, dynamic>> get matches {
    final m = raw['matches'];
    if (m is! List) return const [];
    return m
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  bool get isIntegro => verdict == 'integro' && ok;
  bool get isManomesso =>
      verdict == 'manomesso' || verdict == 'sconosciuto_o_manomesso';
}
