alter table public.logistica_mdo_ferroviari
  add column if not exists check_eseguito boolean not null default false,
  add column if not exists check_confermato_at timestamptz,
  add column if not exists check_confermato_by_user_uuid uuid references public.users(id_uuid) on delete set null;

create index if not exists idx_logistica_mdo_check_confermato_by
  on public.logistica_mdo_ferroviari (check_confermato_by_user_uuid);
