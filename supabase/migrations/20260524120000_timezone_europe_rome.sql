-- Fuso orario ufficiale progetto: Europe/Rome (ora italiana, con DST).
-- I campi timestamptz restano istanti UTC in DB; la formattazione usa timezone Italia.

create or replace function public.fmt_timestamp_italy(ts timestamptz)
returns text
language sql
stable
set search_path = public
as $$
  select to_char(timezone('Europe/Rome', ts), 'DD/MM/YYYY HH24:MI');
$$;

comment on function public.fmt_timestamp_italy(timestamptz) is
  'Formatta un timestamptz in dd/MM/yyyy HH:mm (fuso Europe/Rome).';

create or replace function public.app_now_italy()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select timezone('Europe/Rome', now());
$$;

comment on function public.app_now_italy() is
  'Istante corrente espresso nel fuso Europe/Rome (per log/report SQL).';
