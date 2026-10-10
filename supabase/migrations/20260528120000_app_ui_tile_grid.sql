-- Griglia hub 8×4: posizione e dimensione in celle.



alter table public.app_ui_tile_styles

  add column if not exists grid_col smallint

    check (grid_col is null or (grid_col >= 0 and grid_col < 8)),

  add column if not exists grid_row smallint

    check (grid_row is null or (grid_row >= 0 and grid_row < 4)),

  add column if not exists grid_col_span smallint

    check (grid_col_span is null or (grid_col_span >= 1 and grid_col_span <= 8)),

  add column if not exists grid_row_span smallint

    check (grid_row_span is null or (grid_row_span >= 1 and grid_row_span <= 4));



comment on column public.app_ui_tile_styles.grid_col is

  'Colonna griglia 8×4 (0–7). Null = posizione automatica.';

comment on column public.app_ui_tile_styles.grid_row is

  'Riga griglia 8×4 (0–3). Null = posizione automatica.';

comment on column public.app_ui_tile_styles.grid_col_span is

  'Celle orizzontali occupate (1–8). Deriva da size_scale se null.';

comment on column public.app_ui_tile_styles.grid_row_span is

  'Celle verticali occupate (1–4). Deriva da size_scale se null.';



-- Migra pos_x/pos_y legacy (0–1) in celle griglia.

update public.app_ui_tile_styles

set

  grid_col = least(7, greatest(0, round(pos_x * 7)::int)),

  grid_row = least(3, greatest(0, round(pos_y * 3)::int))

where grid_col is null

  and grid_row is null

  and pos_x is not null

  and pos_y is not null;


