alter table public.users
  add column if not exists secondary_role text,
  add column if not exists secondary_admin_type integer;

