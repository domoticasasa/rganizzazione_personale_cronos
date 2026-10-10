-- Accettazione regolamento chat GESTOPRO + divieto allegati in messaggi privati.

alter table public.users
  add column if not exists chat_rules_accepted_at timestamptz,
  add column if not exists chat_rules_notice_version text;

comment on column public.users.chat_rules_accepted_at is
  'Quando l''utente ha accettato il regolamento della chat aziendale.';
comment on column public.users.chat_rules_notice_version is
  'Versione del regolamento chat accettato (es. v1).';

create or replace function public.has_accepted_app_chat_rules(
  p_notice_version text default 'v1'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  return exists (
    select 1
    from public.users u
    where (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
      and u.chat_rules_accepted_at is not null
      and coalesce(u.chat_rules_notice_version, '') = coalesce(p_notice_version, 'v1')
  );
end;
$$;

create or replace function public.accept_app_chat_rules(
  p_notice_version text default 'v1'
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_ver text := coalesce(nullif(trim(p_notice_version), ''), 'v1');
  v_updated integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  update public.users u
  set
    chat_rules_accepted_at = v_at,
    chat_rules_notice_version = v_ver
  where u.auth_id = auth.uid();

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    update public.users u
    set
      chat_rules_accepted_at = v_at,
      chat_rules_notice_version = v_ver
    where u.id_uuid = auth.uid();
    get diagnostics v_updated = row_count;
  end if;

  if v_updated = 0 then
    raise exception 'user profile not found';
  end if;

  return v_at;
end;
$$;

grant execute on function public.has_accepted_app_chat_rules(text) to authenticated;
grant execute on function public.accept_app_chat_rules(text) to authenticated;

-- Nelle chat private non si possono allegare foto/documenti.
alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_dm_no_attachment;

alter table public.app_chat_messages
  add constraint app_chat_messages_dm_no_attachment check (
    recipient_user_id is null
    or (
      (attachment_path is null or length(trim(attachment_path)) = 0)
      and (attachment_name is null or length(trim(attachment_name)) = 0)
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
        recipient_user_id is null
        and recipient_auth_id is null
      )
      or (
        recipient_user_id is not null
        and recipient_auth_id is not null
        and recipient_auth_id is distinct from auth.uid()
        and (attachment_path is null or length(trim(attachment_path)) = 0)
      )
    )
  );
