alter table public.logistica_mezzi_stradali
  add column if not exists assegnatario_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists note text;

create index if not exists logistica_mezzi_stradali_assegnatario_user_uuid_idx
  on public.logistica_mezzi_stradali(assegnatario_user_uuid);
