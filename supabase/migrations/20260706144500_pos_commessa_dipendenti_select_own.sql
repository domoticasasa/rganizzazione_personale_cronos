-- Il dipendente può leggere le proprie assegnazioni POS (commesse di lavoro).

drop policy if exists pos_commessa_dipendenti_select_own on public.pos_commessa_dipendenti;
create policy pos_commessa_dipendenti_select_own
on public.pos_commessa_dipendenti
for select
to authenticated
using (
  personale_id in (
    select p.id_uuid
    from public.personale p
    where public.personale_belongs_to_current_auth(p)
  )
);
