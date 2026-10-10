-- Accessi app: ultimo canale (web / android / windows / ios).

alter table public.users
  add column if not exists last_app_open_platform text;

comment on column public.users.last_app_open_platform is
  'Ultimo client: web, android, windows, ios, macos, linux.';

alter table public.app_activity_logs
  add column if not exists platform text;

comment on column public.app_activity_logs.platform is
  'Client dell''evento app_open (web / android / windows / …).';

drop function if exists public.touch_my_last_app_open();

create or replace function public.touch_my_last_app_open(p_platform text default '')
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_prev timestamptz;
  v_updated int := 0;
  v_platform text := lower(trim(coalesce(p_platform, '')));
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_platform not in ('web', 'android', 'windows', 'ios', 'macos', 'linux') then
    v_platform := '';
  end if;

  select u.last_app_open_at
    into v_prev
    from public.users u
   where u.auth_id = auth.uid()
      or u.id_uuid = auth.uid()
   order by case when u.auth_id = auth.uid() then 0 else 1 end
   limit 1;

  if v_prev is not null and v_prev > (v_at - interval '2 minutes') then
    return v_prev;
  end if;

  update public.users u
     set last_app_open_at = v_at,
         last_app_open_platform = nullif(v_platform, '')
   where u.auth_id = auth.uid();
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    update public.users u
       set last_app_open_at = v_at,
           last_app_open_platform = nullif(v_platform, '')
     where u.id_uuid = auth.uid();
  end if;

  perform public._insert_app_activity_log(
    'app_open',
    coalesce(nullif(v_platform, ''), '')
  );

  return v_at;
end;
$$;

create or replace function public._insert_app_activity_log(
  p_action text default 'app_open',
  p_detail text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
  v_user_id integer;
  v_full_name text;
  v_username text;
  v_role text;
  v_platform text := lower(trim(coalesce(p_detail, '')));
begin
  perform public.cleanup_app_activity_logs();

  if v_uid is null then
    return null;
  end if;

  if v_platform not in ('web', 'android', 'windows', 'ios', 'macos', 'linux') then
    v_platform := '';
  end if;

  select u.id, coalesce(u.full_name, ''), coalesce(u.username, ''), coalesce(u.role, '')
    into v_user_id, v_full_name, v_username, v_role
  from public.users u
  where u.auth_id = v_uid
     or u.id_uuid = v_uid
  order by case when u.auth_id = v_uid then 0 else 1 end
  limit 1;

  if v_user_id is null then
    return null;
  end if;

  insert into public.app_activity_logs (
    user_id,
    auth_id,
    full_name,
    username,
    role,
    action,
    detail,
    platform
  )
  values (
    v_user_id,
    v_uid,
    coalesce(nullif(trim(v_full_name), ''), v_username),
    v_username,
    v_role,
    coalesce(nullif(trim(p_action), ''), 'app_open'),
    coalesce(p_detail, ''),
    nullif(v_platform, '')
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.touch_my_last_app_open(text) to authenticated;

comment on function public.touch_my_last_app_open(text) is
  'Registra last_app_open_at e il canale client (throttle 2 min).';

drop function if exists public.admin_list_accessi_app();

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
  last_seen_source text,
  last_app_open_platform text
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
    end::text as last_seen_source,
    coalesce(u.last_app_open_platform, '')::text
  from public.users u
  inner join auth.users a on a.id = u.auth_id
  where u.auth_id is not null
  order by coalesce(u.last_app_open_at, a.last_sign_in_at) desc nulls last,
           u.full_name;
end;
$$;

grant execute on function public.admin_list_accessi_app() to authenticated;

notify pgrst, 'reload schema';
