-- Allinea regole notifiche al flusso treno/aereo (dipendente / DT / assistente / admin)
insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  (
    'request_to_dt',
    '[Treno/Aereo] Dipendente invia richiesta → notifica al DT scelto nel modulo',
    array['selected_dt'],
    true
  ),
  (
    'dt_approved_to_admin',
    '[Treno/Aereo] DT conferma biglietto → notifica agli Admin treni/aereo',
    array['role:admin_trenoaereo'],
    true
  ),
  (
    'dt_approved_to_requester',
    '[Treno/Aereo] DT conferma → notifica al dipendente coinvolto (e al richiedente se diverso, es. assistente)',
    array['dipendente', 'requester'],
    true
  ),
  (
    'dt_rejected_to_requester',
    '[Treno/Aereo] DT rifiuta → notifica al dipendente coinvolto e al richiedente se presente',
    array['dipendente', 'requester'],
    true
  ),
  (
    'create_treno_aereo_by_dt',
    '[Treno/Aereo] DT crea prenotazione (invio ad admin) → Admin treni/aereo + dipendente coinvolto',
    array['role:admin_trenoaereo', 'dipendente'],
    true
  ),
  (
    'create_treno_aereo_by_assistente_dt',
    '[Treno/Aereo] Assistente DT crea prenotazione → Admin treni/aereo + DT supervisore (richiedente)',
    array['role:admin_trenoaereo', 'requester'],
    true
  ),
  (
    'create_to_admin_trenoaereo',
    '[Treno/Aereo] Fallback creazione (es. altro ruolo): solo Admin treni/aereo',
    array['role:admin_trenoaereo'],
    true
  ),
  (
    'create_to_admin_pernottamenti',
    'Creazione pernottamento → Admin pernottamenti',
    array['role:admin_pernottamenti'],
    true
  ),
  (
    'admin_update_notify',
    'Admin modifica / cambia stato / conferma (prenotazioni generiche) → richiedente + dipendente',
    array['requester', 'dipendente'],
    true
  ),
  (
    'admin_delete_notify',
    'Admin elimina (prenotazioni generiche) → richiedente + dipendente',
    array['requester', 'dipendente'],
    true
  ),
  (
    'admin_treno_aereo_update_notify',
    '[Treno/Aereo] Admin modifica o cambia stato → DT della prenotazione, suoi assistenti autorizzati, dipendente',
    array['dt_prenotazione', 'assistenti_dt_prenotazione', 'dipendente'],
    true
  ),
  (
    'admin_treno_aereo_delete_notify',
    '[Treno/Aereo] Admin elimina → DT della prenotazione, suoi assistenti autorizzati, dipendente',
    array['dt_prenotazione', 'assistenti_dt_prenotazione', 'dipendente'],
    true
  )
on conflict (rule_key) do update
set
  label = excluded.label,
  targets = excluded.targets,
  enabled = excluded.enabled,
  updated_at = now();
