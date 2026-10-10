import '../utils/date_formatters.dart';
import '../utils/formazione_programmazione_dates.dart';
import 'formazione_dlgs_strutture_service.dart';
import 'supabase_service.dart';

/// Campi «programmazione corso» (blocco ODA / data / modalità) su [formazione_corsi].
abstract final class FormazioneProgrammazioneService {
  static const List<String> fieldKeys = <String>[
    'prima_data',
    'seconda_data',
    'oda',
    'orario',
    'modalita',
    'struttura_dlgs_id',
    'struttura_nome',
    'struttura_indirizzo',
    'struttura_email',
    'struttura_link',
    'note',
  ];

  static Map<String, dynamic> clearPayload() => <String, dynamic>{
        'prima_data': null,
        'seconda_data': null,
        'oda': null,
        'orario': null,
        'modalita': null,
        ...FormazioneDlgsStruttureService.clearCorsoStrutturaPayload(),
        'note': null,
        'updated_at': supabaseNowIsoUtc(),
      };

  static bool hasAnyField(Map<String, dynamic> row) {
    for (final k in fieldKeys) {
      if ((row[k] ?? '').toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  /// `true` se oggi è dal giorno successivo a [endDate] (fine corso + 1 giorno).
  static bool shouldClearAfterCourseEnd(DateTime endDate, DateTime today) {
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final ref = DateTime(today.year, today.month, today.day);
    final hideFrom = end.add(const Duration(days: 1));
    return !ref.isBefore(hideFrom);
  }

  static DateTime? parseDateOnly(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  /// Dopo la fine programmazione (+1 giorno) il corso non compare più in elenco.
  static bool shouldClearAfterProgrammazione(
    Map<String, dynamic> row,
    DateTime today,
  ) {
    final prima = parseDateOnly(row['prima_data']);
    if (prima == null) return false;
    final end =
        programmazioneEndDate(row['prima_data'], row['seconda_data']) ?? prima;
    return shouldClearAfterCourseEnd(end, today);
  }

  /// Azzera i campi programmazione sui corsi scaduti (fine corso + 1 giorno).
  static Future<int> purgeExpiredFromRows(
    Iterable<Map<String, dynamic>> rows, {
    DateTime? referenceDay,
  }) async {
    final now = referenceDay ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var cleared = 0;
    for (final row in rows) {
      if (!shouldClearAfterProgrammazione(row, today)) continue;
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      try {
        await SupabaseService.client
            .from('formazione_corsi')
            .update(clearPayload())
            .eq('id', id);
        cleared++;
      } catch (_) {}
    }
    return cleared;
  }
}
