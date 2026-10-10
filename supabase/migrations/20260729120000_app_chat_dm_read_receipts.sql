-- Ricevute di lettura chat privata (per conversazione 1:1).

create table if not exists public.app_chat_dm_read_state (
  user_id integer not null references public.users (id) on delete cascade,
  auth_id uuid not null,
  peer_user_id integer not null references public.users (id) on delete cascade,
  peer_auth_id uuid not null,
  last_read_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (auth_id, peer_auth_id)
);

create index if not exists app_chat_dm_read_state_peer_auth_idx
  on public.app_chat_dm_read_state (peer_auth_id);

comment on table public.app_chat_dm_read_state is
  'Ultima lettura DM: user ha letto i messaggi della chat con peer.';

alter table public.app_chat_dm_read_state enable row level security;

drop policy if exists app_chat_dm_read_state_select on public.app_chat_dm_read_state;
create policy app_chat_dm_read_state_select
  on public.app_chat_dm_read_state
  for select
  to authenticated
  using (auth_id = auth.uid() or peer_auth_id = auth.uid());

drop policy if exists app_chat_dm_read_state_insert_own on public.app_chat_dm_read_state;
create policy app_chat_dm_read_state_insert_own
  on public.app_chat_dm_read_state
  for insert
  to authenticated
  with check (auth_id = auth.uid());

drop policy if exists app_chat_dm_read_state_update_own on public.app_chat_dm_read_state;
create policy app_chat_dm_read_state_update_own
  on public.app_chat_dm_read_state
  for update
  to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

-- Segna come letti i messaggi privati con un peer.
create or replace function public.app_chat_dm_mark_read(
  p_peer_user_id integer,
  p_peer_auth_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer;
  v_auth uuid := auth.uid();
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;
  if p_peer_user_id is null or p_peer_user_id <= 0 or p_peer_auth_id is null then
    raise exception 'peer required';
  end if;

  select u.id into v_uid
  from public.users u
  where u.auth_id = v_auth or u.id_uuid = v_auth
  limit 1;

  if v_uid is null then
    raise exception 'user profile missing';
  end if;

  insert into public.app_chat_dm_read_state (
    user_id, auth_id, peer_user_id, peer_auth_id, last_read_at, updated_at
  ) values (
    v_uid, v_auth, p_peer_user_id, p_peer_auth_id, timezone('utc', now()), timezone('utc', now())
  )
  on conflict (auth_id, peer_auth_id) do update
  set
    last_read_at = excluded.last_read_at,
    updated_at = excluded.updated_at,
    user_id = excluded.user_id,
    peer_user_id = excluded.peer_user_id;
end;
$$;

grant execute on function public.app_chat_dm_mark_read(integer, uuid) to authenticated;

-- Quando il peer ha letto l'ultima volta i miei messaggi (per ricevute «Letto»).
create or replace function public.app_chat_dm_peer_last_read(
  p_peer_user_id integer,
  p_peer_auth_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_ts timestamptz;
begin
  if v_auth is null then
    return null;
  end if;

  select r.last_read_at
  into v_ts
  from public.app_chat_dm_read_state r
  where r.auth_id = p_peer_auth_id
    and r.peer_auth_id = v_auth
  limit 1;

  if v_ts is null and p_peer_user_id is not null and p_peer_user_id > 0 then
    select r.last_read_at
    into v_ts
    from public.app_chat_dm_read_state r
    where r.user_id = p_peer_user_id
      and r.peer_auth_id = v_auth
    limit 1;
  end if;

  return v_ts;
end;
$$;

grant execute on function public.app_chat_dm_peer_last_read(integer, uuid) to authenticated;

-- Realtime per aggiornare «Letto» subito quando il peer apre la chat.
do $$
begin
  alter publication supabase_realtime add table public.app_chat_dm_read_state;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
