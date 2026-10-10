-- Soft-delete più robusto: non fallisce se lo storage non è cancellabile.

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

  -- Best-effort: non bloccare la cancellazione del messaggio.
  if v_path is not null and length(trim(v_path)) > 0 then
    begin
      delete from storage.objects o
      where o.bucket_id = 'chat_allegati'
        and o.name = v_path;
    exception
      when others then
        null;
    end;
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
