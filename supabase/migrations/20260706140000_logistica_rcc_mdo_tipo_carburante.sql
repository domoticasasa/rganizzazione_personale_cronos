alter table if exists public.logistica_rcc_mdo_carburante
  add column if not exists tipo_carburante text;

comment on column public.logistica_rcc_mdo_carburante.tipo_carburante is
  'Tipo carburante: Gasolio, Benzina o AdBlue.';
