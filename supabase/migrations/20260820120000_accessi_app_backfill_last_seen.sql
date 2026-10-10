-- Accessi app: allinea last_app_open_at con auth.last_sign_in_at dove manca,
-- e espone entrambe le date agli admin per la pagina Accessi app.

-- 1) Backfill: chi ha fatto login Auth ma non ha ancora un touch app.
update public.users u
set last_app_open_at = a.last_sign_in_at
from auth.users a
where u.auth_id = a.id
  and u.last_app_open_at is null
  and a.last_sign_in_at is not null;

-- 2) Elenco admin: ultima apertura app + ultimo sign-in Auth.
create or replace function public.admin_list_accessi_app()
returns table (
  id bigint,
  full_name text,
  username text,
  email text,
  role text,
  active boolean,
  auth_id uuid,
  hidden_from_directory boolean,
  last_app_open_at timestamptz,
  last_sign_in_at timestamptz,
  last_seen_at timestamptz,
  last_seen_source text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if public.current_user_role_norm() not in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  ) and not coalesce(public.has_custom_page_access('accessi_app'), false) then
    raise exception 'not allowed';
  end if;

  return query
  select
    u.id::bigint,
    coalesce(u.full_name, '')::text,
    coalesce(u.username, '')::text,
    coalesce(u.email, '')::text,
    coalesce(u.role, '')::text,
    coalesce(u.active, true) as active,
    u.auth_id,
    coalesce(u.hidden_from_directory, false) as hidden_from_directory,
    u.last_app_open_at,
    a.last_sign_in_at,
    coalesce(u.last_app_open_at, a.last_sign_in_at) as last_seen_at,
    case
      when u.last_app_open_at is not null
        and (a.last_sign_in_at is null or u.last_app_open_at >= a.last_sign_in_at)
        then 'app'
      when a.last_sign_in_at is not null then 'login'
      else null
    end::text as last_seen_source
  from public.users u
  left join auth.users a on a.id = u.auth_id
  where u.auth_id is not null
  order by coalesce(u.last_app_open_at, a.last_sign_in_at) desc nulls last,
           u.full_name;
end;
$$;

grant execute on function public.admin_list_accessi_app() to authenticated;

comment on function public.admin_list_accessi_app() is
  'Elenco utenti con login + ultima apertura app / ultimo sign-in Auth (solo admin).';
