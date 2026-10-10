-- Nome/icona/testo tile: dimensione 1–50 px.

do $$
declare
  r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname
    from pg_constraint c
    where c.contype = 'c'
      and (
        pg_get_constraintdef(c.oid) ilike '%title_font_size%'
        or pg_get_constraintdef(c.oid) ilike '%icon_font_size%'
      )
      and c.conrelid::regclass::text in (
        'public.app_ui_tile_styles',
        'app_ui_tile_styles',
        'public.app_ui_user_tile_style',
        'app_ui_user_tile_style',
        'public.app_ui_futuristic_tile_styles',
        'app_ui_futuristic_tile_styles'
      )
  loop
    execute format('alter table %s drop constraint if exists %I', r.tbl, r.conname);
  end loop;
end $$;

alter table public.app_ui_tile_styles
  drop constraint if exists app_ui_tile_styles_title_font_size_check,
  drop constraint if exists app_ui_tile_styles_icon_font_size_check;

alter table public.app_ui_user_tile_style
  drop constraint if exists app_ui_user_tile_style_icon_font_size_check,
  drop constraint if exists app_ui_user_tile_style_title_font_size_check;

alter table public.app_ui_futuristic_tile_styles
  drop constraint if exists app_ui_futuristic_tile_styles_title_font_size_check,
  drop constraint if exists app_ui_futuristic_tile_styles_icon_font_size_check;

alter table public.app_ui_tile_styles
  add constraint app_ui_tile_styles_title_font_size_check
    check (title_font_size is null or (title_font_size >= 1 and title_font_size <= 50)),
  add constraint app_ui_tile_styles_icon_font_size_check
    check (icon_font_size is null or (icon_font_size >= 1 and icon_font_size <= 50));

alter table public.app_ui_user_tile_style
  add constraint app_ui_user_tile_style_title_font_size_check
    check (title_font_size is null or (title_font_size >= 1 and title_font_size <= 50)),
  add constraint app_ui_user_tile_style_icon_font_size_check
    check (icon_font_size is null or (icon_font_size >= 1 and icon_font_size <= 50));

alter table public.app_ui_futuristic_tile_styles
  add constraint app_ui_futuristic_tile_styles_title_font_size_check
    check (title_font_size is null or (title_font_size >= 1 and title_font_size <= 50)),
  add constraint app_ui_futuristic_tile_styles_icon_font_size_check
    check (icon_font_size is null or (icon_font_size >= 1 and icon_font_size <= 50));

comment on column public.app_ui_tile_styles.title_font_size is
  'Dimensione testo titolo in px (1–50). Null = automatica.';
comment on column public.app_ui_tile_styles.icon_font_size is
  'Dimensione icona in px (1–50). Null = automatica.';
