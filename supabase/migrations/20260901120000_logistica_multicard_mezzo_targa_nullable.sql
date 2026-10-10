-- Gestione Multicard: "Nessuna assegnazione" non deve violare NOT NULL.
alter table if exists public.logistica_multicard
  alter column mezzo_targa drop not null;

update public.logistica_multicard
set mezzo_targa = coalesce(nullif(trim(mezzo_targa), ''), '')
where mezzo_targa is null;
