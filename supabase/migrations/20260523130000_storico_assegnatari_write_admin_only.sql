-- Modifica storico assegnatari: solo ruoli admin (non logistica/DT).

drop policy if exists logistica_asset_assegnatari_storico_write on public.logistica_asset_assegnatari_storico;

create policy logistica_asset_assegnatari_storico_write
on public.logistica_asset_assegnatari_storico
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
);
