create table if not exists public.app_page_registry (
  page_key text primary key,
  label text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_app_page_registry_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_app_page_registry_updated_at on public.app_page_registry;
create trigger trg_app_page_registry_updated_at
before update on public.app_page_registry
for each row execute function public.set_app_page_registry_updated_at();

alter table public.app_page_registry enable row level security;

drop policy if exists app_page_registry_select_all_authenticated on public.app_page_registry;
create policy app_page_registry_select_all_authenticated
on public.app_page_registry
for select
to authenticated
using (true);

drop policy if exists app_page_registry_manage_admin_generale on public.app_page_registry;
create policy app_page_registry_manage_admin_generale
on public.app_page_registry
for all
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin_generale', 'admin')
  )
);

insert into public.app_page_registry (page_key, label, active)
values
  ('pernottamenti', 'Pernottamenti', true),
  ('treni', 'Treni', true),
  ('aerei', 'Aerei', true),
  ('admin_dashboard', 'Admin Dashboard', true),
  ('anteprima_vista_ruolo', 'Anteprima vista ruolo', true),
  ('richieste_da_approvare', 'Richieste da approvare', true),
  ('formazione_rfi', 'Formazione RFI', true),
  ('logistica', 'Logistica', true),
  ('mdo_ferroviari', 'MDO Ferroviari', true),
  ('formazione_dlgs_81_08', 'Formazione D.Lgs. 81/08', true),
  ('permessi_assistenti_dt', 'Permessi Assistenti DT', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

