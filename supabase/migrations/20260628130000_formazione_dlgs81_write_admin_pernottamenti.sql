-- Scrittura griglia formazione_corsi (D.Lgs. 81/08) e anagrafica strutture: solo admin_generale e admin_pernottamenti.
-- DT / assistente_dt: solo aggiornamento programmazione (non griglia attestati).

drop policy if exists formazione_corsi_admin_write on public.formazione_corsi;
create policy formazione_corsi_admin_write
on public.formazione_corsi
for all
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti')
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti')
  )
);

drop policy if exists formazione_corsi_custom_role_write on public.formazione_corsi;

drop policy if exists formazione_corsi_dt_programmazione_update on public.formazione_corsi;
create policy formazione_corsi_dt_programmazione_update
on public.formazione_corsi
for update
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('dt', 'assistente_dt')
  )
);

drop policy if exists formazione_dlgs_strutture_write on public.formazione_dlgs_strutture;
create policy formazione_dlgs_strutture_write
on public.formazione_dlgs_strutture
for all
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti')
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti')
  )
);
