-- Consenti visibilita' MDO anche agli utenti con ruolo "user"
-- (oltre a dipendente/dipendenti), visto che in alcuni account dipendente
-- il ruolo salvato in users.role e' "user".

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
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti', 'user')
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
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti', 'user')
  )
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti', 'user')
  )
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica')
);
