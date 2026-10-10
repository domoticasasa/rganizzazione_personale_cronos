-- Dimensione icona personalizzata per tile hub.

alter table public.app_ui_tile_styles
  add column if not exists icon_font_size real
    check (
      icon_font_size is null
      or (icon_font_size >= 16 and icon_font_size <= 56)
    );

alter table public.app_ui_user_tile_style
  add column if not exists icon_font_size real
    check (
      icon_font_size is null
      or (icon_font_size >= 16 and icon_font_size <= 56)
    );

comment on column public.app_ui_tile_styles.icon_font_size is
  'Dimensione icona tile in px; null = automatica da size_scale.';
comment on column public.app_ui_user_tile_style.icon_font_size is
  'Override dimensione icona (layout personale DT).';
