-- Pulizia notifiche: conserva solo gli ultimi 5 giorni (data creazione, Europe/Rome).

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

  delete from public.notifications n
  where (coalesce(n.created_at, '1970-01-01'::timestamptz) at time zone 'Europe/Rome')::date
        <= v_cutoff;

  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

grant execute on function public.cleanup_notifications() to authenticated;
