-- Colonna mancante su remoto (dt/mezzo già presenti): collegamento commessa al rifornimento RCC.

alter table public.logistica_rcc_carburante
  add column if not exists commessa_uuid uuid references public.commesse (id_uuid) on delete set null;

create index if not exists logistica_rcc_carburante_commessa_uuid_idx
  on public.logistica_rcc_carburante (commessa_uuid);
