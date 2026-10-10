-- Stato lettura chat per utente (badge non letti personalizzato).

create table if not exists public.app_chat_read_state (
  user_id integer primary key references public.users (id) on delete cascade,
  auth_id uuid not null,
  last_read_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists app_chat_read_state_auth_id_uidx
  on public.app_chat_read_state (auth_id);

comment on table public.app_chat_read_state is
  'Ultima lettura chat aziendale per utente (badge non letti indipendente).';

alter table public.app_chat_read_state enable row level security;

drop policy if exists app_chat_read_state_select_own on public.app_chat_read_state;
create policy app_chat_read_state_select_own
  on public.app_chat_read_state
  for select
  to authenticated
  using (auth_id = auth.uid());

drop policy if exists app_chat_read_state_insert_own on public.app_chat_read_state;
create policy app_chat_read_state_insert_own
  on public.app_chat_read_state
  for insert
  to authenticated
  with check (auth_id = auth.uid());

drop policy if exists app_chat_read_state_update_own on public.app_chat_read_state;
create policy app_chat_read_state_update_own
  on public.app_chat_read_state
  for update
  to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

-- Conta messaggi non letti (esclusi i propri), ultimi 7 giorni.
create or replace function public.app_chat_unread_count()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_last timestamptz;
  v_cutoff timestamptz := timezone('utc', now()) - interval '7 days';
  v_count integer := 0;
begin
  if v_auth is null then
    return 0;
  end if;

  select r.last_read_at
    into v_last
  from public.app_chat_read_state r
  where r.auth_id = v_auth
  limit 1;

  if v_last is null then
    v_last := v_cutoff;
  elsif v_last < v_cutoff then
    v_last := v_cutoff;
  end if;

  select count(*)::integer
    into v_count
  from public.app_chat_messages m
  where m.created_at > v_last
    and m.created_at >= v_cutoff
    and m.sender_auth_id is distinct from v_auth;

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.app_chat_unread_count() to authenticated;

-- Segna la chat come letta ora.
create or replace function public.app_chat_mark_read()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_user_id integer;
  v_at timestamptz := timezone('utc', now());
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;

  select u.id
    into v_user_id
  from public.users u
  where u.auth_id = v_auth
     or u.id_uuid = v_auth
  order by case when u.auth_id = v_auth then 0 else 1 end
  limit 1;

  if v_user_id is null then
    raise exception 'user profile not found';
  end if;

  insert into public.app_chat_read_state (user_id, auth_id, last_read_at, updated_at)
  values (v_user_id, v_auth, v_at, v_at)
  on conflict (user_id) do update
  set
    auth_id = excluded.auth_id,
    last_read_at = excluded.last_read_at,
    updated_at = excluded.updated_at;

  return v_at;
end;
$$;

grant execute on function public.app_chat_mark_read() to authenticated;
