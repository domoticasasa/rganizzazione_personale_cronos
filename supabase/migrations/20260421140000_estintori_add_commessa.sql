alter table public.estintori
  add column if not exists commessa_id uuid references public.commesse(id_uuid) on delete set null;

create index if not exists estintori_commessa_idx
  on public.estintori(commessa_id);
