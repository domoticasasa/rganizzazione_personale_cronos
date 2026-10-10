-- Log accessi app: storico 14 giorni, visibile in Impostazioni → Log app.

create table if not exists public.app_activity_logs (
  id bigserial primary key,
  created_at timestamptz not null default timezone('utc', now()),
  user_id integer references public.users (id) on delete set null,
  auth_id uuid,
  full_name text not null default '',
  username text not null default '',
  role text not null default '',
  action text not null default 'app_open',
  detail text not null default ''
);

comment on table public.app_activity_logs is
  'Storico accessi/attività app. Righe più vecchie di 14 giorni eliminate in automatico.';

create index if not exists app_activity_logs_created_at_idx
  on public.app_activity_logs (created_at desc);

create index if not exists app_activity_logs_user_id_idx
  on public.app_activity_logs (user_id);

create index if not exists app_activity_logs_role_idx
  on public.app_activity_logs (role);

create index if not exists app_activity_logs_full_name_idx
  on public.app_activity_logs (full_name);

grant select on public.app_activity_logs to authenticated;

alter table public.app_activity_logs enable row level security;

drop policy if exists app_activity_logs_select_admin on public.app_activity_logs;
create policy app_activity_logs_select_admin
on public.app_activity_logs
for select
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or coalesce(public.has_custom_page_access('log_app'), false)
);

create or replace function public.cleanup_app_activity_logs()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  delete from public.app_activity_logs
  where created_at < (timezone('utc', now()) - interval '14 days');
  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

comment on function public.cleanup_app_activity_logs() is
  'Elimina log app più vecchi di 14 giorni.';

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
begin
  perform public.cleanup_app_activity_logs();

  if v_uid is null then
    return null;
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
    detail
  )
  values (
    v_user_id,
    v_uid,
    coalesce(nullif(trim(v_full_name), ''), v_username),
    v_username,
    v_role,
    coalesce(nullif(trim(p_action), ''), 'app_open'),
    coalesce(p_detail, '')
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.record_my_app_activity(
  p_action text default 'app_open',
  p_detail text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  return public._insert_app_activity_log(p_action, p_detail);
end;
$$;

grant execute on function public.record_my_app_activity(text, text) to authenticated;

comment on function public.record_my_app_activity(text, text) is
  'Registra un log di accesso/attività per l''utente autenticato.';

-- Ogni apertura app (throttle 2 min) scrive anche una riga di log.
create or replace function public.touch_my_last_app_open()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_prev timestamptz;
  v_updated int := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
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
  set last_app_open_at = v_at
  where u.auth_id = auth.uid();
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    update public.users u
    set last_app_open_at = v_at
    where u.id_uuid = auth.uid();
  end if;

  perform public._insert_app_activity_log('app_open', '');
  return v_at;
end;
$$;

grant execute on function public.touch_my_last_app_open() to authenticated;

create or replace function public.admin_list_app_activity_logs(
  p_name text default null,
  p_role text default null,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns table (
  id bigint,
  created_at timestamptz,
  user_id integer,
  full_name text,
  username text,
  role text,
  action text,
  detail text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_role text := nullif(trim(coalesce(p_role, '')), '');
begin
  if public.current_user_role_norm() not in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  ) and not coalesce(public.has_custom_page_access('log_app'), false) then
    raise exception 'not allowed';
  end if;

  perform public.cleanup_app_activity_logs();

  return query
  select
    l.id,
    l.created_at,
    l.user_id,
    l.full_name,
    l.username,
    l.role,
    l.action,
    l.detail
  from public.app_activity_logs l
  where (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at <= p_to)
    and (
      v_name is null
      or l.full_name ilike '%' || v_name || '%'
      or l.username ilike '%' || v_name || '%'
    )
    and (v_role is null or lower(l.role) = lower(v_role))
  order by l.created_at desc, l.id desc
  limit 2000;
end;
$$;

grant execute on function public.admin_list_app_activity_logs(text, text, timestamptz, timestamptz)
  to authenticated;

comment on function public.admin_list_app_activity_logs(text, text, timestamptz, timestamptz) is
  'Elenco log app (max 14 giorni) per admin, con filtro nome/ruolo/intervallo.';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'cleanup_app_activity_logs_daily'
    ) then
      perform cron.unschedule('cleanup_app_activity_logs_daily');
    end if;

    perform cron.schedule(
      'cleanup_app_activity_logs_daily',
      '15 2 * * *',
      $job$select public.cleanup_app_activity_logs();$job$
    );
  end if;
end
$$;
