import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/admin_vista_guard.dart';

/// Pulizia dati storici tramite RPC Supabase (security definer sul server).
class DataCleanupService {
  DataCleanupService._();

  /// Giorni conservati in `notifications` (allineato a cleanup_notifications su Supabase).
  static const int notificationRetentionDays = 10;

  /// Soglia ISO8601 UTC per filtrare le query client (solo notifiche recenti).
  static String notificationRetentionCutoffIso() {
    final cutoff = DateTime.now().toUtc().subtract(
      const Duration(days: notificationRetentionDays),
    );
    return cutoff.toIso8601String();
  }

  static Future<int> runRpc(String rpcName) async {
    await ensureCanPersistOrThrow();
    final raw = await Supabase.instance.client.rpc(rpcName);
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return int.tryParse('$raw') ?? 0;
  }

  static Future<int> cleanupNotifications() => runRpc('cleanup_notifications');

  static Future<int> cleanupPernottamenti() => runRpc('cleanup_pernottamenti');

  static Future<int> cleanupTreni() => runRpc('cleanup_treni');

  static Future<int> cleanupAereo() => runRpc('cleanup_aereo');

  /// Totale righe attuali in `notifications` (admin: policy lettura globale).
  static Future<int> countNotifications() async {
    final count = await Supabase.instance.client
        .from('notifications')
        .count(CountOption.exact);
    return count;
  }
}
