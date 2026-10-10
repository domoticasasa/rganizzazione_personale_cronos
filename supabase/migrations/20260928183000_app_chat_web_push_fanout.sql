-- Chat: Web Push anche se il client non chiama app-chat-notify.
-- Stesso vault `service_role_key` di invoke_admin_send_push.

create or replace function public.invoke_app_chat_notify(p_message_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  v_key text;
  v_url text;
  v_request_id bigint;
begin
  if p_message_id is null then
    return 0;
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net non disponibile: skip invoke_app_chat_notify';
    return 0;
  end if;

  begin
    select ds.decrypted_secret
      into v_key
    from vault.decrypted_secrets ds
    where ds.name = 'service_role_key'
    limit 1;
  exception when others then
    v_key := null;
  end;

  if coalesce(trim(v_key), '') = '' then
    raise notice 'Vault secret service_role_key assente: skip chat Web Push.';
    return 0;
  end if;

  v_url := 'https://bjdimalvbdablzoctrsf.supabase.co/functions/v1/app-chat-notify';

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key,
      'apikey', v_key
    ),
    body := jsonb_build_object('message_id', p_message_id),
    timeout_milliseconds := 15000
  )
  into v_request_id;

  return coalesce(v_request_id, 0);
end;
$$;

comment on function public.invoke_app_chat_notify(uuid) is
  'Chiama app-chat-notify (Web Push + FCM) per un messaggio chat. Vault: service_role_key.';

create or replace function public.app_chat_messages_fanout_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.invoke_app_chat_notify(new.id);
  return new;
exception
  when others then
    raise warning 'app_chat_messages_fanout_push: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_app_chat_messages_fanout_push on public.app_chat_messages;
create trigger trg_app_chat_messages_fanout_push
after insert on public.app_chat_messages
for each row
execute function public.app_chat_messages_fanout_push();
