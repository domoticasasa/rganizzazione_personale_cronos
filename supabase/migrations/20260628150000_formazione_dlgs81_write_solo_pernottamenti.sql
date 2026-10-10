-- Formazione D.Lgs. 81/08: scrittura solo admin_pernottamenti (non admin_generale).

drop policy if exists formazione_corsi_admin_write on public.formazione_corsi;
create policy formazione_corsi_admin_write
on public.formazione_corsi
for all
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'admin_pernottamenti'
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'admin_pernottamenti'
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
      and lower(coalesce(u.role, '')) = 'admin_pernottamenti'
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'admin_pernottamenti'
  )
);
