-- Registro RCC gasolio: DT e collegamento al mezzo stradale.
alter table public.logistica_rcc_carburante
  add column if not exists dt_user_uuid uuid references public.users (id_uuid) on delete set null,
  add column if not exists mezzo_stradale_id_uuid uuid references public.logistica_mezzi_stradali (id_uuid) on delete set null,
  add column if not exists commessa_uuid uuid references public.commesse (id_uuid) on delete set null;

create index if not exists logistica_rcc_carburante_dt_user_uuid_idx
  on public.logistica_rcc_carburante (dt_user_uuid);

create index if not exists logistica_rcc_carburante_mezzo_stradale_id_uuid_idx
  on public.logistica_rcc_carburante (mezzo_stradale_id_uuid);
