-- Tipografia e icona personalizzata per tile hub.

alter table public.app_ui_tile_styles
  add column if not exists icon_codepoint integer,
  add column if not exists font_family text,
  add column if not exists title_font_size real
    check (title_font_size is null or (title_font_size >= 10 and title_font_size <= 28));

comment on column public.app_ui_tile_styles.icon_codepoint is
  'Codepoint Material Icons. Null = icona predefinita del pulsante.';
comment on column public.app_ui_tile_styles.font_family is
  'Famiglia font titolo (es. Roboto, Georgia). Null = predefinito.';
comment on column public.app_ui_tile_styles.title_font_size is
  'Dimensione testo titolo in px logici (10–28). Null = deriva da size_scale.';
