-- Allegati in chat privata: solo amministratori chat (is_app_chat_admin).
-- Rimuove il CHECK assoluto e aggiorna la policy INSERT.

alter table public.app_chat_messages
  drop constraint if exists app_chat_messages_dm_no_attachment;

drop policy if exists app_chat_messages_insert on public.app_chat_messages;
create policy app_chat_messages_insert
  on public.app_chat_messages
  for insert
  to authenticated
  with check (
    sender_auth_id = auth.uid()
    and (
      (
        group_id is not null
        and recipient_user_id is null
        and recipient_auth_id is null
        and public.is_app_chat_group_member(group_id)
      )
      or (
        group_id is null
        and recipient_user_id is not null
        and recipient_auth_id is not null
        and recipient_auth_id is distinct from auth.uid()
        and (
          attachment_path is null
          or public.is_app_chat_admin()
        )
      )
    )
  );
