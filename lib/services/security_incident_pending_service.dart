import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../hub/app_ui_custom_hub.dart';
import 'app_ui_layout_service.dart';

/// Conteggio segnalazioni sicurezza non ancora «gestite» (hub blink).
abstract final class SecurityIncidentPendingService {
  SecurityIncidentPendingService._();

  static const incidentiLayoutKey = 'incidenti_sicurezza';
  static const impostazioniLauncherKey = 'impostazioni_app';

  static const openStatuses = <String>['aperto', 'in_lavorazione'];

  static Future<int> countOpenForAdmin(SupabaseClient client) async {
    try {
      final count = await client
          .from('security_incident_reports')
          .count(CountOption.exact)
          .inFilter('status', openStatuses);
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Dashboard: tile Incidenti se presente, altrimenti launcher Impostazioni.
  static Set<String> blinkKeysOnDashboard({
    required HubLayoutOrders orders,
    required List<AppUiCustomHub> customHubs,
    required String dashboardLayoutKey,
  }) {
    final dashKeys = orders.keysFor(dashboardLayoutKey);
    final out = <String>{};
    if (dashKeys.contains(incidentiLayoutKey)) {
      out.add(incidentiLayoutKey);
    }
    final inImpostazioni = orders
        .keysFor(AppUiLayoutService.layoutImpostazioniHub)
        .contains(incidentiLayoutKey);
    if (inImpostazioni || !dashKeys.contains(incidentiLayoutKey)) {
      out.add(impostazioniLauncherKey);
    }
    for (final hub in customHubs) {
      if (orders.keysFor(hub.layoutKey).contains(incidentiLayoutKey) &&
          dashKeys.contains(hub.launcherKey)) {
        out.add(hub.launcherKey);
      }
    }
    return out;
  }

  static Set<String> blinkKeysInHubLayout({
    required HubLayoutOrders orders,
    required String layoutKey,
  }) {
    if (!orders.keysFor(layoutKey).contains(incidentiLayoutKey)) {
      return const <String>{};
    }
    return const {incidentiLayoutKey};
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
