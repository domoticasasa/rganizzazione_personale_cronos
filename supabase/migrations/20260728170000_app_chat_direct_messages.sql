-- Messaggi privati 1:1: recipient null = gruppo aziendale.

alter table public.app_chat_messages
  add column if not exists recipient_user_id integer
    references public.users (id) on delete cascade,
  add column if not exists recipient_auth_id uuid,
  add column if not exists recipient_name text;

comment on column public.app_chat_messages.recipient_user_id is
  'NULL = messaggio di gruppo; valorizzato = messaggio privato al destinatario.';

create index if not exists app_chat_messages_recipient_auth_idx
  on public.app_chat_messages (recipient_auth_id, created_at desc)
  where recipient_auth_id is not null;

create index if not exists app_chat_messages_dm_pair_idx
  on public.app_chat_messages (sender_user_id, recipient_user_id, created_at desc)
  where recipient_user_id is not null;

-- Solo gruppo (tutti) oppure DM dove sei mittente o destinatario.
drop policy if exists app_chat_messages_select on public.app_chat_messages;
create policy app_chat_messages_select
  on public.app_chat_messages
  for select
  to authenticated
  using (
    recipient_auth_id is null
    or sender_auth_id = auth.uid()
    or recipient_auth_id = auth.uid()
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
        recipient_user_id is null
        and recipient_auth_id is null
      )
      or (
        recipient_user_id is not null
        and recipient_auth_id is not null
        and recipient_auth_id is distinct from auth.uid()
      )
    )
  );

-- Unread: solo messaggi visibili all'utente (gruppo + DM verso di lui).
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
    and m.sender_auth_id is distinct from v_auth
    and (
      m.recipient_auth_id is null
      or m.recipient_auth_id = v_auth
    );

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.app_chat_unread_count() to authenticated;
