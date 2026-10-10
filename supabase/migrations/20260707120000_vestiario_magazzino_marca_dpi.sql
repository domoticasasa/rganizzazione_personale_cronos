-- Marca opzionale su inventario (DPI III categoria e altri articoli unitari).

alter table public.vestiario_magazzino
  add column if not exists marca text;

comment on column public.vestiario_magazzino.marca is
  'Marca/modello in magazzino (principalmente DPI III categoria).';
