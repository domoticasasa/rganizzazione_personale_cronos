import '../services/app_ui_layout_service.dart';

/// Chiavi pulsanti Home DT / Assistente DT (ordine in [layoutHomeDt]).
abstract final class HomeDtButtonKeys {
  static const String layoutKey = AppUiLayoutService.layoutHomeDt;

  static const List<String> defaults = <String>[
    'uqsa',
    'pernottamenti',
    'treni',
    'aerei',
    'richieste_da_approvare',
    'programmazione_formazioni',
    'programmazione_formazioni_rfi',
    'scadenze_alert',
    'formazione_rfi',
    'logistica',
    'carburante',
    'mdo_mappa_gps',
    'bacheca',
    'formazione_dlgs_81_08',
    'permessi_assistenti_dt',
    'visite_mediche',
    'rubrica',
    'commesse_cig_cup',
    'segnalazione_assenze',
  ];
}
