-- Elimina notifiche oltre 10 giorni (Europe/Rome) + pulizia automatica giornaliera.

create or replace function public._delete_notifications_older_than(p_days integer default 10)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_cutoff date := (timezone('Europe/Rome', now()))::date - coalesce(p_days, 10);
begin
  delete from public.notifications n
  where (coalesce(n.created_at, '1970-01-01'::timestamptz) at time zone 'Europe/Rome')::date
        <= v_cutoff;

  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

create or replace function public.cleanup_notifications()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._cleanup_assert_admin();
  return public._delete_notifications_older_than(10);
end;
$$;

grant execute on function public.cleanup_notifications() to authenticated;

create or replace function public.cleanup_notifications_cron()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  return public._delete_notifications_older_than(10);
end;
$$;

comment on function public.cleanup_notifications_cron() is
  'Elimina notifiche > 10 giorni; invocato da pg_cron ogni notte.';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'cleanup_notifications_daily'
    ) then
      perform cron.unschedule('cleanup_notifications_daily');
    end if;

    perform cron.schedule(
      'cleanup_notifications_daily',
      '0 2 * * *',
      $job$select public.cleanup_notifications_cron();$job$
    );
  end if;
end
$$;
