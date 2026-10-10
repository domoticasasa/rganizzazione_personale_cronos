-- Hint batch per chat: foto tesserino + last_app_open_at (presenza).
create or replace function public.app_chat_peer_presence_hints(
  p_auth_ids uuid[]
)
returns table (
  auth_id uuid,
  foto_tesserino_path text,
  last_app_open_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_auth_ids is null or cardinality(p_auth_ids) = 0 then
    return;
  end if;

  return query
  with wanted as (
    select distinct unnest(p_auth_ids) as aid
  ),
  matched_users as (
    select distinct on (w.aid)
      w.aid as auth_id,
      u.id as user_id,
      u.auth_id as user_auth_id,
      u.id_uuid as user_id_uuid,
      u.email as user_email,
      u.last_app_open_at
    from wanted w
    join public.users u
      on u.auth_id = w.aid
      or u.id_uuid = w.aid
    order by
      w.aid,
      case when u.auth_id = w.aid then 0 else 1 end,
      u.id desc
  )
  select
    mu.auth_id,
    (
      select nullif(trim(p.foto_tesserino_path), '')
      from public.personale p
      where (
          nullif(trim(p.user_id::text), '') in (
            nullif(trim(coalesce(mu.user_auth_id::text, '')), ''),
            mu.user_id::text,
            nullif(trim(coalesce(mu.user_id_uuid::text, '')), '')
          )
        )
        or (
          nullif(trim(coalesce(mu.user_email, '')), '') is not null
          and lower(trim(coalesce(p.email, ''))) = lower(trim(mu.user_email))
        )
      order by coalesce(p.active, true) desc, p.id desc
      limit 1
    ) as foto_tesserino_path,
    mu.last_app_open_at
  from matched_users mu;
end;
$$;

grant execute on function public.app_chat_peer_presence_hints(uuid[]) to authenticated;

comment on function public.app_chat_peer_presence_hints(uuid[]) is
  'Batch foto tesserino + last_app_open_at per avatar/presenza in chat.';
