-- Tipo attività personale (LFM, IS, TE, OP. CIVILI, …) in Dislocazione Personale.
alter table public.dislocazione_personale
  add column if not exists attivita text;
