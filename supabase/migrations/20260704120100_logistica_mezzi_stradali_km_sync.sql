-- Km attuali su mezzo stradale, sincronizzati dal registro Mod.RCC (km_ore).
alter table public.logistica_mezzi_stradali
  add column if not exists km_attuali bigint,
  add column if not exists km_aggiornato_il timestamptz;

create index if not exists logistica_mezzi_stradali_km_aggiornato_il_idx
  on public.logistica_mezzi_stradali (km_aggiornato_il desc nulls last);

-- Backfill dall'ultimo rifornimento RCC con km per ogni mezzo.
with ranked as (
  select
    r.mezzo_stradale_id_uuid,
    r.km_ore,
    coalesce(
      nullif(r.field_timestamps -> 'km_ore' ->> 'at', '')::timestamptz,
      r.updated_at,
      r.created_at
    ) as agg_at,
    row_number() over (
      partition by r.mezzo_stradale_id_uuid
      order by r.data_rifornimento desc,
        coalesce(r.updated_at, r.created_at) desc nulls last
    ) as rn
  from public.logistica_rcc_carburante r
  where r.mezzo_stradale_id_uuid is not null
    and nullif(trim(r.km_ore), '') is not null
),
latest as (
  select mezzo_stradale_id_uuid, km_ore, agg_at
  from ranked
  where rn = 1
)
update public.logistica_mezzi_stradali m
set
  km_attuali = nullif(regexp_replace(l.km_ore, '[^0-9]', '', 'g'), '')::bigint,
  km_aggiornato_il = l.agg_at
from latest l
where m.id_uuid = l.mezzo_stradale_id_uuid
  and nullif(regexp_replace(l.km_ore, '[^0-9]', '', 'g'), '') is not null;
