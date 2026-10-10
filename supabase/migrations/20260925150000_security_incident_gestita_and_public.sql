-- Stato «gestita» + inserimento pubblico (via edge function / service_role).

alter table public.security_incident_reports
  drop constraint if exists security_incident_reports_status_check;

alter table public.security_incident_reports
  add constraint security_incident_reports_status_check
  check (status in ('aperto', 'in_lavorazione', 'gestita', 'chiuso'));

comment on column public.security_incident_reports.status is
  'aperto | in_lavorazione | gestita | chiuso. Il tile hub lampeggia finché non è gestita/chiuso.';

-- Colonna opzionale: segnalazione inviata senza login.
alter table public.security_incident_reports
  add column if not exists is_public_submit boolean not null default false;

comment on column public.security_incident_reports.is_public_submit is
  'True se inviata dalla pagina pre-login (edge security-incident-public).';
