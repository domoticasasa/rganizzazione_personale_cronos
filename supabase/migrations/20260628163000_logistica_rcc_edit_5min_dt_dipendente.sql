-- DT e dipendente possono modificare un rifornimento solo entro 5 minuti dal salvataggio.
-- Dopo la finestra, restano validi solo i permessi admin/logistica già esistenti.

drop policy if exists logistica_rcc_carburante_update_dt_dipendente_5min
  on public.logistica_rcc_carburante;

create policy logistica_rcc_carburante_update_dt_dipendente_5min
on public.logistica_rcc_carburante
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        (
          lower(coalesce(u.role, '')) = 'dt'
          and logistica_rcc_carburante.dt_user_uuid = u.id_uuid
        )
        or
        (
          lower(coalesce(u.role, '')) in ('dipendente', 'user', 'caposquadra')
          and logistica_rcc_carburante.user_uuid = u.id_uuid
        )
      )
  )
  and coalesce(logistica_rcc_carburante.updated_at, logistica_rcc_carburante.created_at)
      >= (now() - interval '5 minutes')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        (
          lower(coalesce(u.role, '')) = 'dt'
          and logistica_rcc_carburante.dt_user_uuid = u.id_uuid
        )
        or
        (
          lower(coalesce(u.role, '')) in ('dipendente', 'user', 'caposquadra')
          and logistica_rcc_carburante.user_uuid = u.id_uuid
        )
      )
  )
  and coalesce(logistica_rcc_carburante.updated_at, logistica_rcc_carburante.created_at)
      >= (now() - interval '5 minutes')
);
