alter table public.logistica_mdo_ferroviari
  drop column if exists fca_check,
  drop column if exists fca_checked_at,
  drop column if exists fca_checked_by_user_uuid;
