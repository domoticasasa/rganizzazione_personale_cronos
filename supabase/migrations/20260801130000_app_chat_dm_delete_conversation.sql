-- Cancella (soft-delete) una conversazione DM tra utente corrente e peer.

create or replace function public.app_chat_dm_delete_conversation(
  p_peer_user_id integer default null,
  p_peer_auth_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_peer_auth uuid := p_peer_auth_id;
  v_peer_user integer := p_peer_user_id;
  v_deleted integer := 0;
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;

  if v_peer_auth is null and v_peer_user is null then
    raise exception 'peer required';
  end if;

  if v_peer_auth is null and v_peer_user is not null then
    select coalesce(u.auth_id, u.id_uuid)
      into v_peer_auth
    from public.users u
    where u.id = v_peer_user
    limit 1;
  end if;

  if v_peer_user is null and v_peer_auth is not null then
    select u.id
      into v_peer_user
    from public.users u
    where u.auth_id = v_peer_auth or u.id_uuid = v_peer_auth
    order by case when u.auth_id = v_peer_auth then 0 else 1 end
    limit 1;
  end if;

  if v_peer_auth is null then
    raise exception 'peer not found';
  end if;

  update public.app_chat_messages m
  set
    deleted_at = coalesce(m.deleted_at, timezone('utc', now())),
    body = null,
    attachment_path = null,
    attachment_name = null,
    attachment_mime = null,
    attachment_size = null
  where m.group_id is null
    and m.deleted_at is null
    and (
      (m.sender_auth_id = v_auth and m.recipient_auth_id = v_peer_auth)
      or
      (m.sender_auth_id = v_peer_auth and m.recipient_auth_id = v_auth)
    );

  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

grant execute on function public.app_chat_dm_delete_conversation(integer, uuid) to authenticated;

comment on function public.app_chat_dm_delete_conversation(integer, uuid) is
  'Soft-delete di tutti i messaggi DM tra utente corrente e peer.';
