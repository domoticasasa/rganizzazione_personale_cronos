-- Check contenuto casette P.S. + N. LOTO (DM 388/2003 Allegato 1 / 2).

alter table public.logistica_casette_ps
  add column if not exists n_loto text,
  add column if not exists materiale_contenuto jsonb not null default '[]'::jsonb,
  add column if not exists data_ultimo_check_materiale timestamptz;

comment on column public.logistica_casette_ps.n_loto is
  'Numero lotto della casetta / contenuto principale.';
comment on column public.logistica_casette_ps.materiale_contenuto is
  'Array JSON: [{id, descrizione, presente, scadenza}, ...] — check Allegato 1/2.';
comment on column public.logistica_casette_ps.data_ultimo_check_materiale is
  'Data/ora ultimo salvataggio check contenuto materiale.';
