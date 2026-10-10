-- Griglia hub: da 10×6 a 26×20 (celle piccole -> pulsanti di misure diverse).
-- Le posizioni salvate vengono riscalate in modo proporzionale per
-- mantenere l'aspetto del layout sulla griglia più fine.

create or replace function public._drop_grid_check_constraints(p_table regclass)
returns void
language plpgsql
as $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid = p_table
      and c.contype = 'c'
      and c.conname like '%grid\_%'
  loop
    execute format('alter table %s drop constraint %I', p_table, r.conname);
  end loop;
end;
$$;

select public._drop_grid_check_constraints('public.app_ui_tile_styles'::regclass);
select public._drop_grid_check_constraints('public.app_ui_tile_grid_placement'::regclass);
select public._drop_grid_check_constraints('public.app_ui_user_tile_grid_placement'::regclass);

-- Riscala le posizioni globali esistenti (10×6 -> 26×20) con clamp valido.
update public.app_ui_tile_grid_placement p
set
  grid_col_span = s.ncs,
  grid_row_span = s.nrs,
  grid_col = least(greatest(s.col_scaled, 0), 26 - s.ncs),
  grid_row = least(greatest(s.row_scaled, 0), 20 - s.nrs)
from (
  select
    layout_key,
    item_key,
    greatest(1, least(26, round(grid_col_span * 2.6)::int)) as ncs,
    greatest(1, least(20, round(grid_row_span * 3.3)::int)) as nrs,
    round(grid_col * 2.6)::int as col_scaled,
    round(grid_row * 3.3)::int as row_scaled
  from public.app_ui_tile_grid_placement
) s
where p.layout_key = s.layout_key
  and p.item_key = s.item_key;

-- Riscala le posizioni personali (DT / Assistente DT).
update public.app_ui_user_tile_grid_placement p
set
  grid_col_span = s.ncs,
  grid_row_span = s.nrs,
  grid_col = least(greatest(s.col_scaled, 0), 26 - s.ncs),
  grid_row = least(greatest(s.row_scaled, 0), 20 - s.nrs)
from (
  select
    user_id,
    layout_key,
    item_key,
    greatest(1, least(26, round(grid_col_span * 2.6)::int)) as ncs,
    greatest(1, least(20, round(grid_row_span * 3.3)::int)) as nrs,
    round(grid_col * 2.6)::int as col_scaled,
    round(grid_row * 3.3)::int as row_scaled
  from public.app_ui_user_tile_grid_placement
) s
where p.user_id = s.user_id
  and p.layout_key = s.layout_key
  and p.item_key = s.item_key;

alter table public.app_ui_tile_styles
  add constraint app_ui_tile_styles_grid_col_check
    check (grid_col is null or (grid_col >= 0 and grid_col < 26)),
  add constraint app_ui_tile_styles_grid_row_check
    check (grid_row is null or (grid_row >= 0 and grid_row < 20)),
  add constraint app_ui_tile_styles_grid_col_span_check
    check (grid_col_span is null or (grid_col_span >= 1 and grid_col_span <= 26)),
  add constraint app_ui_tile_styles_grid_row_span_check
    check (grid_row_span is null or (grid_row_span >= 1 and grid_row_span <= 20));

alter table public.app_ui_tile_grid_placement
  add constraint app_ui_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 26),
  add constraint app_ui_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 20),
  add constraint app_ui_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 26),
  add constraint app_ui_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 20);

alter table public.app_ui_user_tile_grid_placement
  add constraint app_ui_user_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 26),
  add constraint app_ui_user_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 20),
  add constraint app_ui_user_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 26),
  add constraint app_ui_user_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 20);

comment on column public.app_ui_tile_styles.grid_col is
  'Colonna griglia 26×20 (0–25). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_row is
  'Riga griglia 26×20 (0–19). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_col_span is
  'Celle orizzontali occupate (1–26). Deriva da size_scale se null.';
comment on column public.app_ui_tile_styles.grid_row_span is
  'Celle verticali occupate (1–20). Deriva da size_scale se null.';

comment on table public.app_ui_tile_grid_placement is
  'Posizione tile sulla griglia 26×20, distinta per ogni pagina (layout_key).';

comment on table public.app_ui_user_tile_grid_placement is
  'Griglia 26×20 personale per layout_key (DT / Assistente DT).';

drop function public._drop_grid_check_constraints(regclass);

notify pgrst, 'reload schema';
