alter table public.estintori
  add column if not exists numero_estintore text,
  add column if not exists anno_produzione text,
  add column if not exists potere_estinguente text;
