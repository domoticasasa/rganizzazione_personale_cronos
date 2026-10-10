-- Non letti DM per singolo mittente (per evidenziare nome in inbox Privato).

create or replace function public.app_chat_dm_unread_by_peer()
returns table(peer_auth_id uuid, unread_count integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth uuid := auth.uid();
  v_dm_last timestamptz;
  v_cutoff timestamptz := timezone('utc', now()) - interval '7 days';
begin
  if v_auth is null then
    return;
  end if;

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

  return query
  select
    m.sender_auth_id::uuid as peer_auth_id,
    count(*)::integer as unread_count
  from public.app_chat_messages m
  where m.group_id is null
    and m.deleted_at is null
    and m.recipient_auth_id = v_auth
    and m.created_at >= v_cutoff
    and m.created_at > v_dm_last
    and m.sender_auth_id is distinct from v_auth
  group by m.sender_auth_id;
end;
$$;

grant execute on function public.app_chat_dm_unread_by_peer() to authenticated;

comment on function public.app_chat_dm_unread_by_peer() is
  'Ritorna (peer_auth_id, unread_count) DM non letti per mittente.';
