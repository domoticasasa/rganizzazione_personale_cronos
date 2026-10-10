-- Ricevute gruppo: admin può leggere tutti i cursori (anche via Realtime RLS).
-- Senza questo, Realtime non consegna gli UPDATE degli altri utenti agli admin.

drop policy if exists app_chat_group_read_state_select on public.app_chat_group_read_state;
create policy app_chat_group_read_state_select
  on public.app_chat_group_read_state
  for select
  to authenticated
  using (
    auth_id = auth.uid()
    or public.is_app_chat_group_member(group_id)
    or public.is_app_chat_admin()
  );

do $$
begin
  alter publication supabase_realtime add table public.app_chat_group_read_state;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
