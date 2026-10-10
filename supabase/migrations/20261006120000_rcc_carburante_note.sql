alter table public.logistica_rcc_carburante
  add column if not exists note text;

comment on column public.logistica_rcc_carburante.note is
  'Nota libera sul rifornimento (opzionale).';
