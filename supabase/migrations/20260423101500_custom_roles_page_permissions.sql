create table if not exists public.app_custom_roles (
  role_key text primary key,
  label text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_custom_role_pages (
  id bigserial primary key,
  role_key text not null references public.app_custom_roles(role_key) on delete cascade,
  page_key text not null,
  can_view boolean not null default true,
  created_at timestamptz not null default now(),
  unique (role_key, page_key)
);

create or replace function public.set_app_custom_roles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_app_custom_roles_updated_at on public.app_custom_roles;
create trigger trg_app_custom_roles_updated_at
before update on public.app_custom_roles
for each row execute function public.set_app_custom_roles_updated_at();

alter table public.app_custom_roles enable row level security;
alter table public.app_custom_role_pages enable row level security;

drop policy if exists app_custom_roles_select_all_authenticated on public.app_custom_roles;
create policy app_custom_roles_select_all_authenticated
on public.app_custom_roles
for select
to authenticated
using (true);

drop policy if exists app_custom_role_pages_select_all_authenticated on public.app_custom_role_pages;
create policy app_custom_role_pages_select_all_authenticated
on public.app_custom_role_pages
for select
to authenticated
using (true);

drop policy if exists app_custom_roles_manage_admin_generale on public.app_custom_roles;
create policy app_custom_roles_manage_admin_generale
on public.app_custom_roles
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
);

drop policy if exists app_custom_role_pages_manage_admin_generale on public.app_custom_role_pages;
create policy app_custom_role_pages_manage_admin_generale
on public.app_custom_role_pages
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
);
