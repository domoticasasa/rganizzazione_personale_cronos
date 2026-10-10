-- Stili tile dedicati alla dashboard admin in modalità futuristica (separati dalla vista classica).

create table if not exists public.app_ui_futuristic_tile_styles (
  item_key text primary key,
  custom_label text,
  custom_subtitle text,
  background_color text,
  text_color text,
  icon_color text,
  size_scale real not null default 1.0
    check (size_scale >= 0.6 and size_scale <= 2.0),
  icon_codepoint integer,
  font_family text,
  title_font_size real
    check (
      title_font_size is null
      or (title_font_size >= 10 and title_font_size <= 28)
    ),
  icon_font_size real
    check (
      icon_font_size is null
      or (icon_font_size >= 16 and icon_font_size <= 56)
    ),
  updated_at timestamptz not null default now()
);

comment on table public.app_ui_futuristic_tile_styles is
  'Aspetto tile hub per dashboard admin futuristica (indipendente da app_ui_tile_styles).';

grant select on public.app_ui_futuristic_tile_styles to authenticated;
grant insert, update, delete on public.app_ui_futuristic_tile_styles to authenticated;

alter table public.app_ui_futuristic_tile_styles enable row level security;

drop policy if exists app_ui_futuristic_tile_styles_select on public.app_ui_futuristic_tile_styles;
create policy app_ui_futuristic_tile_styles_select
on public.app_ui_futuristic_tile_styles
for select
to authenticated
using (true);

drop policy if exists app_ui_futuristic_tile_styles_write on public.app_ui_futuristic_tile_styles;
create policy app_ui_futuristic_tile_styles_write
on public.app_ui_futuristic_tile_styles
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());
