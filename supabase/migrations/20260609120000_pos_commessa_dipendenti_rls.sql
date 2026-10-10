-- RLS lista dipendenti POS per commessa (hub UQSA): DT, assistente DT, admin, formazione, UQSA.

insert into public.app_page_registry (page_key, label, active)
values ('pos_dipendenti_lista', 'Lista dipendenti POS', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

grant select, insert, update, delete on public.pos_commessa_lista_meta to authenticated;
grant select, insert, update, delete on public.pos_commessa_dipendenti to authenticated;

alter table public.pos_commessa_lista_meta enable row level security;
alter table public.pos_commessa_dipendenti enable row level security;

create or replace function public.is_pos_commessa_dipendenti_user()
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
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_formazione',
        'uqsa'
      )
  )
  or public.has_custom_page_access('pos_dipendenti_lista')
  or public.has_custom_page_access('uqsa');
$$;

grant execute on function public.is_pos_commessa_dipendenti_user() to authenticated;

-- pos_commessa_lista_meta
drop policy if exists pos_commessa_lista_meta_select on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_select
on public.pos_commessa_lista_meta
for select
to authenticated
using (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_lista_meta_insert on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_insert
on public.pos_commessa_lista_meta
for insert
to authenticated
with check (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_lista_meta_update on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_update
on public.pos_commessa_lista_meta
for update
to authenticated
using (public.is_pos_commessa_dipendenti_user())
with check (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_lista_meta_delete on public.pos_commessa_lista_meta;
create policy pos_commessa_lista_meta_delete
on public.pos_commessa_lista_meta
for delete
to authenticated
using (public.is_pos_commessa_dipendenti_user());

-- pos_commessa_dipendenti
drop policy if exists pos_commessa_dipendenti_select on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_select
on public.pos_commessa_dipendenti
for select
to authenticated
using (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_dipendenti_insert on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_insert
on public.pos_commessa_dipendenti
for insert
to authenticated
with check (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_dipendenti_update on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_update
on public.pos_commessa_dipendenti
for update
to authenticated
using (public.is_pos_commessa_dipendenti_user())
with check (public.is_pos_commessa_dipendenti_user());

drop policy if exists pos_commessa_dipendenti_delete on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_delete
on public.pos_commessa_dipendenti
for delete
to authenticated
using (public.is_pos_commessa_dipendenti_user());
