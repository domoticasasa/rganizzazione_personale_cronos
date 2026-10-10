-- Sottotitolo / descrizione personalizzabile sui pulsanti hub.

alter table public.app_ui_tile_styles
  add column if not exists custom_subtitle text;

comment on column public.app_ui_tile_styles.custom_subtitle is
  'Testo descrittivo sotto il titolo del tile (override rispetto al default app).';

alter table public.app_ui_user_tile_style
  add column if not exists custom_subtitle text;

comment on column public.app_ui_user_tile_style.custom_subtitle is
  'Sottotitolo tile personale (DT / Assistente DT).';
