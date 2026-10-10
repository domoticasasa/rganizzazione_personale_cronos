-- Fix badge chat: mark lettura anche per admin; unread ignora soft-delete;
-- membership anche per user_id (non solo auth_id sulla riga members).

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
      and (
        m.auth_id = auth.uid()
        or m.user_id in (
          select u.id
          from public.users u
          where u.auth_id = auth.uid()
             or u.id_uuid = auth.uid()
        )
      )
  );
$$;

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

  select u.id into v_user_id
  from public.users u
  where u.auth_id = v_auth or u.id_uuid = v_auth
  order by case when u.auth_id = v_auth then 0 else 1 end
  limit 1;

  if v_user_id is null then
    raise exception 'user profile not found';
  end if;

  if not public.is_app_chat_group_member(p_group_id)
     and not public.is_app_chat_admin() then
    raise exception 'not a group member';
  end if;

  -- Admin che apre un gruppo: assicurati che possa salvare il cursore lettura.
  if not public.is_app_chat_group_member(p_group_id)
     and public.is_app_chat_admin() then
    insert into public.app_chat_group_members (
      group_id, user_id, auth_id, role, invited_by_user_id
    )
    values (p_group_id, v_user_id, v_auth, 'admin', v_user_id)
    on conflict do nothing;
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
    where m.group_id is not null
      and m.deleted_at is null
      and m.created_at >= v_cutoff
      and m.sender_auth_id is distinct from v_auth
      and public.is_app_chat_group_member(m.group_id)
      and m.created_at > coalesce(
        (
          select gr.last_read_at
          from public.app_chat_group_read_state gr
          where gr.group_id = m.group_id
            and (
              gr.auth_id = v_auth
              or gr.user_id in (
                select u.id from public.users u
                where u.auth_id = v_auth or u.id_uuid = v_auth
              )
            )
          order by gr.last_read_at desc
          limit 1
        ),
        v_cutoff
      )
    group by m.group_id
  ) sub;

  select r.last_read_at into v_dm_last
  from public.app_chat_read_state r
  where r.auth_id = v_auth
     or r.user_id in (
       select u.id from public.users u
       where u.auth_id = v_auth or u.id_uuid = v_auth
     )
  order by r.last_read_at desc
  limit 1;

  if v_dm_last is null then
    v_dm_last := v_cutoff;
  elsif v_dm_last < v_cutoff then
    v_dm_last := v_cutoff;
  end if;

  select count(*)::integer into v_dm_count
  from public.app_chat_messages m
  where m.group_id is null
    and m.deleted_at is null
    and m.recipient_auth_id = v_auth
    and m.created_at >= v_cutoff
    and m.created_at > v_dm_last
    and m.sender_auth_id is distinct from v_auth;

  return coalesce(v_group_count, 0) + coalesce(v_dm_count, 0);
end;
$$;
