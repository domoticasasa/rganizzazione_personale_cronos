-- Programmazione corso RFI: intervallo dal/al (come formazione_corsi.prima_data / seconda_data).

insert into public.formazione_rfi_records (
  personale_id, track_key, field_key, value_date, value_text, source_file, updated_at
)
select
  personale_id,
  track_key,
  'data_programmazione_dal',
  value_date,
  null,
  'migration_dal_al',
  now()
from public.formazione_rfi_records
where field_key = 'data_programmazione_corso'
  and value_date is not null
on conflict (personale_id, track_key, field_key) do update
set
  value_date = excluded.value_date,
  updated_at = now();

insert into public.formazione_rfi_records (
  personale_id, track_key, field_key, value_date, value_text, source_file, updated_at
)
select
  personale_id,
  track_key,
  'data_programmazione_al',
  value_date,
  null,
  'migration_dal_al',
  now()
from public.formazione_rfi_records
where field_key = 'data_programmazione_corso'
  and value_date is not null
on conflict (personale_id, track_key, field_key) do update
set
  value_date = excluded.value_date,
  updated_at = now();

delete from public.formazione_rfi_records
where field_key = 'data_programmazione_corso';
