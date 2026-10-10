-- Rifornimento MDO completato (manca da rifornire = 0): dipendente non può più modificare.
alter table if exists public.logistica_rcc_mdo_carburante
  add column if not exists rifornimento_completo boolean not null default false;

comment on column public.logistica_rcc_mdo_carburante.rifornimento_completo is
  'True se litri totali = somma mezzi riforniti; blocca modifica per dipendente.';
