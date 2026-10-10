-- Estende RLS ai ruoli personalizzati anche fuori Logistica,
-- allineando i dati visibili alle pagine abilitate dal manager ruoli.

-- Safety: se la funzione non esiste ancora, la creiamo.
create or replace function public.has_custom_page_access(p_page_key text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.users u
    join public.app_custom_roles acr
      on lower(acr.role_key) = lower(coalesce(u.role, ''))
     and acr.active = true
    join public.app_custom_role_pages arp
      on lower(arp.role_key) = lower(acr.role_key)
     and lower(arp.page_key) = lower(p_page_key)
     and arp.can_view = true
    where u.auth_id = auth.uid()
  );
$$;

-- ==================================
-- FORMAZIONE D.LGS. 81/08 (formazione_corsi)
-- ==================================
drop policy if exists formazione_corsi_custom_role_read on public.formazione_corsi;
create policy formazione_corsi_custom_role_read
on public.formazione_corsi
for select
to authenticated
using (public.has_custom_page_access('formazione_dlgs_81_08'));

drop policy if exists formazione_corsi_custom_role_write on public.formazione_corsi;
create policy formazione_corsi_custom_role_write
on public.formazione_corsi
for all
to authenticated
using (public.has_custom_page_access('formazione_dlgs_81_08'))
with check (public.has_custom_page_access('formazione_dlgs_81_08'));

-- ==================================
-- PERMESSI ASSISTENTI DT
-- ==================================
drop policy if exists assistente_dt_permissions_custom_role_select on public.assistente_dt_permissions;
create policy assistente_dt_permissions_custom_role_select
on public.assistente_dt_permissions
for select
to authenticated
using (public.has_custom_page_access('permessi_assistenti_dt'));

drop policy if exists assistente_dt_permissions_custom_role_write on public.assistente_dt_permissions;
create policy assistente_dt_permissions_custom_role_write
on public.assistente_dt_permissions
for all
to authenticated
using (public.has_custom_page_access('permessi_assistenti_dt'))
with check (public.has_custom_page_access('permessi_assistenti_dt'));

