-- Admin pernottamenti: stessi accessi dati di Admin generale
-- (es. giacenza magazzino DPI / inventario vestiario).

create or replace function public.is_admin_generale_equivalent()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_pernottamenti'
  );
$$;

comment on function public.is_admin_generale_equivalent() is
  'Admin, Admin generale e Admin pernottamenti: stessi permessi operativi.';

grant execute on function public.is_admin_generale_equivalent() to authenticated;

-- Giacenza magazzino DPI / inventario vestiario
create or replace function public.is_vestiario_magazzino_user()
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
        'admin_dpi',
        'uqsa',
        'caposquadra'
      )
  )
  or public.has_custom_page_access('vestiario_inventario')
  or public.has_custom_page_access('vestiario_report')
  or public.has_custom_page_access('vestiario_fabbisogno_taglie')
  or public.has_custom_page_access('dpi')
  or public.has_custom_page_access('uqsa')
  or public.has_custom_page_access('dotazioni_dpi');
$$;

-- Estintori (policy live senza admin_pernottamenti)
drop policy if exists estintori_select_role_allowed on public.estintori;
create policy estintori_select_role_allowed
on public.estintori
for select
to authenticated
using (
  public.is_admin_generale_equivalent()
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('estintori')
);

drop policy if exists estintori_insert_role_allowed on public.estintori;
create policy estintori_insert_role_allowed
on public.estintori
for insert
to authenticated
with check (
  public.is_admin_generale_equivalent()
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('estintori')
);

drop policy if exists estintori_update_role_allowed on public.estintori;
create policy estintori_update_role_allowed
on public.estintori
for update
to authenticated
using (
  public.is_admin_generale_equivalent()
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('estintori')
)
with check (
  public.is_admin_generale_equivalent()
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('estintori')
);

drop policy if exists estintori_delete_role_allowed on public.estintori;
create policy estintori_delete_role_allowed
on public.estintori
for delete
to authenticated
using (
  public.is_admin_generale_equivalent()
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('estintori')
);

-- Strutture RFI: scrittura come Admin generale
drop policy if exists formazione_rfi_strutture_write on public.formazione_rfi_strutture;
create policy formazione_rfi_strutture_write
on public.formazione_rfi_strutture
for all
to authenticated
using (
  public.is_admin_generale_equivalent()
  or exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'admin_formazione'
  )
  or public.has_custom_page_access('formazione_rfi')
)
with check (
  public.is_admin_generale_equivalent()
  or exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'admin_formazione'
  )
  or public.has_custom_page_access('formazione_rfi')
);

-- Tesserini / modelli commessa
drop policy if exists commessa_tesserino_modelli_select on public.commessa_tesserino_modelli;
create policy commessa_tesserino_modelli_select
on public.commessa_tesserino_modelli
for select
to authenticated
using (
  public.is_admin_generale_equivalent()
  or public.current_user_role_norm() in (
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
  or public.has_custom_page_access('tesserino')
);

drop policy if exists commessa_tesserino_modelli_write on public.commessa_tesserino_modelli;
create policy commessa_tesserino_modelli_write
on public.commessa_tesserino_modelli
for all
to authenticated
using (
  public.is_admin_generale_equivalent()
  or public.current_user_role_norm() in (
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
)
with check (
  public.is_admin_generale_equivalent()
  or public.current_user_role_norm() in (
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
);

-- Gestione ruoli custom (Impostazioni)
drop policy if exists app_custom_roles_manage_admin_generale on public.app_custom_roles;
create policy app_custom_roles_manage_admin_generale
on public.app_custom_roles
for all
to authenticated
using (public.is_admin_generale_equivalent())
with check (public.is_admin_generale_equivalent());

drop policy if exists app_custom_role_pages_manage_admin_generale on public.app_custom_role_pages;
create policy app_custom_role_pages_manage_admin_generale
on public.app_custom_role_pages
for all
to authenticated
using (public.is_admin_generale_equivalent())
with check (public.is_admin_generale_equivalent());

drop policy if exists app_page_registry_manage_admin_generale on public.app_page_registry;
create policy app_page_registry_manage_admin_generale
on public.app_page_registry
for all
to authenticated
using (public.is_admin_generale_equivalent())
with check (public.is_admin_generale_equivalent());
