-- Backup dati giornalieri: bucket privato + elenco tabelle + cron HTTP.

insert into storage.buckets (id, name, public, file_size_limit)
values ('cronos_data_backups', 'cronos_data_backups', false, 524288000)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

-- Nessuna policy per authenticated/anon: solo service_role (bypass RLS).

create table if not exists public.data_backup_runs (
  id bigserial primary key,
  backup_date date not null,
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz,
  ok boolean,
  tables_count integer,
  rows_count bigint,
  storage_prefix text,
  error_message text,
  unique (backup_date)
);

comment on table public.data_backup_runs is
  'Log delle esecuzioni del backup giornaliero (retention file: 10 giorni).';

alter table public.data_backup_runs enable row level security;

drop policy if exists data_backup_runs_admin_select on public.data_backup_runs;
create policy data_backup_runs_admin_select
  on public.data_backup_runs for select to authenticated
  using (public.is_cronos_admin_role());

revoke all on table public.data_backup_runs from anon, authenticated;
grant select on table public.data_backup_runs to authenticated;

-- Elenco tabelle public da esportare (no service_role needed in app).
create or replace function public._backup_list_public_tables()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(c.relname order by c.relname),
    '{}'::text[]
  )
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relname not like 'pg_%'
    and c.relname <> 'data_backup_runs';
$$;

revoke all on function public._backup_list_public_tables() from public, anon, authenticated;
grant execute on function public._backup_list_public_tables() to service_role;

-- Invoca edge function daily-data-backup (se secret vault presente).
create or replace function public.invoke_daily_data_backup_cron()
returns bigint
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  v_secret text;
  v_url text;
  v_request_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net non disponibile: skip invoke_daily_data_backup_cron';
    return 0;
  end if;

  begin
    select ds.decrypted_secret
      into v_secret
    from vault.decrypted_secrets ds
    where ds.name = 'daily_backup_secret'
    limit 1;
  exception
    when undefined_table then
      v_secret := null;
    when others then
      v_secret := null;
  end;

  if coalesce(trim(v_secret), '') = '' then
    raise notice
      'Vault secret daily_backup_secret assente: configura con supabase secrets / vault, oppure usa GitHub Action.';
    return 0;
  end if;

  v_url := 'https://bjdimalvbdablzoctrsf.supabase.co/functions/v1/daily-data-backup';

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cronos-backup-secret', v_secret
    ),
    body := jsonb_build_object('source', 'pg_cron')
  )
  into v_request_id;

  return coalesce(v_request_id, 0);
end;
$$;

comment on function public.invoke_daily_data_backup_cron() is
  'Chiama edge function daily-data-backup ogni notte (secret vault: daily_backup_secret).';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'daily_data_backup'
    ) then
      perform cron.unschedule('daily_data_backup');
    end if;

    -- 03:15 Europe/Rome ≈ 01:15 UTC (inverno) / 02:15 UTC gestito dalla schedule UTC.
    -- Usare 1:15 UTC come slot notturno stabile.
    perform cron.schedule(
      'daily_data_backup',
      '15 1 * * *',
      $job$select public.invoke_daily_data_backup_cron();$job$
    );
  end if;
end
$$;
