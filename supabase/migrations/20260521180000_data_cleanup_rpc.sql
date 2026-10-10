-- Pulizia dati (dashboard Admin): RPC con conteggio righe eliminate e soglia 10 giorni.

create or replace function public._cleanup_assert_admin()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  ) then
    raise exception 'Pulizia dati: permesso negato';
  end if;
end;
$$;

create or replace function public.cleanup_notifications()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_cutoff date := (timezone('Europe/Rome', now()))::date - 5;
begin
  perform public._cleanup_assert_admin();
  delete from public.notifications
  where (coalesce(created_at, '1970-01-01'::timestamptz) at time zone 'Europe/Rome')::date
        <= v_cutoff;
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

create or replace function public.cleanup_pernottamenti()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_cutoff date := (current_date - interval '10 days')::date;
begin
  perform public._cleanup_assert_admin();
  delete from public.bookings
  where end_date is not null
    and end_date::date < v_cutoff;
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

create or replace function public.cleanup_treni()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_cutoff date := (current_date - interval '10 days')::date;
begin
  perform public._cleanup_assert_admin();
  delete from public.bookings_treno
  where data is not null
    and greatest(
      data::date,
      coalesce(data_ritorno::date, data::date)
    ) < v_cutoff;
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

create or replace function public.cleanup_aereo()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
  v_cutoff date := (current_date - interval '10 days')::date;
begin
  perform public._cleanup_assert_admin();
  delete from public.bookings_aereo
  where data is not null
    and greatest(
      data::date,
      coalesce(data_ritorno::date, data::date)
    ) < v_cutoff;
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

grant execute on function public.cleanup_notifications() to authenticated;
grant execute on function public.cleanup_pernottamenti() to authenticated;
grant execute on function public.cleanup_treni() to authenticated;
grant execute on function public.cleanup_aereo() to authenticated;
