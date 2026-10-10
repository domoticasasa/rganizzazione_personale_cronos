insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  (
    'admin_formazione_update_notify',
    '[Formazione] Admin inserisce/aggiorna corso o programmazione → notifica al dipendente coinvolto',
    array['requester']::text[],
    true
  ),
  (
    'admin_formazione_delete_notify',
    '[Formazione] Admin elimina corso formazione → notifica al dipendente coinvolto',
    array['requester']::text[],
    true
  )
on conflict (rule_key) do update
set
  label = excluded.label,
  targets = excluded.targets,
  enabled = excluded.enabled,
  updated_at = now();

