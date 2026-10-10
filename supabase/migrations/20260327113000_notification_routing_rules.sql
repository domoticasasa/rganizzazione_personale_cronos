create table if not exists public.notification_routing_rules (
  rule_key text primary key,
  label text not null default '',
  targets text[] not null default '{}',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_notification_routing_rules_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_notification_routing_rules_updated_at
on public.notification_routing_rules;

create trigger trg_notification_routing_rules_updated_at
before update on public.notification_routing_rules
for each row
execute function public.set_notification_routing_rules_updated_at();

alter table public.notification_routing_rules enable row level security;

drop policy if exists "notification_rules_read_authenticated"
on public.notification_routing_rules;
create policy "notification_rules_read_authenticated"
on public.notification_routing_rules
for select
to authenticated
using (true);

drop policy if exists "notification_rules_write_admin_only"
on public.notification_routing_rules;
create policy "notification_rules_write_admin_only"
on public.notification_routing_rules
for all
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
)
with check (
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

insert into public.notification_routing_rules (rule_key, label, targets, enabled)
values
  ('request_to_dt', 'Richiesta dipendente/assistente -> DT selezionato', array['selected_dt'], true),
  ('dt_approved_to_admin', 'DT approva -> Admin competenti', array['role:admin_trenoaereo'], true),
  ('dt_approved_to_requester', 'DT approva -> Richiedente', array['requester'], true),
  ('dt_rejected_to_requester', 'DT rifiuta -> Richiedente', array['requester'], true),
  ('create_to_admin_trenoaereo', 'Creazione treno/aereo -> Admin treni/aerei', array['role:admin_trenoaereo'], true),
  ('create_to_admin_pernottamenti', 'Creazione pernottamento -> Admin pernottamenti', array['role:admin_pernottamenti'], true),
  ('admin_update_notify', 'Admin modifica -> Richiedente + dipendente', array['requester', 'dipendente'], true),
  ('admin_delete_notify', 'Admin elimina -> Richiedente + dipendente', array['requester', 'dipendente'], true)
on conflict (rule_key) do update
set
  label = excluded.label,
  targets = excluded.targets,
  enabled = excluded.enabled,
  updated_at = now();

