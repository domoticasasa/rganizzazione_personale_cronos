-- Colonne mancanti per quantità/anno estivo e invernale (sincronizzazione con pagina Fabbisogno taglie).

alter table public.vestiario_fabbisogno_annuo_config
add column if not exists felpa_estivo integer not null default 1,
add column if not exists giacca_estivo integer not null default 1,
add column if not exists gilet_estivo integer not null default 1,
add column if not exists tshirt_invernale integer not null default 1;

update public.vestiario_fabbisogno_annuo_config
set
  felpa_estivo = coalesce(felpa_estivo, felpa, 1),
  giacca_estivo = coalesce(giacca_estivo, giacca, 1),
  gilet_estivo = coalesce(gilet_estivo, gilet, 1),
  tshirt_invernale = coalesce(tshirt_invernale, tshirt, 1)
where id = 1;
