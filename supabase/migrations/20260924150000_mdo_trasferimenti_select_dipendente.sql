-- Lettura trasferimenti MDO anche per dipendenti (vista Mezzi sola lettura).

drop policy if exists logistica_mdo_trasferimenti_select_dipendente
  on public.logistica_mdo_trasferimenti;
create policy logistica_mdo_trasferimenti_select_dipendente
on public.logistica_mdo_trasferimenti
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = (select auth.uid())
      and lower(coalesce(u.role, '')) in ('dipendente', 'dipendenti', 'user')
  )
);

-- Grant espliciti (post-cambio default Data API ottobre 2026).
grant select on public.logistica_mdo_trasferimenti to authenticated;
grant select, insert, update, delete
  on public.logistica_mdo_trasferimenti to service_role;
