alter table public.logistica_mdo_proprieta
  add column if not exists commessa_id uuid references public.commesse(id_uuid) on delete set null,
  add column if not exists posizione_gps text,
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

create index if not exists logistica_mdo_proprieta_commessa_idx
  on public.logistica_mdo_proprieta(commessa_id);

create index if not exists idx_logistica_mdo_proprieta_lat_lon
  on public.logistica_mdo_proprieta(latitudine, longitudine);
