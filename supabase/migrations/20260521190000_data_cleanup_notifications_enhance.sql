-- Pulizia notifiche: DELETE su public.notifications (security definer, bypass RLS).

create or replace function public._cleanup_normalize_role(p_role text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(p_role, '')), '\s+|/', '_', 'g'));
$$;

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
      and public._cleanup_normalize_role(u.role) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_treno_aereo',
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
  -- Come pernottamenti/treni: data calendario (Europe/Rome), non timestamp da now().
  -- Conserva ultimi 5 giorni (Europe/Rome): elimina created_at::date <= oggi - 5.
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
