import 'package:flutter/foundation.dart';

import '../utils/date_formatters.dart';
import 'formazione_programmazione_service.dart';
import 'supabase_service.dart';
/// Impostazioni globali programmazione corsi (Supabase).
abstract final class FormazioneProgrammazioneConfigService {
  FormazioneProgrammazioneConfigService._();

  static const String _rfiAutoPurgeKey = 'rfi_auto_purge_after_course_end';

  static bool _rfiAutoPurgeAfterCourseEnd = true;

  static bool get rfiAutoPurgeAfterCourseEnd => _rfiAutoPurgeAfterCourseEnd;

  static Future<bool> loadRfiAutoPurge() async {
    try {
      final row = await SupabaseService.client
          .from('formazione_programmazione_config')
          .select('config_value')
          .eq('config_key', _rfiAutoPurgeKey)
          .maybeSingle();
      if (row != null) {
        _rfiAutoPurgeAfterCourseEnd = _readBool(row['config_value'], defaultValue: true);
      }
    } catch (_) {
      _rfiAutoPurgeAfterCourseEnd = true;
    }
    return _rfiAutoPurgeAfterCourseEnd;
  }

  static Future<void> setRfiAutoPurge(bool enabled) async {
    await SupabaseService.client.from('formazione_programmazione_config').upsert(
      <String, dynamic>{
        'config_key': _rfiAutoPurgeKey,
        'config_value': enabled,
        'updated_at': supabaseNowIsoUtc(),
      },
      onConflict: 'config_key',
    );
    _rfiAutoPurgeAfterCourseEnd = enabled;
  }

  static bool shouldHideRfiRowAfterCourseEnd(
    Map<String, dynamic> row,
    DateTime today,
  ) {
    if (!_rfiAutoPurgeAfterCourseEnd) return false;
    return FormazioneProgrammazioneService.shouldClearAfterProgrammazione(
      row,
      today,
    );
  }

  static bool _readBool(dynamic value, {required bool defaultValue}) {
    if (value is bool) return value;
    final s = (value ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  @visibleForTesting
  static void setRfiAutoPurgeForTests(bool enabled) {
    _rfiAutoPurgeAfterCourseEnd = enabled;
  }
}
