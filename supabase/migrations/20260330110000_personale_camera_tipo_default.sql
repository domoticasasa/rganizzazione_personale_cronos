alter table public.personale
add column if not exists camera_tipo_default text not null default 'singola';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'personale_camera_tipo_default_check'
  ) then
    alter table public.personale
    add constraint personale_camera_tipo_default_check
    check (camera_tipo_default in ('singola', 'doppia'));
  end if;
end $$;
