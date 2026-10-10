-- Posizione libera tile hub (coordinate normalizzate 0–1 sul canvas).

alter table public.app_ui_tile_styles
  add column if not exists pos_x real
    check (pos_x is null or (pos_x >= 0 and pos_x <= 1)),
  add column if not exists pos_y real
    check (pos_y is null or (pos_y >= 0 and pos_y <= 1));

comment on column public.app_ui_tile_styles.pos_x is
  'Posizione orizzontale normalizzata (0=sinistra, 1=destra). Null = griglia automatica.';
comment on column public.app_ui_tile_styles.pos_y is
  'Posizione verticale normalizzata (0=alto, 1=basso). Null = griglia automatica.';
