-- Sync multicard per numero carta (non solo targa): la carta può spostarsi su altro mezzo.

create or replace function public.logistica_normalize_multicard_key(p_raw text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(trim(coalesce(p_raw, '')), '[.[:space:]]+$', ''), '');
$$;

create or replace function public.logistica_extract_multicard_keys(p_raw text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    array_agg(distinct m[1]),
    '{}'::text[]
  )
  from regexp_matches(coalesce(p_raw, ''), '710[0-9]{12,16}', 'g') as m;
$$;

create or replace function public.trg_logistica_mezzi_sync_multicard_assignee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_targa text := nullif(trim(coalesce(new.targa, '')), '');
  v_key text;
begin
  if v_targa is null then
    return new;
  end if;

  if to_regclass('public.logistica_multicard') is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if coalesce(new.assegnatario_attuale, '') is not distinct from coalesce(old.assegnatario_attuale, '')
       and coalesce(new.assegnatario_user_uuid::text, '') is not distinct from coalesce(old.assegnatario_user_uuid::text, '')
       and new.periodo_assegnatario_attuale is not distinct from old.periodo_assegnatario_attuale
       and new.data_fine_assegnatario_attuale is not distinct from old.data_fine_assegnatario_attuale
       and coalesce(new.multicard, '') is not distinct from coalesce(old.multicard, '') then
      return new;
    end if;
  end if;

  -- Per targa salvata sulla multicard.
  update public.logistica_multicard c
  set
    assegnatario_attuale = new.assegnatario_attuale,
    assegnatario_user_uuid = new.assegnatario_user_uuid,
    periodo_assegnatario_attuale = new.periodo_assegnatario_attuale,
    data_fine_assegnatario_attuale = new.data_fine_assegnatario_attuale,
    mezzo_targa = new.targa,
    updated_at = now()
  where lower(trim(coalesce(c.mezzo_targa, ''))) = lower(v_targa);

  -- Per ogni numero carta citato nel campo multicard del mezzo.
  foreach v_key in array public.logistica_extract_multicard_keys(new.multicard)
  loop
    update public.logistica_multicard c
    set
      assegnatario_attuale = new.assegnatario_attuale,
      assegnatario_user_uuid = new.assegnatario_user_uuid,
      periodo_assegnatario_attuale = new.periodo_assegnatario_attuale,
      data_fine_assegnatario_attuale = new.data_fine_assegnatario_attuale,
      mezzo_targa = new.targa,
      updated_at = now()
    where public.logistica_normalize_multicard_key(c.multicard) = v_key;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_sync_multicard_assignee
  on public.logistica_mezzi_stradali;

create trigger trg_logistica_mezzi_sync_multicard_assignee
after insert or update of
  targa,
  multicard,
  assegnatario_attuale,
  assegnatario_user_uuid,
  periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale
on public.logistica_mezzi_stradali
for each row
execute function public.trg_logistica_mezzi_sync_multicard_assignee();

-- Allineamento: per ogni multicard trova il mezzo che cita quel numero (priorità campo esatto).
with mezzo_card as (
  select
    m.targa,
    m.assegnatario_attuale,
    m.assegnatario_user_uuid,
    m.periodo_assegnatario_attuale,
    m.data_fine_assegnatario_attuale,
    k.card_key,
    case
      when public.logistica_normalize_multicard_key(m.multicard) = k.card_key then 10
      when (public.logistica_extract_multicard_keys(m.multicard))[array_length(public.logistica_extract_multicard_keys(m.multicard), 1)] = k.card_key then 5
      else 1
    end as score
  from public.logistica_mezzi_stradali m
  cross join lateral unnest(public.logistica_extract_multicard_keys(m.multicard)) as k(card_key)
  where nullif(trim(coalesce(m.targa, '')), '') is not null
),
best as (
  select distinct on (card_key)
    card_key,
    targa,
    assegnatario_attuale,
    assegnatario_user_uuid,
    periodo_assegnatario_attuale,
    data_fine_assegnatario_attuale
  from mezzo_card
  order by card_key, score desc, targa
)
update public.logistica_multicard c
set
  assegnatario_attuale = b.assegnatario_attuale,
  assegnatario_user_uuid = b.assegnatario_user_uuid,
  periodo_assegnatario_attuale = b.periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale = b.data_fine_assegnatario_attuale,
  mezzo_targa = b.targa,
  updated_at = now()
from best b
where public.logistica_normalize_multicard_key(c.multicard) = b.card_key
  and (
    coalesce(c.assegnatario_attuale, '') is distinct from coalesce(b.assegnatario_attuale, '')
    or coalesce(c.assegnatario_user_uuid::text, '') is distinct from coalesce(b.assegnatario_user_uuid::text, '')
    or c.periodo_assegnatario_attuale is distinct from b.periodo_assegnatario_attuale
    or c.data_fine_assegnatario_attuale is distinct from b.data_fine_assegnatario_attuale
    or lower(trim(coalesce(c.mezzo_targa, ''))) is distinct from lower(trim(b.targa))
  );
