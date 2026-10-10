-- list_dt_selectable_users: non richiedere auth.uid() (GRANT a authenticated basta).
create or replace function public.list_dt_selectable_users(p_active_only boolean default true)
returns table (
  id integer,
  id_uuid uuid,
  auth_id uuid,
  full_name text,
  username text,
  email text,
  role text,
  secondary_role text,
  active boolean,
  hidden_from_directory boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    u.id_uuid,
    u.auth_id,
    u.full_name,
    u.username,
    u.email,
    u.role,
    u.secondary_role,
    u.active,
    coalesce(u.hidden_from_directory, false) as hidden_from_directory
  from public.users u
  where (
      public.cronos_norm_role(u.role) in ('dt', 'assistente_dt')
      or public.cronos_norm_role(coalesce(u.secondary_role, '')) in ('dt', 'assistente_dt')
    )
    and (
      not p_active_only
      or coalesce(u.active, true) = true
    )
  order by u.full_name nulls last, u.id;
$$;

revoke all on function public.list_dt_selectable_users(boolean) from public;
grant execute on function public.list_dt_selectable_users(boolean) to authenticated;

notify pgrst, 'reload schema';
