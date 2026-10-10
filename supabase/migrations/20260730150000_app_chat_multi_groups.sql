-- Chat: gruppi multipli (solo admin crea), messaggi solo per invitati.

-- ---------------------------------------------------------------------------
-- Tables first (helpers that reference members come after)
-- ---------------------------------------------------------------------------
create table if not exists public.app_chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  created_by_user_id integer references public.users (id) on delete set null,
  created_by_auth_id uuid,
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint app_chat_groups_name_nonempty check (length(trim(name)) > 0)
);

create index if not exists app_chat_groups_created_at_idx
  on public.app_chat_groups (created_at desc);

comment on table public.app_chat_groups is
  'Chat di gruppo GESTOPRO (solo admin crea; messaggi solo per membri).';

create table if not exists public.app_chat_group_members (
  group_id uuid not null references public.app_chat_groups (id) on delete cascade,
  user_id integer not null references public.users (id) on delete cascade,
  auth_id uuid not null,
  role text not null default 'member'
    check (role in ('member', 'admin')),
  invited_by_user_id integer references public.users (id) on delete set null,
  joined_at timestamptz not null default timezone('utc', now()),
  primary key (group_id, user_id),
  unique (group_id, auth_id)
);

create index if not exists app_chat_group_members_auth_idx
  on public.app_chat_group_members (auth_id);

comment on table public.app_chat_group_members is
  'Invitati a un gruppo chat: solo loro vedono i messaggi del gruppo.';

create table if not exists public.app_chat_group_read_state (
  group_id uuid not null references public.app_chat_groups (id) on delete cascade,
  user_id integer not null references public.users (id) on delete cascade,
  auth_id uuid not null,
  last_read_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (group_id, auth_id)
);

create index if not exists app_chat_group_read_state_auth_idx
  on public.app_chat_group_read_state (auth_id);

comment on table public.app_chat_group_read_state is
  'Cursore lettura per gruppo (badge + ricevute «letto da»).';

alter table public.app_chat_groups enable row level security;
alter table public.app_chat_group_members enable row level security;
alter table public.app_chat_group_read_state enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_app_chat_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'admin_formazione',
    'admin_dpi'
  );
$$;

grant execute on function public.is_app_chat_admin() to authenticated;

create or replace function public.is_app_chat_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_chat_group_members m
    where m.group_id = p_group_id
      and m.auth_id = auth.uid()
  );
$$;

grant execute on function public.is_app_chat_group_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Seed gruppo default + colonna messages.group_id
-- ---------------------------------------------------------------------------
do $$
declare
  v_gid uuid;
begin
  select id into v_gid
  from public.app_chat_groups
  where name = 'Aziendale'
  order by created_at
  limit 1;

  if v_gid is null then
    insert into public.app_chat_groups (name, description)
    values (
      'Aziendale',
      'Gruppo predefinito (tutti gli utenti con login).'
    )
    returning id into v_gid;
  end if;

  insert into public.app_chat_group_members (group_id, user_id, auth_id, role)
  select
    v_gid,
    u.id,
    coalesce(u.auth_id, u.id_uuid),
    'member'
  from public.users u
  where coalesce(u.auth_id, u.id_uuid) is not null
  on conflict do nothing;
end
$$;

alter table public.app_chat_messages
  add column if not exists group_id uuid references public.app_chat_groups (id) on delete cascade;

create index if not exists app_chat_messages_group_created_idx
  on public.app_chat_messages (group_id, created_at desc)
  where group_id is not null;

update public.app_chat_messages m
set group_id = g.id
from public.app_chat_groups g
where m.group_id is null
  and m.recipient_auth_id is null
  and m.recipient_user_id is null
  and g.name = 'Aziendale';

-- Constraint: gruppo XOR DM (messaggi non cancellati).
alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_body_or_attachment;

alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_dm_no_attachment;

alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_group_or_dm;

alter table public.app_chat_messages
  add constraint app_chat_messages_group_or_dm check (
    deleted_at is not null
    or (
      (
        group_id is not null
        and recipient_user_id is null
        and recipient_auth_id is null
      )
      or (
        group_id is null
        and recipient_user_id is not null
        and recipient_auth_id is not null
      )
    )
  );

alter table public.app_chat_messages
  add constraint app_chat_messages_body_or_attachment check (
    deleted_at is not null
    or (
      (body is not null and length(trim(body)) > 0)
      or (attachment_path is not null and length(trim(attachment_path)) > 0)
    )
  );

alter table public.app_chat_messages
  add constraint app_chat_messages_dm_no_attachment check (
    deleted_at is not null
    or group_id is not null
    or (
      attachment_path is null
      and attachment_name is null
      and attachment_mime is null
      and attachment_size is null
    )
  );

-- ---------------------------------------------------------------------------
-- RLS groups / members / read_state
-- ---------------------------------------------------------------------------
drop policy if exists app_chat_groups_select on public.app_chat_groups;
create policy app_chat_groups_select
  on public.app_chat_groups
  for select
  to authenticated
  using (
    public.is_app_chat_admin()
    or public.is_app_chat_group_member(id)
  );

drop policy if exists app_chat_groups_insert on public.app_chat_groups;
create policy app_chat_groups_insert
  on public.app_chat_groups
  for insert
  to authenticated
  with check (public.is_app_chat_admin());

drop policy if exists app_chat_groups_update on public.app_chat_groups;
create policy app_chat_groups_update
  on public.app_chat_groups
  for update
  to authenticated
  using (public.is_app_chat_admin())
  with check (public.is_app_chat_admin());

drop policy if exists app_chat_group_members_select on public.app_chat_group_members;
create policy app_chat_group_members_select
  on public.app_chat_group_members
  for select
  to authenticated
  using (
    public.is_app_chat_admin()
    or public.is_app_chat_group_member(group_id)
  );

drop policy if exists app_chat_group_members_insert on public.app_chat_group_members;
create policy app_chat_group_members_insert
  on public.app_chat_group_members
  for insert
  to authenticated
  with check (public.is_app_chat_admin());

drop policy if exists app_chat_group_members_delete on public.app_chat_group_members;
create policy app_chat_group_members_delete
  on public.app_chat_group_members
  for delete
  to authenticated
  using (public.is_app_chat_admin());

drop policy if exists app_chat_group_read_state_select on public.app_chat_group_read_state;
create policy app_chat_group_read_state_select
  on public.app_chat_group_read_state
  for select
  to authenticated
  using (
    auth_id = auth.uid()
    or public.is_app_chat_group_member(group_id)
  );

drop policy if exists app_chat_group_read_state_insert on public.app_chat_group_read_state;
create policy app_chat_group_read_state_insert
  on public.app_chat_group_read_state
  for insert
  to authenticated
  with check (auth_id = auth.uid());

drop policy if exists app_chat_group_read_state_update on public.app_chat_group_read_state;
create policy app_chat_group_read_state_update
  on public.app_chat_group_read_state
  for update
  to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Messages RLS: solo membri del gruppo / partecipanti DM
-- ---------------------------------------------------------------------------
drop policy if exists app_chat_messages_select on public.app_chat_messages;
create policy app_chat_messages_select
  on public.app_chat_messages
  for select
  to authenticated
  using (
    (
      group_id is not null
      and public.is_app_chat_group_member(group_id)
    )
    or (
      recipient_auth_id is not null
      and (
        sender_auth_id = auth.uid()
        or recipient_auth_id = auth.uid()
      )
    )
  );

drop policy if exists app_chat_messages_insert on public.app_chat_messages;
create policy app_chat_messages_insert
  on public.app_chat_messages
  for insert
  to authenticated
  with check (
    sender_auth_id = auth.uid()
    and (
      (
        group_id is not null
        and recipient_user_id is null
        and recipient_auth_id is null
        and public.is_app_chat_group_member(group_id)
      )
      or (
        group_id is null
        and recipient_user_id is not null
        and recipient_auth_id is not null
        and recipient_auth_id is distinct from auth.uid()
        and attachment_path is null
      )
    )
  );

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------
create or replace function public.app_chat_list_my_groups()
returns table (
  id uuid,
  name text,
  description text,
  is_archived boolean,
  member_count integer,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.name,
    g.description,
    g.is_archived,
    (
      select count(*)::integer
      from public.app_chat_group_members m
      where m.group_id = g.id
    ) as member_count,
    g.created_at
  from public.app_chat_groups g
  where not g.is_archived
    and (
      public.is_app_chat_admin()
      or public.is_app_chat_group_member(g.id)
    )
  order by
    case when g.name = 'Aziendale' then 0 else 1 end,
    g.name asc;
$$;

grant execute on function public.app_chat_list_my_groups() to authenticated;

create or replace function public.app_chat_create_group(
  p_name text,
  p_member_user_ids integer[] default '{}'::integer[],
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_user_id integer;
  v_gid uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_uid integer;
  v_auth_id uuid;
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_app_chat_admin() then
    raise exception 'only admin can create groups';
  end if;
  if length(v_name) = 0 then
    raise exception 'group name required';
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_id = v_auth or u.id_uuid = v_auth
  order by case when u.auth_id = v_auth then 0 else 1 end
  limit 1;

  insert into public.app_chat_groups (
    name, description, created_by_user_id, created_by_auth_id
  )
  values (v_name, nullif(trim(coalesce(p_description, '')), ''), v_user_id, v_auth)
  returning id into v_gid;

  -- Creator sempre membro
  if v_user_id is not null then
    insert into public.app_chat_group_members (
      group_id, user_id, auth_id, role, invited_by_user_id
    )
    values (v_gid, v_user_id, v_auth, 'admin', v_user_id)
    on conflict do nothing;
  end if;

  if p_member_user_ids is not null then
    foreach v_uid in array p_member_user_ids
    loop
      if v_uid is null or v_uid = v_user_id then
        continue;
      end if;
      select coalesce(u.auth_id, u.id_uuid) into v_auth_id
      from public.users u
      where u.id = v_uid
      limit 1;
      if v_auth_id is null then
        continue;
      end if;
      insert into public.app_chat_group_members (
        group_id, user_id, auth_id, role, invited_by_user_id
      )
      values (v_gid, v_uid, v_auth_id, 'member', v_user_id)
      on conflict do nothing;
    end loop;
  end if;

  return v_gid;
end;
$$;

grant execute on function public.app_chat_create_group(text, integer[], text) to authenticated;

create or replace function public.app_chat_set_group_members(
  p_group_id uuid,
  p_member_user_ids integer[] default '{}'::integer[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_admin_user_id integer;
  v_uid integer;
  v_auth_id uuid;
  v_count integer := 0;
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_app_chat_admin() then
    raise exception 'only admin can manage members';
  end if;
  if p_group_id is null then
    raise exception 'group_id required';
  end if;
  if not exists (select 1 from public.app_chat_groups g where g.id = p_group_id) then
    raise exception 'group not found';
  end if;

  select u.id into v_admin_user_id
  from public.users u
  where u.auth_id = v_auth or u.id_uuid = v_auth
  order by case when u.auth_id = v_auth then 0 else 1 end
  limit 1;

  delete from public.app_chat_group_members m
  where m.group_id = p_group_id
    and (
      p_member_user_ids is null
      or not (m.user_id = any (p_member_user_ids))
    )
    -- non rimuovere creator se presente
    and m.user_id is distinct from (
      select g.created_by_user_id from public.app_chat_groups g where g.id = p_group_id
    );

  if p_member_user_ids is not null then
    foreach v_uid in array p_member_user_ids
    loop
      if v_uid is null then
        continue;
      end if;
      select coalesce(u.auth_id, u.id_uuid) into v_auth_id
      from public.users u
      where u.id = v_uid
      limit 1;
      if v_auth_id is null then
        continue;
      end if;
      insert into public.app_chat_group_members (
        group_id, user_id, auth_id, role, invited_by_user_id
      )
      values (
        p_group_id,
        v_uid,
        v_auth_id,
        case when v_uid = v_admin_user_id then 'admin' else 'member' end,
        v_admin_user_id
      )
      on conflict (group_id, user_id) do update
      set auth_id = excluded.auth_id;
      v_count := v_count + 1;
    end loop;
  end if;

  return v_count;
end;
$$;

grant execute on function public.app_chat_set_group_members(uuid, integer[]) to authenticated;

create or replace function public.app_chat_list_group_members(p_group_id uuid)
returns table (
  user_id integer,
  auth_id uuid,
  display_name text,
  role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.user_id,
    m.auth_id,
    coalesce(
      nullif(trim(u.full_name), ''),
      nullif(trim(u.username), ''),
      nullif(trim(u.email), ''),
      'Utente'
    ) as display_name,
    m.role
  from public.app_chat_group_members m
  left join public.users u on u.id = m.user_id
  where m.group_id = p_group_id
    and (
      public.is_app_chat_admin()
      or public.is_app_chat_group_member(p_group_id)
    )
  order by display_name asc;
$$;

grant execute on function public.app_chat_list_group_members(uuid) to authenticated;

create or replace function public.app_chat_mark_group_read(p_group_id uuid)
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
  if p_group_id is null then
    raise exception 'group_id required';
  end if;
  if not public.is_app_chat_group_member(p_group_id)
     and not public.is_app_chat_admin() then
    raise exception 'not a group member';
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_id = v_auth or u.id_uuid = v_auth
  order by case when u.auth_id = v_auth then 0 else 1 end
  limit 1;

  if v_user_id is null then
    raise exception 'user profile not found';
  end if;

  -- Admin non membro: aggiungi come membro lettura-only? No — solo se membro.
  if not public.is_app_chat_group_member(p_group_id) then
    return v_at;
  end if;

  insert into public.app_chat_group_read_state (
    group_id, user_id, auth_id, last_read_at, updated_at
  )
  values (p_group_id, v_user_id, v_auth, v_at, v_at)
  on conflict (group_id, auth_id) do update
  set
    user_id = excluded.user_id,
    last_read_at = excluded.last_read_at,
    updated_at = excluded.updated_at;

  return v_at;
end;
$$;

grant execute on function public.app_chat_mark_group_read(uuid) to authenticated;

create or replace function public.app_chat_group_read_states(p_group_id uuid)
returns table (
  user_id integer,
  auth_id uuid,
  display_name text,
  last_read_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.user_id,
    r.auth_id,
    coalesce(
      nullif(trim(u.full_name), ''),
      nullif(trim(u.username), ''),
      nullif(trim(u.email), ''),
      'Utente'
    ) as display_name,
    r.last_read_at
  from public.app_chat_group_read_state r
  left join public.users u on u.id = r.user_id
  where r.group_id = p_group_id
    and auth.uid() is not null
    and (
      public.is_app_chat_admin()
      or public.is_app_chat_group_member(p_group_id)
    )
  order by display_name asc;
$$;

grant execute on function public.app_chat_group_read_states(uuid) to authenticated;

-- Unread: somma gruppi (per-group cursor) + DM (cursor globale legacy).
create or replace function public.app_chat_unread_count()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_dm_last timestamptz;
  v_cutoff timestamptz := timezone('utc', now()) - interval '7 days';
  v_group_count integer := 0;
  v_dm_count integer := 0;
begin
  if v_auth is null then
    return 0;
  end if;

  select coalesce(sum(sub.cnt), 0)::integer
    into v_group_count
  from (
    select count(*)::integer as cnt
    from public.app_chat_messages m
    join public.app_chat_group_members mem
      on mem.group_id = m.group_id
     and mem.auth_id = v_auth
    left join public.app_chat_group_read_state gr
      on gr.group_id = m.group_id
     and gr.auth_id = v_auth
    where m.group_id is not null
      and m.created_at >= v_cutoff
      and m.sender_auth_id is distinct from v_auth
      and m.created_at > coalesce(gr.last_read_at, v_cutoff)
    group by m.group_id
  ) sub;

  select r.last_read_at into v_dm_last
  from public.app_chat_read_state r
  where r.auth_id = v_auth
  limit 1;

  if v_dm_last is null then
    v_dm_last := v_cutoff;
  elsif v_dm_last < v_cutoff then
    v_dm_last := v_cutoff;
  end if;

  select count(*)::integer into v_dm_count
  from public.app_chat_messages m
  where m.group_id is null
    and m.recipient_auth_id = v_auth
    and m.created_at >= v_cutoff
    and m.created_at > v_dm_last
    and m.sender_auth_id is distinct from v_auth;

  return coalesce(v_group_count, 0) + coalesce(v_dm_count, 0);
end;
$$;

grant execute on function public.app_chat_unread_count() to authenticated;

-- Compat: vecchia firma senza group_id (non più usata dal client nuovo).
create or replace function public.app_chat_group_read_states()
returns table (
  user_id integer,
  auth_id uuid,
  display_name text,
  last_read_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.user_id,
    r.auth_id,
    coalesce(
      nullif(trim(u.full_name), ''),
      nullif(trim(u.username), ''),
      nullif(trim(u.email), ''),
      'Utente'
    ) as display_name,
    r.last_read_at
  from public.app_chat_group_read_state r
  left join public.users u on u.id = r.user_id
  join public.app_chat_groups g on g.id = r.group_id and g.name = 'Aziendale'
  where auth.uid() is not null
    and public.is_app_chat_group_member(r.group_id)
  order by display_name asc;
$$;

do $$
begin
  alter publication supabase_realtime add table public.app_chat_groups;
exception when duplicate_object then null; when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.app_chat_group_members;
exception when duplicate_object then null; when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.app_chat_group_read_state;
exception when duplicate_object then null; when undefined_object then null;
end $$;
