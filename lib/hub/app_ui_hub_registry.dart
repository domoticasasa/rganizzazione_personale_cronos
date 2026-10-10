import 'package:flutter/foundation.dart';

import '../services/app_ui_layout_service.dart';

import 'app_ui_custom_hub.dart';



/// Hub disponibili per spostare i pulsanti (ordine salvato in Supabase).

class AppUiHubTarget {

  const AppUiHubTarget({required this.layoutKey, required this.label});



  final String layoutKey;

  final String label;

}



abstract final class AppUiHubRegistry {

  static const List<AppUiHubTarget> _builtIn = <AppUiHubTarget>[

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutDashboardAdmin,

      label: 'Dashboard',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutDashboardAdminFuturistic,

      label: 'Dashboard futuristica',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutLogisticaHub,

      label: 'Logistica',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutCarburanteHub,

      label: 'Carburante',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutUqsaHub,

      label: 'UQSA',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutListePosHub,

      label: 'Liste POS',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutImpostazioniHub,

      label: 'Impostazioni',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutHomeMain,

      label: 'Home',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutHomeAdmin,

      label: 'Home admin',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutHomeDt,

      label: 'Home DT',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutHomeDtFuturistic,

      label: 'Home DT GESTOPRO',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutHomeDipendente,

      label: 'Area dipendente',

    ),

    AppUiHubTarget(

      layoutKey: AppUiLayoutService.layoutDpiHub,

      label: 'DPI e Vestiario',

    ),

  ];



  static List<AppUiHubTarget> _custom = <AppUiHubTarget>[];

  /// Etichette personalizzate (custom_label tile) per layoutKey / launcherKey.
  static Map<String, String> _labelOverrides = <String, String>{};

  /// Incrementato quando cambiano etichette hub (per aggiornare barre spostamento).
  static final ValueNotifier<int> labelsRevision = ValueNotifier<int>(0);

  static void _notifyLabelsChanged() {
    labelsRevision.value++;
  }

  static List<AppUiHubTarget> get all {
    AppUiHubTarget withOverride(AppUiHubTarget h) => AppUiHubTarget(
          layoutKey: h.layoutKey,
          label: _resolveLabel(h.layoutKey, h.label),
        );
    return List<AppUiHubTarget>.unmodifiable([
      ..._builtIn.map(withOverride),
      ..._custom.map(withOverride),
    ]);
  }

  static void bindCustomHubs(List<AppUiCustomHub> hubs) {
    _custom = hubs
        .map(
          (h) => AppUiHubTarget(layoutKey: h.layoutKey, label: h.label),
        )
        .toList(growable: false);
    _notifyLabelsChanged();
  }

  /// Applica override da [app_ui_tile_styles.custom_label] (chiave = item_key o layout hub).
  static void bindLabelOverrides(Map<String, String> overrides) {
    _labelOverrides = Map<String, String>.from(overrides);
    _notifyLabelsChanged();
  }

  static String _resolveLabel(String layoutKey, String defaultLabel) {
    final o = _labelOverrides[layoutKey]?.trim();
    if (o != null && o.isNotEmpty) return o;
    return defaultLabel;
  }

  static List<AppUiHubTarget> targetsExcept(String currentLayoutKey) {
    return all.where((h) => h.layoutKey != currentLayoutKey).toList(growable: false);
  }

  static String labelFor(String layoutKey) {
    for (final h in all) {
      if (h.layoutKey == layoutKey) return h.label;
    }
    final o = _labelOverrides[layoutKey]?.trim();
    if (o != null && o.isNotEmpty) return o;
    return layoutKey;
  }

}


