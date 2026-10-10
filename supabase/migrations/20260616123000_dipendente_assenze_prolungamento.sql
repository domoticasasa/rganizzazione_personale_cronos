-- Aggiunge la data di prolungamento delle assenze.

alter table if exists public.dipendente_assenze
  add column if not exists prolungato_fino_al date;

alter table if exists public.dipendente_assenze
  drop constraint if exists dipendente_assenze_prolungato_range_check;

alter table if exists public.dipendente_assenze
  add constraint dipendente_assenze_prolungato_range_check
  check (
    prolungato_fino_al is null
    or prolungato_fino_al >= data_al
  );
