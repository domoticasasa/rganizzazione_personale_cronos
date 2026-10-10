-- Documenti MDO: rimuove "Controllo Periodico 33m (Allegato K)";
-- "Verifica Quinquennale" resta come tipo verifica_quinquennale_allegato_p (label app: Allegato P).

-- Eventuali file già caricati come controllo periodico → Altro (non si perdono).
update public.logistica_mdo_documenti
set
  doc_tipo = 'altro',
  custom_titolo = coalesce(
    nullif(trim(custom_titolo), ''),
    'Controllo Periodico 33m (Allegato K)'
  )
where doc_tipo = 'controllo_periodico_33m_allegato_k';

do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.logistica_mdo_documenti'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%doc_tipo%'
  loop
    execute format(
      'alter table public.logistica_mdo_documenti drop constraint if exists %I',
      r.conname
    );
  end loop;
end $$;

alter table public.logistica_mdo_documenti
  drop constraint if exists logistica_mdo_documenti_doc_tipo_check;

alter table public.logistica_mdo_documenti
  add constraint logistica_mdo_documenti_doc_tipo_check
    check (doc_tipo in (
      'cdc_allegato_j',
      'libro_bordo_allegato_l',
      'diario_manutenzione_allegato_k',
      'targa_identificativa',
      'certificato_va',
      'verifica_quinquennale_allegato_p',
      'mum',
      'inail_terrazzino',
      'inail_gru',
      'altro'
    ));
