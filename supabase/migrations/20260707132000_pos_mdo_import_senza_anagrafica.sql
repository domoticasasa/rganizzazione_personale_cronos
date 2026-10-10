-- Import POS MdO anche senza abbinamento anagrafica (es. noleggio).

alter table public.pos_commessa_mdo_ferroviari
  alter column mdo_id drop not null;

alter table public.pos_commessa_mdo_proprieta
  alter column mdo_id drop not null;

create unique index if not exists pos_commessa_mdo_ferroviari_commessa_codifica_import_idx
  on public.pos_commessa_mdo_ferroviari (
    commessa_id,
    lower(trim(coalesce(codifica_import, '')))
  )
  where mdo_id is null
    and coalesce(trim(codifica_import), '') <> '';

create unique index if not exists pos_commessa_mdo_proprieta_commessa_codifica_import_idx
  on public.pos_commessa_mdo_proprieta (
    commessa_id,
    lower(trim(coalesce(codifica_import, '')))
  )
  where mdo_id is null
    and coalesce(trim(codifica_import), '') <> '';

notify pgrst, 'reload schema';
