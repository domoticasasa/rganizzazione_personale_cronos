import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../hub/app_ui_custom_hub.dart';
import '../services/app_ui_layout_service.dart';
import '../services/assenza_richieste_pending_service.dart';
import '../services/hub_pending_poll_service.dart';
import '../services/security_incident_pending_service.dart';
import 'roles.dart';

/// Lampeggio tile hub: ferie/permessi da approvare + incidenti sicurezza aperti.
mixin HubAssenzeBlinkMixin<T extends StatefulWidget> on State<T> {
  bool hubAssenzeBlinkOn = true;
  Set<String> hubAssenzeBlinkKeys = const <String>{};
  Timer? _hubAssenzeBlinkTimer;

  Future<void> _hubAssenzePollTick() => refreshHubAssenzeBlink();

  String? get hubAssenzeBlinkRole;
  HubLayoutOrders? get hubAssenzeLayoutOrders;
  String get hubAssenzeCurrentLayoutKey;
  bool get hubAssenzeIsDashboardLayout =>
      hubAssenzeCurrentLayoutKey == AppUiLayoutService.layoutDashboardAdmin;

  void initHubAssenzeBlink() {
    _hubAssenzeBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted || hubAssenzeBlinkKeys.isEmpty) return;
      setState(() => hubAssenzeBlinkOn = !hubAssenzeBlinkOn);
    });
    HubPendingPollService.instance.attach(_hubAssenzePollTick);
    refreshHubAssenzeBlink();
  }

  void disposeHubAssenzeBlink() {
    _hubAssenzeBlinkTimer?.cancel();
    HubPendingPollService.instance.detach(_hubAssenzePollTick);
  }

  bool _canSeeSecurityIncidents(String role) {
    final n = normalizeRole(role);
    return n == 'admin' ||
        n == 'admin_generale' ||
        n == 'logistica' ||
        n == 'admin_vista';
  }

  Future<void> refreshHubAssenzeBlink({bool force = false}) async {
    final role = hubAssenzeBlinkRole ?? '';
    final canAssenze = canManageDipendenteAssenze(role);
    final canIncidents = _canSeeSecurityIncidents(role);

    if (!canAssenze && !canIncidents) {
      if (!mounted) return;
      setState(() {
        hubAssenzeBlinkKeys = const <String>{};
        hubAssenzeBlinkOn = true;
      });
      return;
    }

    final client = Supabase.instance.client;
    final pendingAssenze = canAssenze
        ? await HubPendingPollService.instance.assenzePendingCount(
            client,
            force: force,
          )
        : 0;
    final pendingIncidents = canIncidents
        ? await HubPendingPollService.instance.securityIncidentsOpenCount(
            client,
            force: force,
          )
        : 0;
    if (!mounted) return;

    if (pendingAssenze <= 0 && pendingIncidents <= 0) {
      setState(() {
        hubAssenzeBlinkKeys = const <String>{};
        hubAssenzeBlinkOn = true;
      });
      return;
    }

    final orders = hubAssenzeLayoutOrders;
    final keys = <String>{};

    List<AppUiCustomHub> customHubs = const <AppUiCustomHub>[];
    if (hubAssenzeIsDashboardLayout &&
        (pendingAssenze > 0 || pendingIncidents > 0)) {
      customHubs = await AppUiLayoutService.loadCustomHubs();
      if (!mounted) return;
    }

    if (pendingAssenze > 0) {
      if (orders == null) {
        keys.add(AssenzaRichiestePendingService.richiesteFerieLayoutKey);
      } else if (hubAssenzeIsDashboardLayout) {
        keys.addAll(
          AssenzaRichiestePendingService.blinkKeysOnDashboard(
            orders: orders,
            customHubs: customHubs,
            dashboardLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
          ),
        );
      } else {
        keys.addAll(
          AssenzaRichiestePendingService.blinkKeysInHubLayout(
            orders: orders,
            layoutKey: hubAssenzeCurrentLayoutKey,
          ),
        );
      }
    }

    if (pendingIncidents > 0) {
      if (orders == null) {
        if (hubAssenzeIsDashboardLayout) {
          keys.add(SecurityIncidentPendingService.impostazioniLauncherKey);
        } else if (hubAssenzeCurrentLayoutKey ==
            AppUiLayoutService.layoutImpostazioniHub) {
          keys.add(SecurityIncidentPendingService.incidentiLayoutKey);
        }
      } else if (hubAssenzeIsDashboardLayout) {
        keys.addAll(
          SecurityIncidentPendingService.blinkKeysOnDashboard(
            orders: orders,
            customHubs: customHubs,
            dashboardLayoutKey: AppUiLayoutService.layoutDashboardAdmin,
          ),
        );
      } else {
        keys.addAll(
          SecurityIncidentPendingService.blinkKeysInHubLayout(
            orders: orders,
            layoutKey: hubAssenzeCurrentLayoutKey,
          ),
        );
      }
    }

    setState(() {
      hubAssenzeBlinkKeys = keys;
      if (keys.isEmpty) hubAssenzeBlinkOn = true;
    });
  }

  Color hubAssenzeIconColor(String layoutKey, Color fallback) {
    return AssenzaRichiestePendingService.blinkIconColor(
      layoutKey: layoutKey,
      blinkKeys: hubAssenzeBlinkKeys,
      blinkOn: hubAssenzeBlinkOn,
      fallback: fallback,
    );
  }
}
