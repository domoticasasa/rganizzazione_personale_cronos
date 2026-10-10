alter table public.estintori
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

create index if not exists estintori_lat_lon_idx
  on public.estintori(latitudine, longitudine);
