import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import '../utils/module_visibility_flags.dart';

/// Chiavi pulsanti area dipendente (ordine salvato in [layoutHomeDipendente]).
abstract final class DipendenteHomeButtonKeys {
  static const String layoutKey = AppUiLayoutService.layoutHomeDipendente;

  static const List<String> defaults = <String>[
    'emp_treni',
    'emp_aerei',
    'emp_notifiche',
    'emp_pernottamenti',
    'emp_tesserino',
    'emp_i_miei_dati',
    'emp_documenti_firma',
    'emp_bacheca',
    'emp_video_istruzioni',
    'emp_formazione',
    'emp_visita_medica',
    'emp_sicurezza',
    'emp_mezzi',
    'emp_rifornimento',
    'emp_attrezzature',
    'emp_mappa_gps',
    'emp_incidente_sicurezza',
    'emp_buoni_pasto',
    'emp_viaggi_mezzi',
  ];

  /// Filtra chiavi nascoste da [ModuleVisibilityFlags] (ripristino = flag true).
  static List<String> applyVisibility(List<String> keys) {
    if (ModuleVisibilityFlags.showEmpLeMieFeriePermessi) {
      return List<String>.from(keys);
    }
    return keys
        .where((k) => k != 'emp_richiedi_ferie_permessi')
        .toList(growable: false);
  }

  static const Set<String> filledStyle = <String>{
    'emp_treni',
    'emp_aerei',
    'emp_richiedi_ferie_permessi',
    'emp_notifiche',
    'emp_pernottamenti',
    'emp_tesserino',
    'emp_i_miei_dati',
  };

  static const Map<String, String> labels = <String, String>{
    'emp_richiedi_treno': 'Treni',
    'emp_richiedi_aereo': 'Aerei',
    'emp_richiedi_ferie_permessi': 'Le mie ferie / permessi',
    'emp_notifiche': 'Notifiche',
    'emp_treni': 'Treni',
    'emp_aerei': 'Aerei',
    'emp_pernottamenti': 'Pernottamenti',
    'emp_tesserino': 'Il mio tesserino',
    'emp_i_miei_dati': 'I miei dati',
    'emp_documenti_firma': 'Firma digitale',
    'emp_bacheca': 'Bacheca',
    'emp_video_istruzioni': 'Video istruttivi',
    'emp_formazione': 'Formazione',
    'emp_formazione_scadenze': 'Formazione e Scadenze',
    'emp_formazione_rfi_scadenze': 'Formazione RFI',
    'emp_programmazione_formazioni': 'Programmazione Formazioni',
    'emp_programmazione_formazioni_rfi': 'Programmazioni corsi RFI',
    'emp_visita_medica': 'Visita medica',
    'emp_sicurezza': 'Sicurezza',
    'emp_dpi': 'Dotazioni DPI',
    'emp_misure_vestiario': 'Misure vestiario',
    'emp_mezzi': 'Mezzi',
    'emp_mdo_ferroviari': 'MDO Ferroviari',
    'emp_mezzi_stradali': 'Mezzi Stradali',
    'emp_rifornimento': 'Rifornimento',
    'emp_registro_rcc': 'Registro carburante RCC',
    'emp_rifornimento_mdo': 'Rifornimento MDO',
    'emp_multicard': 'Multicard',
    'emp_attrezzature': 'Attrezzature',
    'emp_mappa_gps': 'Mappa GPS',
    'mdo_mappa_gps': 'Mappa GPS',
    'emp_incidente_sicurezza': 'Incidenti sicurezza',
    'emp_buoni_pasto': 'Buoni Pasto',
    'emp_buoni_pasto_scan': 'Scansiona buono pasto',
    'emp_buoni_pasto_riepilogo': 'I miei buoni pasto',
    'emp_viaggi_mezzi': 'Viaggi mezzi',
    'emp_viaggi_mezzi_scan': 'Scansiona viaggio mezzo',
    'emp_viaggi_mezzi_riepilogo': 'I miei viaggi mezzo',
    'emp_viaggi_mezzi_assegnatario': 'Viaggi sui miei mezzi',
  };

  static String labelFor(String key) => labels[key] ?? key;

  static const Map<String, IconData> icons = <String, IconData>{
    'emp_richiedi_treno': Icons.train_outlined,
    'emp_richiedi_aereo': Icons.flight_takeoff_outlined,
    'emp_richiedi_ferie_permessi': Icons.event_busy_outlined,
    'emp_notifiche': Icons.notifications_outlined,
    'emp_treni': Icons.train_outlined,
    'emp_aerei': Icons.flight_takeoff_outlined,
    'emp_pernottamenti': Icons.bed_outlined,
    'emp_tesserino': Icons.badge_outlined,
    'emp_i_miei_dati': Icons.phone_android_outlined,
    'emp_documenti_firma': Icons.fingerprint,
    'emp_bacheca': Icons.campaign_outlined,
    'emp_video_istruzioni': Icons.ondemand_video_outlined,
    'emp_formazione': Icons.school_outlined,
    'emp_formazione_scadenze': Icons.school_outlined,
    'emp_formazione_rfi_scadenze': Icons.account_tree_outlined,
    'emp_programmazione_formazioni': Icons.event_note_outlined,
    'emp_programmazione_formazioni_rfi': Icons.event_available_outlined,
    'emp_visita_medica': Icons.medical_services_outlined,
    'emp_sicurezza': Icons.health_and_safety_outlined,
    'emp_dpi': Icons.shield_outlined,
    'emp_misure_vestiario': Icons.straighten,
    'emp_mezzi': Icons.commute_outlined,
    'emp_mdo_ferroviari': Icons.train_outlined,
    'emp_mezzi_stradali': Icons.local_shipping_outlined,
    'emp_rifornimento': Icons.local_gas_station_outlined,
    'emp_registro_rcc': Icons.local_gas_station_outlined,
    'emp_rifornimento_mdo': Icons.local_gas_station_outlined,
    'emp_multicard': Icons.credit_card_outlined,
    'emp_attrezzature': Icons.handyman_outlined,
    'emp_mappa_gps': Icons.map_outlined,
    'mdo_mappa_gps': Icons.map_outlined,
    'emp_incidente_sicurezza': Icons.report_gmailerrorred_outlined,
    'emp_buoni_pasto': Icons.restaurant_outlined,
    'emp_buoni_pasto_scan': Icons.qr_code_scanner_outlined,
    'emp_buoni_pasto_riepilogo': Icons.restaurant_outlined,
    'emp_viaggi_mezzi': Icons.route_outlined,
    'emp_viaggi_mezzi_scan': Icons.qr_code_scanner,
    'emp_viaggi_mezzi_riepilogo': Icons.route_outlined,
    'emp_viaggi_mezzi_assegnatario': Icons.local_shipping_outlined,
  };

  static IconData iconFor(String key) => icons[key] ?? Icons.widgets_outlined;

  static bool isPrimaryStyle(String key) => filledStyle.contains(key);

  static const Set<String> rifornimentoLegacyKeys = <String>{
    'emp_registro_rcc',
    'emp_rifornimento_mdo',
    'emp_multicard',
  };

  /// Ex «Richiedi treno» → unificato in [emp_treni].
  static const Set<String> treniLegacyKeys = <String>{
    'emp_richiedi_treno',
  };

  /// Ex «Richiedi aereo» → unificato in [emp_aerei].
  static const Set<String> aereiLegacyKeys = <String>{
    'emp_richiedi_aereo',
  };

  static const Set<String> formazioneLegacyKeys = <String>{
    'emp_formazione_scadenze',
    'emp_formazione_rfi_scadenze',
    'emp_programmazione_formazioni',
    'emp_programmazione_formazioni_rfi',
  };

  static const Set<String> mezziLegacyKeys = <String>{
    'emp_mdo_ferroviari',
    'emp_mezzi_stradali',
  };

  static const Set<String> viaggiMezziLegacyKeys = <String>{
    'emp_viaggi_mezzi_scan',
    'emp_viaggi_mezzi_riepilogo',
    'emp_viaggi_mezzi_assegnatario',
  };

  static const Set<String> sicurezzaLegacyKeys = <String>{
    'emp_dpi',
    'emp_misure_vestiario',
  };

  static const Set<String> buoniPastoLegacyKeys = <String>{
    'emp_buoni_pasto_scan',
    'emp_buoni_pasto_riepilogo',
  };

  /// Unisce i pulsanti raggruppati (treni/aerei, rifornimento, formazione, …).
  static List<String> coalesceGroupedKeys(List<String> keys) {
    var out = _coalesceGroup(
      keys,
      launcher: 'emp_treni',
      legacy: treniLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_aerei',
      legacy: aereiLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_rifornimento',
      legacy: rifornimentoLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_formazione',
      legacy: formazioneLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_mezzi',
      legacy: mezziLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_viaggi_mezzi',
      legacy: viaggiMezziLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_sicurezza',
      legacy: sicurezzaLegacyKeys,
    );
    out = _coalesceGroup(
      out,
      launcher: 'emp_buoni_pasto',
      legacy: buoniPastoLegacyKeys,
    );
    return out;
  }

  static List<String> coalesceRifornimentoKeys(List<String> keys) =>
      coalesceGroupedKeys(keys);

  static List<String> _coalesceGroup(
    List<String> keys, {
    required String launcher,
    required Set<String> legacy,
  }) {
    if (keys.isEmpty) return keys;
    final out = <String>[];
    var inserted = false;
    for (final k in keys) {
      final isGroup = k == launcher || legacy.contains(k);
      if (!isGroup) {
        out.add(k);
        continue;
      }
      if (inserted) continue;
      out.add(launcher);
      inserted = true;
    }
    return out;
  }
}
