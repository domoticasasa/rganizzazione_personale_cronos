import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../hub/app_ui_custom_hub.dart';
import 'app_ui_layout_service.dart';

/// Conteggio richieste ferie/permessi in attesa di approvazione admin.
abstract final class AssenzaRichiestePendingService {
  AssenzaRichiestePendingService._();

  static const richiesteFerieLayoutKey = 'richieste_ferie_permessi';
  static const _pendingAdminStatus = 'APPROVATA_DT';
  static const _tipiRichiesta = <String>['FERIE', 'PERMESSO'];

  static Future<int> countPendingAdminApproval(SupabaseClient client) async {
    try {
      final count = await client
          .from('dipendente_assenze')
          .count(CountOption.exact)
          .eq('active', true)
          .eq('segnalazione_admin', false)
          .eq('workflow_status', _pendingAdminStatus)
          .inFilter('tipo_assenza', _tipiRichiesta);
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Pulsanti da lampeggiare sulla dashboard admin (tile diretto + launcher hub).
  static Set<String> blinkKeysOnDashboard({
    required HubLayoutOrders orders,
    required List<AppUiCustomHub> customHubs,
    required String dashboardLayoutKey,
  }) {
    final dashKeys = orders.keysFor(dashboardLayoutKey);
    final out = <String>{};
    if (dashKeys.contains(richiesteFerieLayoutKey)) {
      out.add(richiesteFerieLayoutKey);
    }
    for (final hub in customHubs) {
      if (orders.keysFor(hub.layoutKey).contains(richiesteFerieLayoutKey) &&
          dashKeys.contains(hub.launcherKey)) {
        out.add(hub.launcherKey);
      }
    }
    return out;
  }

  /// Pulsante ferie/permessi dentro un hub secondario (es. Amministrazione/Personale).
  static Set<String> blinkKeysInHubLayout({
    required HubLayoutOrders orders,
    required String layoutKey,
  }) {
    if (!orders.keysFor(layoutKey).contains(richiesteFerieLayoutKey)) {
      return const <String>{};
    }
    return const {richiesteFerieLayoutKey};
  }

  static Color blinkIconColor({
    required String layoutKey,
    required Set<String> blinkKeys,
    required bool blinkOn,
    required Color fallback,
  }) {
    if (!blinkKeys.contains(layoutKey)) return fallback;
    return blinkOn ? Colors.red : fallback;
  }
}
