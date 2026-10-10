-- Lista POS: DT e assistente DT solo lettura; scrittura per admin / UQSA / formazione.

create or replace function public.is_pos_commessa_dipendenti_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_formazione',
        'uqsa'
      )
  )
  or public.has_custom_page_access('pos_dipendenti_lista');
$$;

grant execute on function public.is_pos_commessa_dipendenti_manager() to authenticated;

-- SELECT: invariato (include DT tramite is_pos_commessa_dipendenti_user).
-- INSERT/UPDATE/DELETE: solo chi gestisce la lista.

drop policy if exists pos_commessa_lista_meta_insert on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_insert
on public.pos_commessa_lista_meta
for insert
to authenticated
with check (public.is_pos_commessa_dipendenti_manager());

drop policy if exists pos_commessa_lista_meta_update on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_update
on public.pos_commessa_lista_meta
for update
to authenticated
using (public.is_pos_commessa_dipendenti_manager())
with check (public.is_pos_commessa_dipendenti_manager());

drop policy if exists pos_commessa_lista_meta_delete on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_delete
on public.pos_commessa_lista_meta
for delete
to authenticated
using (public.is_pos_commessa_dipendenti_manager());

drop policy if exists pos_commessa_dipendenti_insert on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_insert
on public.pos_commessa_dipendenti
for insert
to authenticated
with check (public.is_pos_commessa_dipendenti_manager());

drop policy if exists pos_commessa_dipendenti_update on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_update
on public.pos_commessa_dipendenti
for update
to authenticated
using (public.is_pos_commessa_dipendenti_manager())
with check (public.is_pos_commessa_dipendenti_manager());

drop policy if exists pos_commessa_dipendenti_delete on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_delete
on public.pos_commessa_dipendenti
for delete
to authenticated
using (public.is_pos_commessa_dipendenti_manager());
