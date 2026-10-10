import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRoutingRulesService {
  NotificationRoutingRulesService._();

  static const String table = 'notification_routing_rules';

  /// Default allineati al flusso treno/aereo (pernottamenti invariati lato chiavi).
  static const Map<String, Map<String, dynamic>> defaults = {
    'request_to_dt': {
      'rule_key': 'request_to_dt',
      'label':
          '[Treno/Aereo] Dipendente invia richiesta → notifica al DT scelto nel modulo',
      'targets': ['selected_dt'],
      'enabled': true,
    },
    'dt_approved_to_admin': {
      'rule_key': 'dt_approved_to_admin',
      'label':
          '[Treno/Aereo] DT conferma biglietto → notifica agli Admin treni/aereo',
      'targets': ['role:admin_trenoaereo'],
      'enabled': true,
    },
    'dt_approved_to_requester': {
      'rule_key': 'dt_approved_to_requester',
      'label':
          '[Treno/Aereo] DT conferma → notifica al dipendente coinvolto (e al richiedente se diverso, es. assistente)',
      'targets': ['dipendente', 'requester'],
      'enabled': true,
    },
    'dt_rejected_to_requester': {
      'rule_key': 'dt_rejected_to_requester',
      'label':
          '[Treno/Aereo] DT rifiuta → notifica al dipendente coinvolto e al richiedente se presente',
      'targets': ['dipendente', 'requester'],
      'enabled': true,
    },
    'create_treno_aereo_by_dt': {
      'rule_key': 'create_treno_aereo_by_dt',
      'label':
          '[Treno/Aereo] DT crea prenotazione (invio ad admin) → Admin treni/aereo + dipendente coinvolto',
      'targets': ['role:admin_trenoaereo', 'dipendente'],
      'enabled': true,
    },
    'create_treno_aereo_by_assistente_dt': {
      'rule_key': 'create_treno_aereo_by_assistente_dt',
      'label':
          '[Treno/Aereo] Assistente DT crea prenotazione → Admin treni/aereo + DT supervisore (richiedente)',
      'targets': ['role:admin_trenoaereo', 'requester'],
      'enabled': true,
    },
    'create_to_admin_trenoaereo': {
      'rule_key': 'create_to_admin_trenoaereo',
      'label':
          '[Treno/Aereo] Fallback creazione (es. altro ruolo): solo Admin treni/aereo',
      'targets': ['role:admin_trenoaereo'],
      'enabled': true,
    },
    'create_to_admin_pernottamenti': {
      'rule_key': 'create_to_admin_pernottamenti',
      'label': 'Creazione pernottamento → Admin pernottamenti',
      'targets': ['role:admin_pernottamenti'],
      'enabled': true,
    },
    'admin_update_notify': {
      'rule_key': 'admin_update_notify',
      'label':
          'Admin modifica / cambia stato / conferma (prenotazioni generiche) → richiedente + dipendente',
      'targets': ['requester', 'dipendente'],
      'enabled': true,
    },
    'admin_delete_notify': {
      'rule_key': 'admin_delete_notify',
      'label':
          'Admin elimina (prenotazioni generiche) → richiedente + dipendente',
      'targets': ['requester', 'dipendente'],
      'enabled': true,
    },
    'admin_pernottamenti_update_notify': {
      'rule_key': 'admin_pernottamenti_update_notify',
      'label':
          '[Pernottamenti] Admin modifica / conferma / cambia stato → DT inseritore + dipendente',
      'targets': ['requester', 'dipendente'],
      'enabled': true,
    },
    'admin_pernottamenti_delete_notify': {
      'rule_key': 'admin_pernottamenti_delete_notify',
      'label':
          '[Pernottamenti] Admin cancella prenotazione → DT inseritore + dipendente',
      'targets': ['requester', 'dipendente'],
      'enabled': true,
    },
    'admin_treno_aereo_update_notify': {
      'rule_key': 'admin_treno_aereo_update_notify',
      'label':
          '[Treno/Aereo] Admin modifica o cambia stato → DT della prenotazione, suoi assistenti autorizzati, dipendente',
      'targets': [
        'dt_prenotazione',
        'assistenti_dt_prenotazione',
        'dipendente',
      ],
      'enabled': true,
    },
    'admin_treno_aereo_delete_notify': {
      'rule_key': 'admin_treno_aereo_delete_notify',
      'label':
          '[Treno/Aereo] Admin elimina → DT della prenotazione, suoi assistenti autorizzati, dipendente',
      'targets': [
        'dt_prenotazione',
        'assistenti_dt_prenotazione',
        'dipendente',
      ],
      'enabled': true,
    },
    'admin_formazione_update_notify': {
      'rule_key': 'admin_formazione_update_notify',
      'label':
          '[Formazione] Admin inserisce/aggiorna corso o programmazione → notifica al dipendente coinvolto',
      'targets': ['requester'],
      'enabled': true,
    },
    'admin_formazione_delete_notify': {
      'rule_key': 'admin_formazione_delete_notify',
      'label':
          '[Formazione] Admin elimina corso formazione → notifica al dipendente coinvolto',
      'targets': ['requester'],
      'enabled': true,
    },
    'logistica_box_check_completed_notify': {
      'rule_key': 'logistica_box_check_completed_notify',
      'label':
          '[Logistica] Check BOX confermato → notifica a DT, Assistenti DT e Logistica',
      'targets': ['role:dt', 'role:assistente_dt', 'role:logistica'],
      'enabled': true,
    },
    'logistica_mdo_general_check_completed_notify': {
      'rule_key': 'logistica_mdo_general_check_completed_notify',
      'label':
          '[Logistica] Check generale MDO confermato → notifica a DT, Assistenti DT e Logistica',
      'targets': ['role:dt', 'role:assistente_dt', 'role:logistica'],
      'enabled': true,
    },
    'logistica_mdo_dotazioni_check_completed_notify': {
      'rule_key': 'logistica_mdo_dotazioni_check_completed_notify',
      'label':
          '[Logistica] Check dotazioni MDO confermato → notifica a DT, Assistenti DT e Logistica',
      'targets': ['role:dt', 'role:assistente_dt', 'role:logistica'],
      'enabled': true,
    },
    'assenza_request_to_dt': {
      'rule_key': 'assenza_request_to_dt',
      'label':
          '[Assenze] Dipendente invia richiesta ferie/permessi → DT selezionato nel modulo',
      'targets': ['selected_dt'],
      'enabled': true,
    },
    'assenza_dt_approved_to_requester': {
      'rule_key': 'assenza_dt_approved_to_requester',
      'label': '[Assenze] DT approva → notifica al dipendente richiedente',
      'targets': ['requester'],
      'enabled': true,
    },
    'assenza_dt_approved_to_admin': {
      'rule_key': 'assenza_dt_approved_to_admin',
      'label': '[Assenze] DT approva → notifica agli admin (conferma richiesta)',
      'targets': [
        'role:admin',
        'role:admin_generale',
        'role:admin_pernottamenti',
        'role:admin_trenoaereo',
        'role:admin_dpi',
        'role:admin_formazione',
      ],
      'enabled': true,
    },
    'assenza_dt_rejected_to_requester': {
      'rule_key': 'assenza_dt_rejected_to_requester',
      'label': '[Assenze] DT rifiuta → notifica al dipendente richiedente',
      'targets': ['requester'],
      'enabled': true,
    },
    'assenza_admin_approved_to_requester': {
      'rule_key': 'assenza_admin_approved_to_requester',
      'label': '[Assenze] Admin approva → notifica al dipendente richiedente',
      'targets': ['requester'],
      'enabled': true,
    },
    'assenza_admin_rejected_to_requester': {
      'rule_key': 'assenza_admin_rejected_to_requester',
      'label': '[Assenze] Admin rifiuta → notifica al dipendente richiedente',
      'targets': ['requester'],
      'enabled': true,
    },
  };

  static Future<List<Map<String, dynamic>>> listRules() async {
    try {
      final res = await Supabase.instance.client
          .from(table)
          .select('rule_key,label,targets,enabled')
          .order('rule_key');
      final fromDb = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final byKey = <String, Map<String, dynamic>>{
        for (final r in fromDb)
          (r['rule_key'] ?? '').toString(): r,
      };
      for (final entry in defaults.entries) {
        byKey.putIfAbsent(
          entry.key,
          () => Map<String, dynamic>.from(entry.value),
        );
      }
      final merged = byKey.values.toList()
        ..sort(
          (a, b) => (a['rule_key'] ?? '')
              .toString()
              .compareTo((b['rule_key'] ?? '').toString()),
        );
      return merged;
    } catch (_) {
      return defaults.values.map((e) => Map<String, dynamic>.from(e)).toList();
    }
  }

  static Future<void> saveRule({
    required String ruleKey,
    required String label,
    required List<String> targets,
    required bool enabled,
  }) async {
    await Supabase.instance.client.from(table).upsert({
      'rule_key': ruleKey,
      'label': label,
      'targets': targets,
      'enabled': enabled,
    }, onConflict: 'rule_key');
  }

  static Set<String> get defaultRuleKeys => defaults.keys.toSet();

  static Future<void> syncDefaultsToDatabase() async {
    for (final row in defaults.values) {
      await saveRule(
        ruleKey: (row['rule_key'] ?? '').toString(),
        label: (row['label'] ?? '').toString(),
        targets: ((row['targets'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        enabled: row['enabled'] == true,
      );
    }
  }
}
