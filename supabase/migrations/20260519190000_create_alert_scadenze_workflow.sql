-- Stato gestione per singola segnalazione in Alert scadenze.
create table if not exists public.alert_scadenze_workflow (
  alert_key text primary key,
  stato text not null
    check (stato in ('DA GESTIRE', 'IN CORSO DI GESTIONE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null
);

create or replace function public.set_alert_scadenze_workflow_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid
    into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    new.created_by_user_uuid := coalesce(new.created_by_user_uuid, v_user_uuid);
    new.updated_by_user_uuid := coalesce(new.updated_by_user_uuid, v_user_uuid);
    new.updated_at := now();
    return new;
  end if;

  new.updated_at := now();
  new.updated_by_user_uuid := coalesce(v_user_uuid, new.updated_by_user_uuid);
  return new;
end;
$$;

drop trigger if exists trg_alert_scadenze_workflow_audit
  on public.alert_scadenze_workflow;

create trigger trg_alert_scadenze_workflow_audit
before insert or update on public.alert_scadenze_workflow
for each row
execute function public.set_alert_scadenze_workflow_audit_fields();

alter table public.alert_scadenze_workflow enable row level security;

drop policy if exists alert_scadenze_workflow_select on public.alert_scadenze_workflow;
create policy alert_scadenze_workflow_select
  on public.alert_scadenze_workflow
  for select
  to authenticated
  using (true);

drop policy if exists alert_scadenze_workflow_write on public.alert_scadenze_workflow;
create policy alert_scadenze_workflow_write
  on public.alert_scadenze_workflow
  for all
  to authenticated
  using (true)
  with check (true);
