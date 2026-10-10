-- DT deve vedere la stessa griglia formazione dell'admin, ma senza permessi di modifica.
-- Aggiungiamo solo SELECT globale per ruolo dt.

drop policy if exists formazione_corsi_dt_read_all on public.formazione_corsi;
create policy formazione_corsi_dt_read_all
on public.formazione_corsi
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'dt'
  )
);

