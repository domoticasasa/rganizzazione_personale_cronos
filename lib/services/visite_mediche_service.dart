import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'employee_programmazione_service.dart';
import 'supabase_service.dart';

const String kVisiteMedicheRfiBucket = 'visite_mediche_rfi';
const String kVisiteMedicheTable = 'visite_mediche_programmazione';
const String kVisiteMedicheRfiTable = 'visite_mediche_rfi';

/// Accesso dati programmazione visite mediche (standard e RFI).
class VisiteMedicheService {
  VisiteMedicheService._();

  static String _s(dynamic v) => (v ?? '').toString().trim();
  static String _isoDateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static SupabaseClient get _supa => SupabaseService.client;

  static String tableName({required bool rfi}) =>
      rfi ? kVisiteMedicheRfiTable : kVisiteMedicheTable;

  /// Disattiva automaticamente le visite con data precedente a oggi
  /// (quindi dal giorno dopo l'appuntamento in poi).
  static Future<void> _autoDeactivateExpiredVisits({required bool rfi}) async {
    final now = DateTime.now();
    final todayIso = _isoDateOnly(DateTime(now.year, now.month, now.day));
    try {
      await _supa
          .from(tableName(rfi: rfi))
          .update({'active': false})
          .eq('active', true)
          .lt('data_visita', todayIso);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadRows({
    String? onlyPersonaleUuid,
    bool upcomingOnly = false,
    bool rfi = false,
  }) async {
    await _autoDeactivateExpiredVisits(rfi: rfi);
    var q = _supa.from(tableName(rfi: rfi)).select().eq('active', true);
    if ((onlyPersonaleUuid ?? '').isNotEmpty) {
      q = q.eq('personale_id_uuid', onlyPersonaleUuid!);
    }
    final res = await q.order('data_visita', ascending: true);
    var list = List<Map<String, dynamic>>.from(
      (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    if (upcomingOnly) {
      final now = DateTime.now();
      list = list.where((r) {
        final dt = DateTime.tryParse(_s(r['data_visita']));
        if (dt == null) return true;
        return !dt.isBefore(DateTime(now.year, now.month, now.day));
      }).toList(growable: false);
    }
    return list;
  }

  static Future<String?> _ownPersonaleUuid({String? employeeFullName}) {
    return EmployeeProgrammazioneService.resolveOwnPersonaleUuid(
      employeeFullName: employeeFullName,
    );
  }

  static Future<bool> hasUpcomingStandardForCurrentUser({
    String? employeeFullName,
  }) async {
    final pid = await _ownPersonaleUuid(employeeFullName: employeeFullName);
    if (pid == null || pid.isEmpty) return false;
    try {
      final rows = await loadRows(
        onlyPersonaleUuid: pid,
        upcomingOnly: true,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasUpcomingRfiForCurrentUser({
    String? employeeFullName,
  }) async {
    final pid = await _ownPersonaleUuid(employeeFullName: employeeFullName);
    if (pid == null || pid.isEmpty) return false;
    try {
      final rows = await loadRows(
        onlyPersonaleUuid: pid,
        upcomingOnly: true,
        rfi: true,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// True se il dipendente ha almeno una visita programmata (standard o RFI).
  static Future<bool> hasUpcomingForCurrentUser({
    String? employeeFullName,
  }) async {
    try {
      if (await hasUpcomingStandardForCurrentUser(
        employeeFullName: employeeFullName,
      )) {
        return true;
      }
      return await hasUpcomingRfiForCurrentUser(
        employeeFullName: employeeFullName,
      );
    } catch (_) {
      return false;
    }
  }

  static bool isAllowedPdfName(String name) =>
      name.toLowerCase().trim().endsWith('.pdf');

  static String _sanitizePdfFileName(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final dot = trimmed.lastIndexOf('.');
    var stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    stem = stem.replaceAll(RegExp(r'\s+'), '_');
    stem = stem.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    stem = stem.replaceAll(RegExp(r'_+'), '_');
    stem = stem.replaceAll(RegExp(r'^_+|_+$'), '');
    if (stem.isEmpty) stem = 'visita_medica_rfi';
    return '$stem.pdf';
  }

  static Future<void> uploadPdf({
    required String visitId,
    required String originalFileName,
    required Uint8List bytes,
    String? previousFilePath,
  }) async {
    if (bytes.isEmpty) throw StateError('File vuoto');
    if (bytes.length > 50 * 1024 * 1024) {
      throw StateError('Il PDF supera i 50 MB');
    }
    if (!isAllowedPdfName(originalFileName)) {
      throw StateError('Formato non supportato. Carica un PDF.');
    }
    final displayName =
        originalFileName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final safeName = _sanitizePdfFileName(originalFileName);
    final path = '$visitId/$safeName';

    final prev = (previousFilePath ?? '').trim();
    if (prev.isNotEmpty && prev != path) {
      try {
        await _supa.storage.from(kVisiteMedicheRfiBucket).remove([prev]);
      } catch (_) {}
    }

    await _supa.storage.from(kVisiteMedicheRfiBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    await _supa.from(kVisiteMedicheRfiTable).update({
      'pdf_file_path': path,
      'pdf_file_name': displayName.isEmpty ? safeName : displayName,
      'pdf_mime_type': 'application/pdf',
      'pdf_file_size': bytes.length,
    }).eq('id_uuid', visitId);
  }

  static Future<void> clearPdf({
    required String visitId,
    required String? filePath,
  }) async {
    final path = (filePath ?? '').trim();
    if (path.isNotEmpty) {
      try {
        await _supa.storage.from(kVisiteMedicheRfiBucket).remove([path]);
      } catch (_) {}
    }
    await _supa.from(kVisiteMedicheRfiTable).update({
      'pdf_file_path': null,
      'pdf_file_name': null,
      'pdf_mime_type': null,
      'pdf_file_size': null,
    }).eq('id_uuid', visitId);
  }

  static Future<String> signedPdfUrl(
    Map<String, dynamic> row, {
    int expiresIn = 3600,
  }) async {
    final path = _s(row['pdf_file_path']);
    if (path.isEmpty) throw StateError('PDF non disponibile');
    return _supa.storage
        .from(kVisiteMedicheRfiBucket)
        .createSignedUrl(path, expiresIn);
  }

  static Future<Uint8List> downloadPdfBytes(Map<String, dynamic> row) async {
    final path = _s(row['pdf_file_path']);
    if (path.isEmpty) throw StateError('PDF non disponibile');
    return _supa.storage.from(kVisiteMedicheRfiBucket).download(path);
  }

  static bool hasPdf(Map<String, dynamic> row) =>
      _s(row['pdf_file_path']).isNotEmpty;
}
