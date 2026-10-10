alter table public.formazione_corsi
  drop column if exists attestato,
  drop column if exists corso_prenotato,
  drop column if exists seconda_data;

