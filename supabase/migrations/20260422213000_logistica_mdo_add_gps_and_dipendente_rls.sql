alter table public.logistica_mdo_ferroviari
  add column if not exists posizione_gps text,
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

create index if not exists idx_logistica_mdo_lat_lon
  on public.logistica_mdo_ferroviari (latitudine, longitudine);

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
      and lower(coalesce(u.role, '')) = 'dipendente'
  )
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
      and lower(coalesce(u.role, '')) = 'dipendente'
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'dipendente'
  )
);
