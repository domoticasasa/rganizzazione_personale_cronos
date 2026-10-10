-- Attrezzature: tarature opzionali al posto di STATO/VALORE in UI.
alter table public.logistica_attrezzature
  add column if not exists data_ultima_taratura date,
  add column if not exists data_prossima_taratura date;

comment on column public.logistica_attrezzature.data_ultima_taratura is
  'Data ultima taratura (opzionale).';
comment on column public.logistica_attrezzature.data_prossima_taratura is
  'Data prossima taratura (opzionale).';
