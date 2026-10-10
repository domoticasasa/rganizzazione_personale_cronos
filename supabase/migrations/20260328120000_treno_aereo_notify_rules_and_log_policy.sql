-- Regole configurabili (UI Regole notifiche) per admin treno/aereo
insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  (
    'admin_treno_aereo_update_notify',
    'Admin modifica treno/aereo -> DT prenotazione, assistenti autorizzati, dipendente',
    array['dt_prenotazione', 'assistenti_dt_prenotazione', 'dipendente'],
    true
  ),
  (
    'admin_treno_aereo_delete_notify',
    'Admin elimina treno/aereo -> DT prenotazione, assistenti autorizzati, dipendente',
    array['dt_prenotazione', 'assistenti_dt_prenotazione', 'dipendente'],
    true
  )
on conflict (rule_key) do update
set
  label = excluded.label,
  targets = excluded.targets,
  enabled = excluded.enabled,
  updated_at = now();

-- Log notifiche: admin possono leggere tutte le righe (oltre alle policy esistenti per utente)
do $migration$
begin
  if to_regclass('public.notifications') is not null then
    alter table public.notifications enable row level security;
    drop policy if exists "notifications_admin_read_all" on public.notifications;
    create policy "notifications_admin_read_all"
    on public.notifications
    for select
    to authenticated
    using (
      exists (
        select 1
        from public.users u
        where u.auth_id = auth.uid()
          and lower(coalesce(u.role, '')) in (
            'admin',
            'admin_generale',
            'admin_pernottamenti',
            'admin_trenoaereo'
          )
      )
    );
  end if;
end $migration$;
