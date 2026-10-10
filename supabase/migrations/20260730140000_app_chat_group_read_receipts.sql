-- Ricevute lettura chat di gruppo: tutti gli autenticati possono vedere
-- last_read_at degli altri (stesso modello cursore già usato per il badge).

drop policy if exists app_chat_read_state_select_own on public.app_chat_read_state;
drop policy if exists app_chat_read_state_select_all on public.app_chat_read_state;
create policy app_chat_read_state_select_all
  on public.app_chat_read_state
  for select
  to authenticated
  using (true);

comment on table public.app_chat_read_state is
  'Ultima lettura chat aziendale per utente (badge non letti + ricevute gruppo).';

create or replace function public.app_chat_group_read_states()
returns table (
  user_id integer,
  auth_id uuid,
  display_name text,
  last_read_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.user_id,
    r.auth_id,
    coalesce(
      nullif(trim(u.full_name), ''),
      nullif(trim(u.username), ''),
      nullif(trim(u.email), ''),
      'Utente'
    ) as display_name,
    r.last_read_at
  from public.app_chat_read_state r
  left join public.users u on u.id = r.user_id
  where auth.uid() is not null
  order by display_name asc;
$$;

grant execute on function public.app_chat_group_read_states() to authenticated;

comment on function public.app_chat_group_read_states() is
  'Stati lettura gruppo con nome visualizzato (per ricevute «letto da»).';

do $$
begin
  alter publication supabase_realtime add table public.app_chat_read_state;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;
