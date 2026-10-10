-- Campi referenti / luoghi / modalità su trasferimenti MDO.

alter table public.logistica_mdo_trasferimenti
  add column if not exists referente_carico_personale_uuid uuid
    references public.personale (id_uuid) on delete set null,
  add column if not exists referente_carico_nome text,
  add column if not exists referente_carico_telefono text,
  add column if not exists referente_scarico_personale_uuid uuid
    references public.personale (id_uuid) on delete set null,
  add column if not exists referente_scarico_nome text,
  add column if not exists referente_scarico_telefono text,
  add column if not exists luogo_carico text,
  add column if not exists luogo_scarico text,
  add column if not exists modalita_carico text
    check (modalita_carico is null or modalita_carico in ('piano_a_raso', 'gru')),
  add column if not exists modalita_scarico text
    check (modalita_scarico is null or modalita_scarico in ('piano_a_raso', 'gru'));

comment on column public.logistica_mdo_trasferimenti.modalita_carico is
  'piano_a_raso | gru';
comment on column public.logistica_mdo_trasferimenti.modalita_scarico is
  'piano_a_raso | gru';
