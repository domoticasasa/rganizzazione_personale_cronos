import '../services/app_ui_layout_service.dart';

/// Chiavi pulsanti Home admin (ordine in [layoutHomeAdmin]).
abstract final class HomeAdminButtonKeys {
  static const String layoutKey = AppUiLayoutService.layoutHomeAdmin;

  static const List<String> defaults = <String>[
    'pernottamenti',
    'treni',
    'aerei',
    'admin_dashboard',
  ];
}
