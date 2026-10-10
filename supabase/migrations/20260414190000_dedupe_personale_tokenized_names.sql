-- Deduplica personale su nomi equivalenti (anche ordine invertito).
-- Mantiene il record "migliore" (con user_id/email/attivo), migra formazione_corsi e poi elimina i duplicati.

with normalized as (
  select
    p.id,
    p.id_uuid,
    p.full_name,
    p.user_id,
    p.email,
    p.active,
    (
      select string_agg(tok, ' ' order by tok)
      from unnest(
        regexp_split_to_array(
          regexp_replace(lower(coalesce(p.full_name, '')), '[^a-z0-9 ]+', ' ', 'g'),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
ranked as (
  select
    n.*,
    row_number() over (
      partition by n.token_key
      order by
        (n.user_id is not null) desc,
        (coalesce(n.email, '') <> '') desc,
        coalesce(n.active, true) desc,
        n.id asc
    ) as rn
  from normalized n
  where coalesce(n.token_key, '') <> ''
),
keepers as (
  select * from ranked where rn = 1
),
losers as (
  select * from ranked where rn > 1
),
map as (
  select
    l.id as old_id,
    l.id_uuid as old_uuid,
    k.id as new_id,
    k.id_uuid as new_uuid
  from losers l
  join keepers k on k.token_key = l.token_key
)
insert into public.formazione_corsi (
  personale_id,
  anno,
  data,
  oda,
  ente,
  corso,
  primo_rilascio_aggiornamento,
  attestato,
  data_attestato,
  scadenza_attestato,
  corso_prenotato,
  prima_data,
  seconda_data,
  orario,
  modalita,
  dimessi,
  note
)
select
  m.new_uuid,
  fc.anno,
  fc.data,
  fc.oda,
  fc.ente,
  fc.corso,
  fc.primo_rilascio_aggiornamento,
  fc.attestato,
  fc.data_attestato,
  fc.scadenza_attestato,
  fc.corso_prenotato,
  fc.prima_data,
  fc.seconda_data,
  fc.orario,
  fc.modalita,
  fc.dimessi,
  fc.note
from public.formazione_corsi fc
join map m on m.old_uuid = fc.personale_id
on conflict (personale_id, corso, data_attestato) do update set
  anno = coalesce(excluded.anno, public.formazione_corsi.anno),
  data = coalesce(excluded.data, public.formazione_corsi.data),
  oda = coalesce(excluded.oda, public.formazione_corsi.oda),
  ente = coalesce(excluded.ente, public.formazione_corsi.ente),
  primo_rilascio_aggiornamento = coalesce(
    excluded.primo_rilascio_aggiornamento,
    public.formazione_corsi.primo_rilascio_aggiornamento
  ),
  attestato = coalesce(excluded.attestato, public.formazione_corsi.attestato),
  scadenza_attestato = coalesce(excluded.scadenza_attestato, public.formazione_corsi.scadenza_attestato),
  corso_prenotato = coalesce(excluded.corso_prenotato, public.formazione_corsi.corso_prenotato),
  prima_data = coalesce(excluded.prima_data, public.formazione_corsi.prima_data),
  seconda_data = coalesce(excluded.seconda_data, public.formazione_corsi.seconda_data),
  orario = coalesce(excluded.orario, public.formazione_corsi.orario),
  modalita = coalesce(excluded.modalita, public.formazione_corsi.modalita),
  dimessi = coalesce(excluded.dimessi, public.formazione_corsi.dimessi),
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
          regexp_replace(lower(coalesce(p.full_name, '')), '[^a-z0-9 ]+', ' ', 'g'),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
ranked as (
  select
    n.*,
    row_number() over (
      partition by n.token_key
      order by
        (p.user_id is not null) desc,
        (coalesce(p.email, '') <> '') desc,
        coalesce(p.active, true) desc,
        p.id asc
    ) as rn
  from normalized n
  join public.personale p on p.id = n.id
  where coalesce(n.token_key, '') <> ''
),
to_delete as (
  select p.id_uuid
  from ranked r
  join public.personale p on p.id = r.id
  where r.rn > 1
)
delete from public.formazione_corsi fc
using to_delete d
where fc.personale_id = d.id_uuid;

with normalized as (
  select
    p.id,
    (
      select string_agg(tok, ' ' order by tok)
      from unnest(
        regexp_split_to_array(
          regexp_replace(lower(coalesce(p.full_name, '')), '[^a-z0-9 ]+', ' ', 'g'),
          '\s+'
        )
      ) as tok
      where tok <> ''
    ) as token_key
  from public.personale p
),
ranked as (
  select
    n.id,
    row_number() over (
      partition by n.token_key
      order by
        (p.user_id is not null) desc,
        (coalesce(p.email, '') <> '') desc,
        coalesce(p.active, true) desc,
        p.id asc
    ) as rn
  from normalized n
  join public.personale p on p.id = n.id
  where coalesce(n.token_key, '') <> ''
)
delete from public.personale p
using ranked r
where p.id = r.id
  and r.rn > 1;

