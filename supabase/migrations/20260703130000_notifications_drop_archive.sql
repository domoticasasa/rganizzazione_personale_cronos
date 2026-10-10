-- Rimuove archivio notifiche (se applicata migration precedente) e usa solo DELETE.

drop table if exists public.notifications_archive cascade;

drop function if exists public._archive_notifications_older_than(integer);

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
