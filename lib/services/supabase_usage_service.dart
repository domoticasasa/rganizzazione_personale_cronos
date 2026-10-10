import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Piano usato solo come riferimento quota inclusa (Dashboard Billing).
enum SupabasePlanRef { free, pro }

extension SupabasePlanRefX on SupabasePlanRef {
  String get id => switch (this) {
        SupabasePlanRef.free => 'free',
        SupabasePlanRef.pro => 'pro',
      };

  String get label => switch (this) {
        SupabasePlanRef.free => 'Free',
        SupabasePlanRef.pro => 'Pro / Team',
      };

  /// Database incluso nel piano (byte).
  int get databaseLimitBytes => switch (this) {
        SupabasePlanRef.free => 500 * 1024 * 1024,
        SupabasePlanRef.pro => 8 * 1024 * 1024 * 1024,
      };

  /// File Storage incluso nel piano (byte).
  int get storageLimitBytes => switch (this) {
        SupabasePlanRef.free => 1 * 1024 * 1024 * 1024,
        SupabasePlanRef.pro => 100 * 1024 * 1024 * 1024,
      };

  /// MAU Auth inclusi (riferimento, non misurabile da Postgres).
  int get authMauLimit => switch (this) {
        SupabasePlanRef.free => 50000,
        SupabasePlanRef.pro => 100000,
      };

  static SupabasePlanRef fromId(String? id) {
    if (id == 'free') return SupabasePlanRef.free;
    return SupabasePlanRef.pro;
  }
}

class SupabaseUsageBucket {
  const SupabaseUsageBucket({
    required this.id,
    required this.files,
    required this.bytes,
  });

  final String id;
  final int files;
  final int bytes;

  factory SupabaseUsageBucket.fromJson(Map<String, dynamic> json) {
    return SupabaseUsageBucket(
      id: '${json['id'] ?? ''}',
      files: _asInt(json['files']),
      bytes: _asInt(json['bytes']),
    );
  }
}

class SupabaseUsageTable {
  const SupabaseUsageTable({
    required this.name,
    required this.bytes,
    required this.estRows,
  });

  final String name;
  final int bytes;
  final int estRows;

  factory SupabaseUsageTable.fromJson(Map<String, dynamic> json) {
    return SupabaseUsageTable(
      name: '${json['name'] ?? ''}',
      bytes: _asInt(json['bytes']),
      estRows: _asInt(json['est_rows']),
    );
  }
}

class SupabaseUsageSnapshot {
  const SupabaseUsageSnapshot({
    required this.checkedAt,
    required this.databaseBytes,
    required this.storageBytes,
    required this.authUsers,
    required this.appUsers,
    required this.tables,
    required this.buckets,
  });

  final DateTime? checkedAt;
  final int databaseBytes;
  final int storageBytes;
  final int authUsers;
  final int appUsers;
  final List<SupabaseUsageTable> tables;
  final List<SupabaseUsageBucket> buckets;

  int get totalBytes => databaseBytes + storageBytes;

  factory SupabaseUsageSnapshot.fromJson(Map<String, dynamic> json) {
    DateTime? at;
    final rawAt = json['checked_at'];
    if (rawAt is String && rawAt.isNotEmpty) {
      at = DateTime.tryParse(rawAt)?.toLocal();
    }
    return SupabaseUsageSnapshot(
      checkedAt: at,
      databaseBytes: _asInt(json['database_bytes']),
      storageBytes: _asInt(json['storage_bytes']),
      authUsers: _asInt(json['auth_users']),
      appUsers: _asInt(json['app_users']),
      tables: [
        for (final row in (json['tables'] as List? ?? const []))
          if (row is Map)
            SupabaseUsageTable.fromJson(Map<String, dynamic>.from(row)),
      ],
      buckets: [
        for (final row in (json['buckets'] as List? ?? const []))
          if (row is Map)
            SupabaseUsageBucket.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
}

class SupabaseUsageService {
  SupabaseUsageService._();

  static const _planPrefKey = 'cronos_supabase_plan_ref';

  static Future<SupabaseUsageSnapshot> fetch() async {
    final raw = await Supabase.instance.client.rpc('admin_supabase_usage');
    if (raw is Map) {
      return SupabaseUsageSnapshot.fromJson(Map<String, dynamic>.from(raw));
    }
    throw StateError('Risposta utilizzo non valida.');
  }

  static Future<SupabasePlanRef> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    return SupabasePlanRefX.fromId(prefs.getString(_planPrefKey));
  }

  static Future<void> savePlan(SupabasePlanRef plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_planPrefKey, plan.id);
  }
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}
