import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AppActivityLog {
  const AppActivityLog({
    required this.id,
    required this.createdAt,
    required this.createdAtRaw,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.action,
    required this.detail,
  });

  final int id;
  final DateTime? createdAt;
  final dynamic createdAtRaw;
  final int? userId;
  final String fullName;
  final String username;
  final String role;
  final String action;
  final String detail;

  factory AppActivityLog.fromMap(Map<String, dynamic> m) {
    final createdRaw = m['created_at'];
    DateTime? at;
    if (createdRaw is DateTime) {
      at = createdRaw.toUtc();
    } else {
      at = DateTime.tryParse('$createdRaw')?.toUtc();
    }
    return AppActivityLog(
      id: (m['id'] as num?)?.toInt() ?? 0,
      createdAt: at,
      createdAtRaw: createdRaw,
      userId: (m['user_id'] as num?)?.toInt(),
      fullName: (m['full_name'] ?? '').toString().trim(),
      username: (m['username'] ?? '').toString().trim(),
      role: (m['role'] ?? '').toString().trim(),
      action: (m['action'] ?? 'app_open').toString().trim(),
      detail: (m['detail'] ?? '').toString().trim(),
    );
  }

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return '—';
  }
}

/// Lettura log app (Impostazioni). La scrittura avviene lato SQL all'accesso.
abstract final class AppActivityLogService {
  AppActivityLogService._();

  static const missingSchemaMessage =
      'Manca la tabella log su Supabase. Apri SQL Editor del progetto '
      'e esegui il file supabase/migrations/20260825120000_app_activity_logs.sql, '
      'poi ricarica questa pagina.';

  static bool isMissingSchema(Object error) {
    final msg = error.toString();
    return (msg.contains('app_activity_logs') ||
            msg.contains('admin_list_app_activity_logs')) &&
        (msg.contains('PGRST205') ||
            msg.contains('PGRST202') ||
            msg.contains('42P01') ||
            msg.contains('42883') ||
            msg.contains('Could not find'));
  }

  static String formatLoadError(Object error) {
    if (isMissingSchema(error)) return missingSchemaMessage;
    return error.toString();
  }

  /// Scrittura best-effort (export, ecc.). Non deve mai bloccare l'azione.
  static Future<void> record({
    required String action,
    String detail = '',
  }) async {
    final a = action.trim();
    if (a.isEmpty) return;
    try {
      await SupabaseService.client.rpc(
        'record_my_app_activity',
        params: <String, dynamic>{
          'p_action': a,
          'p_detail': detail.trim(),
        },
      );
    } catch (_) {}
  }

  static const String actionUserCreate = 'user_create';
  static const String actionUserDelete = 'user_delete';

  static String _detailParts(Iterable<String> parts) => parts
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join(' · ');

  static Future<void> recordUserCreate({
    required String fullName,
    String email = '',
    String role = '',
    bool login = false,
  }) {
    return record(
      action: actionUserCreate,
      detail: _detailParts([
        login ? 'Login' : 'Anagrafica',
        fullName,
        email,
        if (role.trim().isNotEmpty) 'ruolo ${role.trim()}',
      ]),
    );
  }

  static Future<void> recordUserDelete({
    required String fullName,
    String email = '',
  }) {
    return record(
      action: actionUserDelete,
      detail: _detailParts([fullName, email]),
    );
  }

  static Future<List<AppActivityLog>> list({
    String? name,
    String? role,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    try {
      final res = await SupabaseService.client.rpc(
        'admin_list_app_activity_logs',
        params: <String, dynamic>{
          'p_name': (name ?? '').trim(),
          'p_role': (role ?? '').trim(),
          'p_from': fromUtc?.toUtc().toIso8601String(),
          'p_to': toUtc?.toUtc().toIso8601String(),
        },
      ) as List;
      return [
        for (final raw in res)
          AppActivityLog.fromMap(Map<String, dynamic>.from(raw as Map)),
      ];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') {
        try {
          return await _listFromTable(
            name: name,
            role: role,
            fromUtc: fromUtc,
            toUtc: toUtc,
          );
        } on PostgrestException catch (e2) {
          if (isMissingSchema(e2)) {
            throw StateError(missingSchemaMessage);
          }
          rethrow;
        }
      }
      if (isMissingSchema(e)) {
        throw StateError(missingSchemaMessage);
      }
      rethrow;
    }
  }

  static Future<List<AppActivityLog>> _listFromTable({
    String? name,
    String? role,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    var q = SupabaseService.client
        .from('app_activity_logs')
        .select('id, created_at, user_id, full_name, username, role, action, detail');
    if (fromUtc != null) {
      q = q.gte('created_at', fromUtc.toUtc().toIso8601String());
    }
    if (toUtc != null) {
      q = q.lte('created_at', toUtc.toUtc().toIso8601String());
    }
    final res = await q.order('created_at', ascending: false).limit(2000) as List;
    var list = [
      for (final raw in res)
        AppActivityLog.fromMap(Map<String, dynamic>.from(raw as Map)),
    ];
    final n = (name ?? '').trim().toLowerCase();
    final r = (role ?? '').trim().toLowerCase();
    if (n.isNotEmpty) {
      list = list
          .where(
            (e) =>
                e.fullName.toLowerCase().contains(n) ||
                e.username.toLowerCase().contains(n),
          )
          .toList(growable: false);
    }
    if (r.isNotEmpty) {
      list = list.where((e) => e.role.toLowerCase() == r).toList(growable: false);
    }
    return list;
  }
}
