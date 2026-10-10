import '../utils/date_formatters.dart';
import 'supabase_service.dart';

class FormazioniRepository {
  /// Restituisce il link formazione per utente_id, oppure null.
  static Future<String?> getForUser(String userUuid) async {
    if (userUuid.isEmpty) return null;
    try {
      final r = await SupabaseService.client
          .from('formazioni')
          .select('url_formazione')
          .eq('utente_id', userUuid)
          .maybeSingle();
      final link = r?['url_formazione']?.toString().trim() ?? '';
      return link.isNotEmpty ? link : null;
    } catch (_) {
      return null;
    }
  }

  /// Salva (upsert) il link formazione dell’utente.
  static Future<void> setForUser(String userUuid, String url) async {
    if (userUuid.isEmpty) return;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final exists = await SupabaseService.client
        .from('formazioni')
        .select('id')
        .eq('utente_id', userUuid)
        .maybeSingle();

    if (exists == null) {
      await SupabaseService.client.from('formazioni').insert({
        'utente_id': userUuid,
        'url_formazione': trimmed,
      });
    } else {
      await SupabaseService.client
          .from('formazioni')
          .update({'url_formazione': trimmed, 'updated_at': supabaseNowIsoUtc()})
          .eq('utente_id', userUuid);
    }
  }

  /// Cancella il link formazione dell’utente.
  static Future<void> deleteForUser(String userUuid) async {
    if (userUuid.isEmpty) return;
    await SupabaseService.client
        .from('formazioni')
        .delete()
        .eq('utente_id', userUuid);
  }
}
