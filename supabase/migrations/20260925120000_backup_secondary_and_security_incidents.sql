-- Seconda destinazione backup (metadati) + segnalazioni incidente sicurezza.

alter table public.data_backup_runs
  add column if not exists secondary_ok boolean,
  add column if not exists secondary_provider text,
  add column if not exists secondary_error text;

comment on column public.data_backup_runs.secondary_ok is
  'Esito copia su destinazione secondaria (S3-compatibile), se configurata.';

create table if not exists public.security_incident_reports (
  id_uuid uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  reporter_user_id integer references public.users (id) on delete set null,
  reporter_auth_id uuid,
  reporter_name text not null default '',
  reporter_role text not null default '',
  reporter_phone text not null default '',
  category text not null default 'altro'
    check (category in (
      'phishing',
      'account_compromesso',
      'dispositivo_perso',
      'malware',
      'accesso_non_autorizzato',
      'altro'
    )),
  severity text not null default 'media'
    check (severity in ('bassa', 'media', 'alta', 'critica')),
  title text not null,
  description text not null,
  device_info text not null default '',
  location_info text not null default '',
  status text not null default 'aperto'
    check (status in ('aperto', 'in_lavorazione', 'chiuso')),
  admin_notes text,
  closed_at timestamptz
);

create index if not exists security_incident_reports_created_idx
  on public.security_incident_reports (created_at desc);
create index if not exists security_incident_reports_status_idx
  on public.security_incident_reports (status);

alter table public.security_incident_reports enable row level security;

-- Chiunque autenticato può inserire una propria segnalazione.
drop policy if exists security_incident_reports_insert_own
  on public.security_incident_reports;
create policy security_incident_reports_insert_own
on public.security_incident_reports
for insert
to authenticated
with check (
  reporter_auth_id is null
  or reporter_auth_id = (select auth.uid())
);

-- L'autore vede le proprie; admin/logistica vedono tutte.
drop policy if exists security_incident_reports_select_own_or_admin
  on public.security_incident_reports;
create policy security_incident_reports_select_own_or_admin
on public.security_incident_reports
for select
to authenticated
using (
  reporter_auth_id = (select auth.uid())
  or exists (
    select 1
    from public.users u
    where u.auth_id = (select auth.uid())
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'logistica',
        'admin_vista'
      )
  )
);

drop policy if exists security_incident_reports_update_admin
  on public.security_incident_reports;
create policy security_incident_reports_update_admin
on public.security_incident_reports
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = (select auth.uid())
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'logistica'
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = (select auth.uid())
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'logistica'
      )
  )
);

grant select, insert on public.security_incident_reports to authenticated;
grant select, insert, update, delete on public.security_incident_reports to service_role;
grant update on public.security_incident_reports to authenticated;
