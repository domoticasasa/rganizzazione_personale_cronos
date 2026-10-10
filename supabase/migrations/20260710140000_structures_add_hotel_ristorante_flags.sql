-- Flag tipologia struttura: HOTEL e/o RISTORANTE.

alter table public.structures
  add column if not exists is_hotel boolean not null default false,
  add column if not exists is_ristorante boolean not null default false;

comment on column public.structures.is_hotel is
  'La struttura offre il servizio HOTEL/pernottamento.';
comment on column public.structures.is_ristorante is
  'La struttura offre il servizio RISTORANTE/pasti.';

notify pgrst, 'reload schema';
