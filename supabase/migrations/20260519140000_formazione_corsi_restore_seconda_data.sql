-- Ripristina intervallo programmazione (dal / al) sui corsi D.Lgs.
alter table public.formazione_corsi
  add column if not exists seconda_data date;

comment on column public.formazione_corsi.seconda_data is
  'Data fine programmazione corso; se nulla coincide con prima_data.';
