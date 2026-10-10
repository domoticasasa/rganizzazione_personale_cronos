-- ============================================================================
-- Testi legali in-app + impostazioni privacy (audit legale A1, M1, A5).
-- NON applicato automaticamente: vedi CHECKLIST_modifiche_legali.md
-- ============================================================================

-- Impostazioni privacy del cliente (una sola riga, id = 1).
create table if not exists public.app_legal_settings (
  id integer primary key default 1 check (id = 1),
  azienda_nome text not null default '',
  gps_retention_months integer not null default 12
    check (gps_retention_months between 1 and 120),
  fornitore_ragione_sociale text not null default '',
  fornitore_piva text not null default '',
  fornitore_sede text not null default '',
  fornitore_pec text not null default '',
  email_assistenza text not null default '',
  termini_data text not null default '',
  fornitore_email text not null default '',
  note_legali_data text not null default '',
  updated_at timestamptz not null default now()
);

insert into public.app_legal_settings (id) values (1)
on conflict (id) do nothing;

-- Se la tabella esisteva già (riapplicazione):
alter table public.app_legal_settings
  add column if not exists fornitore_email text not null default '',
  add column if not exists note_legali_data text not null default '';

comment on table public.app_legal_settings is
  'Impostazioni privacy/legali (nome azienda, conservazione GPS in mesi, dati fornitore per i Termini d''uso).';

-- Testi legali pubblicati per cliente (il titolare è il cliente).
create table if not exists public.app_legal_documents (
  doc_key text primary key
    check (doc_key in ('informativa_privacy', 'termini_uso')),
  title text not null default '',
  content text not null default '',
  version text not null default '1.0',
  published boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

-- Prese visione (data e versione).
create table if not exists public.app_legal_acceptances (
  id bigserial primary key,
  auth_id uuid not null default auth.uid(),
  doc_key text not null,
  version text not null default '',
  accepted_at timestamptz not null default now()
);
create index if not exists app_legal_acceptances_auth_idx
  on public.app_legal_acceptances (auth_id, doc_key);

create or replace function public.app_legal_touch_updated()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_app_legal_settings_touch on public.app_legal_settings;
create trigger trg_app_legal_settings_touch before update on public.app_legal_settings
for each row execute function public.app_legal_touch_updated();

drop trigger if exists trg_app_legal_documents_touch on public.app_legal_documents;
create trigger trg_app_legal_documents_touch before insert or update on public.app_legal_documents
for each row execute function public.app_legal_touch_updated();

alter table public.app_legal_settings enable row level security;
alter table public.app_legal_documents enable row level security;
alter table public.app_legal_acceptances enable row level security;

-- Lettura: anche anon (link Privacy nella pagina di login). Solo testi pubblicati.
drop policy if exists app_legal_settings_select on public.app_legal_settings;
create policy app_legal_settings_select on public.app_legal_settings
  for select to anon, authenticated using (true);

drop policy if exists app_legal_settings_write on public.app_legal_settings;
create policy app_legal_settings_write on public.app_legal_settings
  for update to authenticated
  using (public.is_cronos_admin_role()) with check (public.is_cronos_admin_role());

drop policy if exists app_legal_documents_select on public.app_legal_documents;
create policy app_legal_documents_select on public.app_legal_documents
  for select to anon, authenticated
  using (published or public.is_cronos_admin_role());

drop policy if exists app_legal_documents_insert on public.app_legal_documents;
create policy app_legal_documents_insert on public.app_legal_documents
  for insert to authenticated with check (public.is_cronos_admin_role());

drop policy if exists app_legal_documents_update on public.app_legal_documents;
create policy app_legal_documents_update on public.app_legal_documents
  for update to authenticated using (public.is_cronos_admin_role()) with check (public.is_cronos_admin_role());

drop policy if exists app_legal_acceptances_insert on public.app_legal_acceptances;
create policy app_legal_acceptances_insert on public.app_legal_acceptances
  for insert to authenticated with check (auth_id = auth.uid());

drop policy if exists app_legal_acceptances_select on public.app_legal_acceptances;
create policy app_legal_acceptances_select on public.app_legal_acceptances
  for select to authenticated using (auth_id = auth.uid() or public.is_cronos_admin_role());

grant select on public.app_legal_settings, public.app_legal_documents to anon, authenticated;
grant update on public.app_legal_settings to authenticated;
grant insert, update on public.app_legal_documents to authenticated;
grant select, insert on public.app_legal_acceptances to authenticated;
grant usage, select on sequence public.app_legal_acceptances_id_seq to authenticated;

-- ============================================================================
-- Conservazione posizioni GPS (default 12 mesi, configurabile in
-- app_legal_settings.gps_retention_months). Le righe restano (buoni pasto e
-- viaggi servono per amministrazione), vengono azzerate solo le coordinate.
-- ============================================================================
create or replace function public.privacy_retention_cleanup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_months integer;
  v_cutoff timestamptz;
  v_bp integer := 0;
  v_vm integer := 0;
begin
  select coalesce(gps_retention_months, 12) into v_months
  from public.app_legal_settings where id = 1;
  v_months := coalesce(v_months, 12);
  v_cutoff := now() - make_interval(months => v_months);

  update public.buoni_pasto_registrazioni
     set latitudine = null, longitudine = null
   where registrato_at < v_cutoff
     and (latitudine is not null or longitudine is not null);
  get diagnostics v_bp = row_count;

  update public.logistica_mezzi_stradali_viaggi
     set lat_inizio = null, lon_inizio = null, lat_fine = null, lon_fine = null
   where coalesce(chiuso_at, iniziato_at) < v_cutoff
     and (lat_inizio is not null or lon_inizio is not null
          or lat_fine is not null or lon_fine is not null);
  get diagnostics v_vm = row_count;

  return jsonb_build_object(
    'gps_retention_months', v_months,
    'cutoff', v_cutoff,
    'buoni_pasto_gps_azzerati', v_bp,
    'viaggi_mezzi_gps_azzerati', v_vm
  );
end;
$$;

revoke all on function public.privacy_retention_cleanup() from public, anon, authenticated;

comment on function public.privacy_retention_cleanup() is
  'Audit legale: azzera le coordinate GPS più vecchie di app_legal_settings.gps_retention_months (default 12). Invocata da pg_cron ogni notte.';

-- Pianificazione giornaliera (03:40) se pg_cron è attivo.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'privacy_retention_cleanup_daily') then
      perform cron.unschedule('privacy_retention_cleanup_daily');
    end if;
    perform cron.schedule(
      'privacy_retention_cleanup_daily',
      '40 3 * * *',
      $job$select public.privacy_retention_cleanup();$job$
    );
  end if;
end
$$;

comment on table public.data_backup_runs is
  'Log delle esecuzioni del backup giornaliero (retention file: 60 giorni).';

notify pgrst, 'reload schema';
