-- Aspetto personalizzato dei pulsanti hub (nome, colori, dimensione).

create table if not exists public.app_ui_tile_styles (
  item_key text primary key,
  custom_label text,
  background_color text,
  text_color text,
  icon_color text,
  size_scale real not null default 1.0
    check (size_scale >= 0.5 and size_scale <= 2.0),
  updated_at timestamptz not null default now()
);

comment on table public.app_ui_tile_styles is
  'Stile globale per tile/pulsanti hub (condiviso tra tutte le pagine).';

grant select on public.app_ui_tile_styles to authenticated;
grant insert, update, delete on public.app_ui_tile_styles to authenticated;

alter table public.app_ui_tile_styles enable row level security;

drop policy if exists app_ui_tile_styles_select on public.app_ui_tile_styles;
create policy app_ui_tile_styles_select
on public.app_ui_tile_styles
for select
to authenticated
using (true);

drop policy if exists app_ui_tile_styles_write on public.app_ui_tile_styles;
create policy app_ui_tile_styles_write
on public.app_ui_tile_styles
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());
