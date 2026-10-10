-- Collega PDF assegnazione attrezzature all'anagrafica logistica_attrezzature.

alter table public.logistica_assegnazione_attrezzature_documenti
  add column if not exists attrezzatura_id uuid
    references public.logistica_attrezzature (id_uuid) on delete set null;

create index if not exists logistica_assegnazione_attrezzature_doc_att_idx
  on public.logistica_assegnazione_attrezzature_documenti (attrezzatura_id);

comment on column public.logistica_assegnazione_attrezzature_documenti.attrezzatura_id is
  'Attrezzatura selezionata dall''anagrafica (opzionale per PDF legacy).';

notify pgrst, 'reload schema';
