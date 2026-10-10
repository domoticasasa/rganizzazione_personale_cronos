-- Regole push per workflow ferie/permessi (dipendente_assenze).
insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  (
    'assenza_request_to_dt',
    '[Assenze] Dipendente invia richiesta ferie/permessi → DT selezionato nel modulo',
    array['selected_dt'],
    true
  ),
  (
    'assenza_dt_approved_to_requester',
    '[Assenze] DT approva → notifica al dipendente richiedente',
    array['requester'],
    true
  ),
  (
    'assenza_dt_rejected_to_requester',
    '[Assenze] DT rifiuta → notifica al dipendente richiedente',
    array['requester'],
    true
  ),
  (
    'assenza_admin_approved_to_requester',
    '[Assenze] Admin approva → notifica al dipendente richiedente',
    array['requester'],
    true
  ),
  (
    'assenza_admin_rejected_to_requester',
    '[Assenze] Admin rifiuta → notifica al dipendente richiedente',
    array['requester'],
    true
  )
on conflict (rule_key) do nothing;
