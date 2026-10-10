import '../services/app_ui_layout_service.dart';

/// Chiavi pulsanti Home principale (ordine in [layoutHomeMain]).
abstract final class HomeMainButtonKeys {
  static const String layoutKey = AppUiLayoutService.layoutHomeMain;

  static const List<String> defaults = <String>[
    'pernottamenti',
    'treni',
    'aerei',
    'admin_dashboard',
    'richieste_da_approvare',
    'programmazione_formazioni',
    'programmazione_formazioni_rfi',
    'visite_mediche',
    'segnalazione_assenze',
    'scadenze_alert',
    'formazione_rfi',
    'logistica',
    'mdo_ferroviari',
    'mezzi_stradali',
    'formazione_dlgs_81_08',
    'pos_dipendenti_lista',
    'pos_mdo_ferroviari_lista',
    'pos_mezzi_stradali_lista',
    'pos_mdo_proprieta_lista',
    'uqsa',
    'permessi_assistenti_dt',
  ];
}
