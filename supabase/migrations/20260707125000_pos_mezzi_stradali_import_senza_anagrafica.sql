-- Import POS mezzi stradali anche senza abbinamento anagrafica (solo dati file).

alter table public.pos_commessa_mezzi_stradali
  alter column mezzo_id drop not null;

create unique index if not exists pos_commessa_mezzi_stradali_commessa_targa_import_idx
  on public.pos_commessa_mezzi_stradali (
    commessa_id,
    lower(trim(coalesce(targa_import, '')))
  )
  where mezzo_id is null
    and coalesce(trim(targa_import), '') <> '';

notify pgrst, 'reload schema';
