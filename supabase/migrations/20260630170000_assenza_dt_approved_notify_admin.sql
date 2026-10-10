-- DT approva ferie/permessi → notifica agli admin per conferma o rifiuto finale.

insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  (
    'assenza_dt_approved_to_admin',
    '[Assenze] DT approva → notifica agli admin (conferma richiesta)',
    array[
      'role:admin',
      'role:admin_generale',
      'role:admin_pernottamenti',
      'role:admin_trenoaereo',
      'role:admin_dpi',
      'role:admin_formazione'
    ],
    true
  )
on conflict (rule_key) do nothing;
