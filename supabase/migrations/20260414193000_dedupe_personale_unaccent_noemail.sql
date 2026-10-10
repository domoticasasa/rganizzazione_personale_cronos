create extension if not exists unaccent;

with normalized as (
  select
    p.id,
    p.id_uuid,
    p.full_name,
    p.user_id,
    p.email,
    (
      select string_agg(tok, ' ' order by tok)
      from unnest(
        regexp_split_to_array(
          regexp_replace(
            lower(
              unaccent(
                replace(
                  replace(
                    replace(coalesce(p.full_name, ''), '’', ''''),
                    '´',
                    ''''
                  ),
                  '`',
                  ''''
                )
              )
            ),
            '[^a-z0-9 ]+',
            ' ',
            'g'
          ),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
keepers as (
  select distinct on (n.token_key)
    n.token_key,
    n.id as keep_id,
    n.id_uuid as keep_uuid
  from normalized n
  where coalesce(n.token_key, '') <> ''
  order by
    n.token_key,
    (n.user_id is not null) desc,
    (coalesce(n.email, '') <> '') desc,
    n.id asc
),
losers as (
  select
    n.id as lose_id,
    n.id_uuid as lose_uuid,
    k.keep_uuid
  from normalized n
  join keepers k on k.token_key = n.token_key
  where n.id <> k.keep_id
    and n.user_id is null
    and coalesce(n.email, '') = ''
)
insert into public.formazione_corsi (
  personale_id, anno, data, oda, ente, corso, primo_rilascio_aggiornamento, attestato,
  data_attestato, scadenza_attestato, corso_prenotato, prima_data, seconda_data, orario, modalita, dimessi, note
)
select
  l.keep_uuid, fc.anno, fc.data, fc.oda, fc.ente, fc.corso, fc.primo_rilascio_aggiornamento, fc.attestato,
  fc.data_attestato, fc.scadenza_attestato, fc.corso_prenotato, fc.prima_data, fc.seconda_data, fc.orario, fc.modalita, fc.dimessi, fc.note
from public.formazione_corsi fc
join losers l on l.lose_uuid = fc.personale_id
on conflict (personale_id, corso, data_attestato) do update set
  ente = coalesce(excluded.ente, public.formazione_corsi.ente),
  attestato = coalesce(excluded.attestato, public.formazione_corsi.attestato),
  scadenza_attestato = coalesce(excluded.scadenza_attestato, public.formazione_corsi.scadenza_attestato),
  note = coalesce(excluded.note, public.formazione_corsi.note),
  updated_at = now();

with normalized as (
  select
    p.id,
    p.id_uuid,
    (
      select string_agg(tok, ' ' order by tok)
      from unnest(
        regexp_split_to_array(
          regexp_replace(
            lower(
              unaccent(
                replace(
                  replace(
                    replace(coalesce(p.full_name, ''), '’', ''''),
                    '´',
                    ''''
                  ),
                  '`',
                  ''''
                )
              )
            ),
            '[^a-z0-9 ]+',
            ' ',
            'g'
          ),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
keepers as (
  select distinct on (n.token_key)
    n.token_key,
    n.id as keep_id
  from normalized n
  join public.personale p on p.id = n.id
  where coalesce(n.token_key, '') <> ''
  order by
    n.token_key,
    (p.user_id is not null) desc,
    (coalesce(p.email, '') <> '') desc,
    p.id asc
),
losers as (
  select p.id, p.id_uuid
  from normalized n
  join public.personale p on p.id = n.id
  join keepers k on k.token_key = n.token_key
  where p.id <> k.keep_id
    and p.user_id is null
    and coalesce(p.email, '') = ''
)
delete from public.formazione_corsi fc
using losers l
where fc.personale_id = l.id_uuid;

with normalized as (
  select
    p.id,
    (
      select string_agg(tok, ' ' order by tok)
      from unnest(
        regexp_split_to_array(
          regexp_replace(
            lower(
              unaccent(
                replace(
                  replace(
                    replace(coalesce(p.full_name, ''), '’', ''''),
                    '´',
                    ''''
                  ),
                  '`',
                  ''''
                )
              )
            ),
            '[^a-z0-9 ]+',
            ' ',
            'g'
          ),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
keepers as (
  select distinct on (n.token_key)
    n.token_key,
    n.id as keep_id
  from normalized n
  join public.personale p on p.id = n.id
  where coalesce(n.token_key, '') <> ''
  order by
    n.token_key,
    (p.user_id is not null) desc,
    (coalesce(p.email, '') <> '') desc,
    p.id asc
),
losers as (
  select p.id
  from normalized n
  join public.personale p on p.id = n.id
  join keepers k on k.token_key = n.token_key
  where p.id <> k.keep_id
    and p.user_id is null
    and coalesce(p.email, '') = ''
)
delete from public.personale p
using losers l
where p.id = l.id;

