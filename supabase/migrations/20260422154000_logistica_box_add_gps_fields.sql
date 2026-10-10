alter table public.logistica_box
  add column if not exists posizione_gps text,
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

create index if not exists idx_logistica_box_lat_lon
  on public.logistica_box (latitudine, longitudine);
