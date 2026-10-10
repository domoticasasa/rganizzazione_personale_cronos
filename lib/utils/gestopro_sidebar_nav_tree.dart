import '../services/app_ui_layout_service.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';

/// Mappa layout hub → chiave tile che lo apre (dashboard o hub padre).
String? hubLauncherKeyForLayout(String hubLayoutKey) {
  switch (hubLayoutKey) {
    case AppUiLayoutService.layoutUqsaHub:
      return 'uqsa';
    case AppUiLayoutService.layoutDpiHub:
      return 'dpi_hub';
    case AppUiLayoutService.layoutLogisticaHub:
      return 'logistica';
    case AppUiLayoutService.layoutCarburanteHub:
      return 'carburante';
    case AppUiLayoutService.layoutImpostazioniHub:
      return 'impostazioni_app';
    case AppUiLayoutService.layoutListePosHub:
      return 'liste_pos_hub';
    default:
      return null;
  }
}

bool containsNavKeyRecursive(
  List<FuturisticNavSubItem> items,
  String key,
) {
  for (final item in items) {
    if (item.key == key) return true;
    if (item.children.isNotEmpty && containsNavKeyRecursive(item.children, key)) {
      return true;
    }
  }
  return false;
}

List<FuturisticNavSubItem> attachNavChildrenRecursive(
  List<FuturisticNavSubItem> items,
  String parentKey,
  List<FuturisticNavSubItem> children,
) {
  return [
    for (final item in items)
      if (item.key == parentKey)
        item.copyWith(children: children)
      else if (item.children.isNotEmpty)
        item.copyWith(
          children: attachNavChildrenRecursive(
            item.children,
            parentKey,
            children,
          ),
        )
      else
        item,
  ];
}
