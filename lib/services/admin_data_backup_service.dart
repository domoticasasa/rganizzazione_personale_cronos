import 'package:supabase_flutter/supabase_flutter.dart';

class DataBackupRun {
  const DataBackupRun({
    required this.id,
    required this.backupDate,
    required this.startedAt,
    this.finishedAt,
    this.ok,
    this.tablesCount,
    this.rowsCount,
    this.storagePrefix,
    this.errorMessage,
    this.secondaryOk,
    this.secondaryProvider,
    this.secondaryError,
    this.triggerSource,
  });

  final int id;
  final String backupDate;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool? ok;
  final int? tablesCount;
  final int? rowsCount;
  final String? storagePrefix;
  final String? errorMessage;
  final bool? secondaryOk;
  final String? secondaryProvider;
  final String? secondaryError;
  final String? triggerSource;

  factory DataBackupRun.fromMap(Map<String, dynamic> m) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return DataBackupRun(
      id: parseInt(m['id']) ?? 0,
      backupDate: (m['backup_date'] ?? '').toString().trim(),
      startedAt: parseTs(m['started_at']),
      finishedAt: parseTs(m['finished_at']),
      ok: m['ok'] is bool ? m['ok'] as bool : null,
      tablesCount: parseInt(m['tables_count']),
      rowsCount: parseInt(m['rows_count']),
      storagePrefix: (m['storage_prefix'] ?? '').toString().trim().isEmpty
          ? null
          : (m['storage_prefix'] ?? '').toString().trim(),
      errorMessage: (m['error_message'] ?? '').toString().trim().isEmpty
          ? null
          : (m['error_message'] ?? '').toString().trim(),
      secondaryOk: m['secondary_ok'] is bool ? m['secondary_ok'] as bool : null,
      secondaryProvider:
          (m['secondary_provider'] ?? '').toString().trim().isEmpty
              ? null
              : (m['secondary_provider'] ?? '').toString().trim(),
      secondaryError: (m['secondary_error'] ?? '').toString().trim().isEmpty
          ? null
          : (m['secondary_error'] ?? '').toString().trim(),
      triggerSource: (m['trigger_source'] ?? '').toString().trim().isEmpty
          ? null
          : (m['trigger_source'] ?? '').toString().trim(),
    );
  }

  bool get isSuccess => ok == true;
  bool get isFailed => ok == false;
  bool get isRunning => ok == null && finishedAt == null;
  bool get hasSecondaryCopy => secondaryOk == true;

  String get triggerLabelIt {
    switch ((triggerSource ?? '').toLowerCase()) {
      case 'pg_cron':
        return 'Automatico (notte)';
      case 'github_actions':
        return 'Automatico (GitHub)';
      case 'admin-data-backup':
        return 'Manuale';
      default:
        return triggerSource == null || triggerSource!.isEmpty
            ? '—'
            : triggerSource!;
    }
  }
}

/// Origine file backup per dettaglio / ripristino.
enum BackupCopySource {
  primary,
  secondary,
}

extension BackupCopySourceX on BackupCopySource {
  String get apiValue => this == BackupCopySource.secondary ? 'secondary' : 'primary';

  String get labelIt =>
      this == BackupCopySource.secondary ? 'copia secondaria' : 'copia primaria';
}

class AdminDataBackupService {
  AdminDataBackupService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<DataBackupRun>> listRuns() async {
    final res = await _client
        .from('data_backup_runs')
        .select(
          'id, backup_date, started_at, finished_at, ok, tables_count, rows_count, '
          'storage_prefix, error_message, secondary_ok, secondary_provider, secondary_error, '
          'trigger_source',
        )
        .order('backup_date', ascending: false)
        .limit(40);
    return (res as List)
        .map((e) => DataBackupRun.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body,
  ) async {
    final res = await _client.functions.invoke(
      'admin-data-backup',
      body: body,
    );
    final data = res.data;
    if (data is! Map) {
      throw StateError('Risposta backup non valida (${res.status})');
    }
    final map = Map<String, dynamic>.from(data);
    if (res.status != 200 || map['error'] != null) {
      throw StateError(
        (map['error'] ?? 'Operazione backup fallita (${res.status})').toString(),
      );
    }
    return map;
  }

  static Future<Map<String, dynamic>> runBackup({
    required String confirmPassword,
  }) {
    return _invoke({
      'action': 'run',
      'confirm_password': confirmPassword,
    });
  }

  static Future<Map<String, dynamic>> loadManifest({
    required String backupDate,
    required String confirmPassword,
    BackupCopySource source = BackupCopySource.primary,
  }) {
    return _invoke({
      'action': 'manifest',
      'backup_date': backupDate,
      'confirm_password': confirmPassword,
      'source': source.apiValue,
    });
  }

  static Future<Map<String, dynamic>> restoreBackup({
    required String backupDate,
    required String confirmPassword,
    required String confirmPhrase,
    BackupCopySource source = BackupCopySource.primary,
  }) {
    return _invoke({
      'action': 'restore',
      'backup_date': backupDate,
      'confirm_password': confirmPassword,
      'confirm_phrase': confirmPhrase,
      'source': source.apiValue,
    });
  }
}
