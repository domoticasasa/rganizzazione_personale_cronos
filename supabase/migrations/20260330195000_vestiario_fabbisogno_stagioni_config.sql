alter table public.vestiario_fabbisogno_annuo_config
add column if not exists tshirt_estivo integer not null default 1 check (tshirt_estivo > 0),
add column if not exists pantalone_estivo integer not null default 1 check (pantalone_estivo > 0),
add column if not exists scarpe_estivo integer not null default 1 check (scarpe_estivo > 0),
add column if not exists felpa_invernale integer not null default 1 check (felpa_invernale > 0),
add column if not exists giacca_invernale integer not null default 1 check (giacca_invernale > 0),
add column if not exists gilet_invernale integer not null default 1 check (gilet_invernale > 0),
add column if not exists guanti_invernale integer not null default 1 check (guanti_invernale > 0),
add column if not exists pantalone_invernale integer not null default 1 check (pantalone_invernale > 0),
add column if not exists scarpe_invernale integer not null default 1 check (scarpe_invernale > 0);

update public.vestiario_fabbisogno_annuo_config
set
  tshirt_estivo = coalesce(tshirt_estivo, tshirt, 1),
  pantalone_estivo = coalesce(pantalone_estivo, pantalone, 1),
  scarpe_estivo = coalesce(scarpe_estivo, scarpe, 1),
  felpa_invernale = coalesce(felpa_invernale, felpa, 1),
  giacca_invernale = coalesce(giacca_invernale, giacca, 1),
  gilet_invernale = coalesce(gilet_invernale, gilet, 1),
  guanti_invernale = coalesce(guanti_invernale, guanti, 1),
  pantalone_invernale = coalesce(pantalone_invernale, pantalone, 1),
  scarpe_invernale = coalesce(scarpe_invernale, scarpe, 1)
where id = 1;
