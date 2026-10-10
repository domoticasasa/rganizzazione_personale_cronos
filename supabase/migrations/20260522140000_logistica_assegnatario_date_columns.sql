-- Date inizio/fine assegnatario attuale (mezzi e multicard).

alter table public.logistica_mezzi_stradali
  add column if not exists data_fine_assegnatario_attuale date;

comment on column public.logistica_mezzi_stradali.periodo_assegnatario_attuale is
  'Data inizio assegnazione attuale.';
comment on column public.logistica_mezzi_stradali.data_fine_assegnatario_attuale is
  'Data fine assegnazione attuale (opzionale).';

do $$
begin
  if to_regclass('public.logistica_multicard') is not null then
    alter table public.logistica_multicard
      add column if not exists periodo_assegnatario_attuale date,
      add column if not exists data_fine_assegnatario_attuale date;

    comment on column public.logistica_multicard.periodo_assegnatario_attuale is
      'Data inizio assegnazione attuale.';
    comment on column public.logistica_multicard.data_fine_assegnatario_attuale is
      'Data fine assegnazione attuale (opzionale).';
  end if;
end $$;
