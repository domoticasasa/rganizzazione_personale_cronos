-- Altri documenti MDO: tipo libero con titolo e descrizione.

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
  add column if not exists custom_titolo text,
  add column if not exists custom_descrizione text;

alter table public.logistica_mdo_documenti
  drop constraint if exists logistica_mdo_documenti_doc_tipo_check,
  drop constraint if exists logistica_mdo_documenti_altro_titolo_check;

alter table public.logistica_mdo_documenti
  add constraint logistica_mdo_documenti_doc_tipo_check
    check (doc_tipo in (
      'cdc_allegato_j',
      'libro_bordo_allegato_l',
      'diario_manutenzione_allegato_k',
      'targa_identificativa',
      'certificato_va',
      'controllo_periodico_33m_allegato_k',
      'verifica_quinquennale_allegato_p',
      'mum',
      'inail_terrazzino',
      'inail_gru',
      'altro'
    ));

alter table public.logistica_mdo_documenti
  add constraint logistica_mdo_documenti_altro_titolo_check
    check (
      doc_tipo <> 'altro'
      or length(trim(coalesce(custom_titolo, ''))) > 0
    );

comment on column public.logistica_mdo_documenti.custom_titolo is
  'Nome del documento quando doc_tipo = altro.';
comment on column public.logistica_mdo_documenti.custom_descrizione is
  'Descrizione libera del documento custom.';
