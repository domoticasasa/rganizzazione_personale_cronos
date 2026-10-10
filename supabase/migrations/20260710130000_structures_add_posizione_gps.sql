-- Coordinate GPS manuali per le strutture (priorità sul maps_link).

alter table public.structures
  add column if not exists posizione_gps text;

comment on column public.structures.posizione_gps is
  'Coordinate GPS manuali in formato "lat, lon". Se valorizzate hanno '
  'priorità sul maps_link per la posizione sulla mappa.';

notify pgrst, 'reload schema';
