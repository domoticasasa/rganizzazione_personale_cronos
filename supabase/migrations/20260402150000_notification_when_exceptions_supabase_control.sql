-- Eccezioni "quando" per la routing notifiche: spostiamo in Supabase
-- le liste che oggi erano hardcoded in Flutter/Edge Function.

-- 1) Per action=create (treno/aereo) esiste una lista di workflow_status
--    che deve BLOCCARE le notifiche agli admin.
create table if not exists public.notification_admin_create_skip_workflow_statuses (
  action_key text not null default 'create',
  workflow_status text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (action_key, workflow_status)
);

create or replace function public.set_notification_admin_create_skip_workflow_statuses_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_notification_admin_create_skip_workflow_statuses_updated_at
on public.notification_admin_create_skip_workflow_statuses;

create trigger trg_notification_admin_create_skip_workflow_statuses_updated_at
before update on public.notification_admin_create_skip_workflow_statuses
for each row
execute function public.set_notification_admin_create_skip_workflow_statuses_updated_at();

alter table public.notification_admin_create_skip_workflow_statuses enable row level security;

drop policy if exists "notification_admin_create_skip_workflow_statuses_read"
on public.notification_admin_create_skip_workflow_statuses;
create policy "notification_admin_create_skip_workflow_statuses_read"
on public.notification_admin_create_skip_workflow_statuses
for select
to authenticated
using (true);

drop policy if exists "notification_admin_create_skip_workflow_statuses_write_admin_only"
on public.notification_admin_create_skip_workflow_statuses;
create policy "notification_admin_create_skip_workflow_statuses_write_admin_only"
on public.notification_admin_create_skip_workflow_statuses
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

-- Default values (legacy hardcoded):
-- INVIATA_AL_DT e RIFIUTATA_DAL_DT => BLOCCA admin su action=create.
insert into public.notification_admin_create_skip_workflow_statuses (action_key, workflow_status, enabled)
values
  ('create', 'INVIATA_AL_DT', true),
  ('create', 'RIFIUTATA_DAL_DT', true)
on conflict (action_key, workflow_status) do update
set enabled = excluded.enabled,
    updated_at = now();

-- 2) Admin_generale filtro: in Edge Function oggi viene applicato
--    tranne che per alcune azioni "di servizio".
--    Facciamo configurabile anche questa lista.
create table if not exists public.notification_admin_generale_filter_skip_actions (
  action_key text primary key,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_notification_admin_generale_filter_skip_actions_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_notification_admin_generale_filter_skip_actions_updated_at
on public.notification_admin_generale_filter_skip_actions;

create trigger trg_notification_admin_generale_filter_skip_actions_updated_at
before update on public.notification_admin_generale_filter_skip_actions
for each row
execute function public.set_notification_admin_generale_filter_skip_actions_updated_at();

alter table public.notification_admin_generale_filter_skip_actions enable row level security;

drop policy if exists "notification_admin_generale_filter_skip_actions_read"
on public.notification_admin_generale_filter_skip_actions;
create policy "notification_admin_generale_filter_skip_actions_read"
on public.notification_admin_generale_filter_skip_actions
for select
to authenticated
using (true);

drop policy if exists "notification_admin_generale_filter_skip_actions_write_admin_only"
on public.notification_admin_generale_filter_skip_actions;
create policy "notification_admin_generale_filter_skip_actions_write_admin_only"
on public.notification_admin_generale_filter_skip_actions
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

-- Legacy hardcoded list in Edge Function:
-- queste azioni => "skip filter admin_generale" => admin_generale rimane incluso.
insert into public.notification_admin_generale_filter_skip_actions (action_key, enabled)
values
  ('dt_approval_required', true),
  ('dt_rejected', true),
  ('dt_approved', true)
on conflict (action_key) do update
set enabled = excluded.enabled,
    updated_at = now();

