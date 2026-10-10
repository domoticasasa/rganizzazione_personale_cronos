-- Pagine hub personalizzate create dagli admin (tile spostabili).

create table if not exists public.app_ui_custom_hubs (
  layout_key text primary key,
  label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.app_ui_custom_hubs is
  'Etichette pagine hub custom (layout_key = custom_* in app_ui_layout_order).';

grant select on public.app_ui_custom_hubs to authenticated;
grant insert, update, delete on public.app_ui_custom_hubs to authenticated;

alter table public.app_ui_custom_hubs enable row level security;

drop policy if exists app_ui_custom_hubs_select on public.app_ui_custom_hubs;
create policy app_ui_custom_hubs_select
on public.app_ui_custom_hubs
for select
to authenticated
using (true);

drop policy if exists app_ui_custom_hubs_write on public.app_ui_custom_hubs;
create policy app_ui_custom_hubs_write
on public.app_ui_custom_hubs
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());
