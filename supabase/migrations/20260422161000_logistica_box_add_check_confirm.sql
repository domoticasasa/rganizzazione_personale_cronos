alter table public.logistica_box
  add column if not exists check_eseguito boolean not null default false,
  add column if not exists check_confermato_at timestamptz,
  add column if not exists check_confermato_by_uuid uuid;
