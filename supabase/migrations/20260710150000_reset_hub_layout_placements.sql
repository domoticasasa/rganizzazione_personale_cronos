-- Reset layout hub dopo il passaggio alla griglia 26×20.
-- Il vecchio layout 10×6 riscalato produceva tile sovradimensionate, sovrapposte
-- e sparse: azzeriamo posizioni e dimensioni salvate così le tile si
-- ridispongono ordinate a misura base su TUTTE le pagine. L'aspetto
-- (colori, etichette, icone) resta invariato.

-- Posizioni salvate (globali e personali DT/Assistente DT).
delete from public.app_ui_tile_grid_placement;
delete from public.app_ui_user_tile_grid_placement;

-- Dimensioni: riporta tutte le tile alla scala base (1.0) e rimuove eventuali
-- posizioni/span residui memorizzati negli stili globali.
update public.app_ui_tile_styles
set
  grid_col = null,
  grid_row = null,
  grid_col_span = null,
  grid_row_span = null,
  size_scale = 1.0
where grid_col is not null
   or grid_row is not null
   or grid_col_span is not null
   or grid_row_span is not null
   or size_scale is distinct from 1.0;

-- Dimensioni personali (DT / Assistente DT).
update public.app_ui_user_tile_style
set size_scale = 1.0
where size_scale is distinct from 1.0;

notify pgrst, 'reload schema';
