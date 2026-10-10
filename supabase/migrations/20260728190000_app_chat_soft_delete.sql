-- Soft-delete messaggi chat: resta la riga con «Messaggio cancellato».

alter table public.app_chat_messages
  add column if not exists deleted_at timestamptz;

comment on column public.app_chat_messages.deleted_at is
  'Se valorizzato, il messaggio è cancellato dal mittente (contenuto rimosso).';

-- Messaggio valido se ha contenuto OPPURE è cancellato.
alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_body_or_attachment;

alter table public.app_chat_messages
  add constraint app_chat_messages_body_or_attachment check (
    deleted_at is not null
    or (
      (body is not null and length(trim(body)) > 0)
      or (attachment_path is not null and length(trim(attachment_path)) > 0)
    )
  );

-- Solo il mittente può soft-delete (e solo i propri campi di cancellazione).
drop policy if exists app_chat_messages_update_own on public.app_chat_messages;
create policy app_chat_messages_update_own
  on public.app_chat_messages
  for update
  to authenticated
  using (sender_auth_id = auth.uid())
  with check (sender_auth_id = auth.uid());

create or replace function public.app_chat_delete_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_auth uuid := auth.uid();
  v_path text;
  v_updated integer := 0;
begin
  if v_auth is null then
    raise exception 'not authenticated';
  end if;

  select m.attachment_path
    into v_path
  from public.app_chat_messages m
  where m.id = p_message_id
    and m.sender_auth_id = v_auth
    and m.deleted_at is null
  for update;

  if not found then
    return false;
  end if;

  if v_path is not null and length(trim(v_path)) > 0 then
    delete from storage.objects o
    where o.bucket_id = 'chat_allegati'
      and o.name = v_path;
  end if;

  update public.app_chat_messages m
  set
    deleted_at = timezone('utc', now()),
    body = null,
    attachment_path = null,
    attachment_name = null,
    attachment_mime = null,
    attachment_size = null
  where m.id = p_message_id
    and m.sender_auth_id = v_auth
    and m.deleted_at is null;

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

grant execute on function public.app_chat_delete_message(uuid) to authenticated;
