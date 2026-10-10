-- Coordinate GPS sede/cantiere commessa (mappa logistica).

alter table public.commesse
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

comment on column public.commesse.latitudine is
  'Latitudine WGS84 (es. 45.49805040586989).';
comment on column public.commesse.longitudine is
  'Longitudine WGS84 (es. 9.219329053189183).';

-- Esempio TE-15-24 (se presente in anagrafica).
update public.commesse
set
  latitudine = 45.49805040586989,
  longitudine = 9.219329053189183
where upper(trim(nome)) in ('TE-15-24', 'TE 15 24', 'TE-15 24');
