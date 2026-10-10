-- Fix backup notturno: timeout pg_net era 5s (troppo basso).
-- Aggiunge trigger_source per distinguere automatico / manuale.

alter table public.data_backup_runs
  add column if not exists trigger_source text;

comment on column public.data_backup_runs.trigger_source is
  'Origine run: pg_cron | github_actions | admin-data-backup | altro.';

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
      'Vault secret daily_backup_secret assente: configura vault oppure usa GitHub Action.';
    return 0;
  end if;

  v_url := 'https://bjdimalvbdablzoctrsf.supabase.co/functions/v1/daily-data-backup';

  -- Il backup dura ~30–90s: timeout default 5s faceva solo "Timeout" nei log
  -- e confondeva. Con 10 minuti si vede lo stato reale; la funzione continua
  -- comunque anche se il client scollega.
  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cronos-backup-secret', v_secret
    ),
    body := jsonb_build_object('source', 'pg_cron'),
    timeout_milliseconds := 600000
  )
  into v_request_id;

  return coalesce(v_request_id, 0);
end;
$$;

comment on function public.invoke_daily_data_backup_cron() is
  'Chiama edge daily-data-backup ogni notte (vault: daily_backup_secret, timeout 10 min).';

-- Assicura schedule attivo (01:15 UTC ≈ 03:15 Europe/Rome).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'daily_data_backup'
    ) then
      perform cron.unschedule('daily_data_backup');
    end if;
    perform cron.schedule(
      'daily_data_backup',
      '15 1 * * *',
      $job$select public.invoke_daily_data_backup_cron();$job$
    );
  end if;
end
$$;
