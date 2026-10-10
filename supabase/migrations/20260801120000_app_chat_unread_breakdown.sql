-- Conteggio non letti separato: gruppo vs privato (per lampeggio tab chat).

create or replace function public.app_chat_unread_breakdown()
returns jsonb
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
    return jsonb_build_object('group', 0, 'dm', 0, 'total', 0);
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

  return jsonb_build_object(
    'group', coalesce(v_group_count, 0),
    'dm', coalesce(v_dm_count, 0),
    'total', coalesce(v_group_count, 0) + coalesce(v_dm_count, 0)
  );
end;
$$;

grant execute on function public.app_chat_unread_breakdown() to authenticated;

comment on function public.app_chat_unread_breakdown() is
  'Non letti chat: {group, dm, total} per badge/lampeggio tab Gruppo vs Privato.';
