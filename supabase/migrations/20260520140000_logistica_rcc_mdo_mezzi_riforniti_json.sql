-- Ripartizione litri su più mezzi (MDO ferroviari / esterni) per rifornimento MDO.
alter table if exists public.logistica_rcc_mdo_carburante
  add column if not exists mezzi_riforniti_json jsonb;

comment on column public.logistica_rcc_mdo_carburante.mezzi_riforniti_json is
  'Array JSON [{mezzo, litri, mdo_id_uuid?}] — ripartizione gasolio su più mezzi.';
