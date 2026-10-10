-- Fix RLS per visibilita' MDO ai dipendenti e ruoli custom collegati.

drop policy if exists logistica_mdo_ferroviari_select_dipendente on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_select_dipendente
on public.logistica_mdo_ferroviari
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti')
  )
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mdo_ferroviari_update_dipendente on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_update_dipendente
on public.logistica_mdo_ferroviari
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti')
  )
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti')
  )
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica')
);
