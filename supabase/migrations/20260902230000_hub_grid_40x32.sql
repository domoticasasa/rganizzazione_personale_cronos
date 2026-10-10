-- Griglia hub: da 26×20 a 40×32 (più quadratini, stesso ingombro visivo dei tile).
-- Le posizioni salvate vengono riscalate in modo proporzionale.

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

update public.app_ui_tile_grid_placement p
set
  grid_col_span = s.ncs,
  grid_row_span = s.nrs,
  grid_col = least(greatest(s.col_scaled, 0), 40 - s.ncs),
  grid_row = least(greatest(s.row_scaled, 0), 32 - s.nrs)
from (
  select
    layout_key,
    item_key,
    greatest(1, least(40, round(grid_col_span * 40.0 / 26)::int)) as ncs,
    greatest(1, least(32, round(grid_row_span * 32.0 / 20)::int)) as nrs,
    round(grid_col * 40.0 / 26)::int as col_scaled,
    round(grid_row * 32.0 / 20)::int as row_scaled
  from public.app_ui_tile_grid_placement
) s
where p.layout_key = s.layout_key
  and p.item_key = s.item_key;

update public.app_ui_user_tile_grid_placement p
set
  grid_col_span = s.ncs,
  grid_row_span = s.nrs,
  grid_col = least(greatest(s.col_scaled, 0), 40 - s.ncs),
  grid_row = least(greatest(s.row_scaled, 0), 32 - s.nrs)
from (
  select
    user_id,
    layout_key,
    item_key,
    greatest(1, least(40, round(grid_col_span * 40.0 / 26)::int)) as ncs,
    greatest(1, least(32, round(grid_row_span * 32.0 / 20)::int)) as nrs,
    round(grid_col * 40.0 / 26)::int as col_scaled,
    round(grid_row * 32.0 / 20)::int as row_scaled
  from public.app_ui_user_tile_grid_placement
) s
where p.user_id = s.user_id
  and p.layout_key = s.layout_key
  and p.item_key = s.item_key;

update public.app_ui_tile_styles p
set
  grid_col_span = case
    when p.grid_col_span is null then null
    else s.ncs
  end,
  grid_row_span = case
    when p.grid_row_span is null then null
    else s.nrs
  end,
  grid_col = case
    when p.grid_col is null then null
    else least(greatest(s.col_scaled, 0), 40 - s.ncs)
  end,
  grid_row = case
    when p.grid_row is null then null
    else least(greatest(s.row_scaled, 0), 32 - s.nrs)
  end
from (
  select
    item_key,
    greatest(1, least(40, round(coalesce(grid_col_span, 1) * 40.0 / 26)::int)) as ncs,
    greatest(1, least(32, round(coalesce(grid_row_span, 1) * 32.0 / 20)::int)) as nrs,
    round(coalesce(grid_col, 0) * 40.0 / 26)::int as col_scaled,
    round(coalesce(grid_row, 0) * 32.0 / 20)::int as row_scaled
  from public.app_ui_tile_styles
  where grid_col is not null
     or grid_row is not null
     or grid_col_span is not null
     or grid_row_span is not null
) s
where p.item_key = s.item_key;

alter table public.app_ui_tile_styles
  add constraint app_ui_tile_styles_grid_col_check
    check (grid_col is null or (grid_col >= 0 and grid_col < 40)),
  add constraint app_ui_tile_styles_grid_row_check
    check (grid_row is null or (grid_row >= 0 and grid_row < 32)),
  add constraint app_ui_tile_styles_grid_col_span_check
    check (grid_col_span is null or (grid_col_span >= 1 and grid_col_span <= 40)),
  add constraint app_ui_tile_styles_grid_row_span_check
    check (grid_row_span is null or (grid_row_span >= 1 and grid_row_span <= 32));

alter table public.app_ui_tile_grid_placement
  add constraint app_ui_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 40),
  add constraint app_ui_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 32),
  add constraint app_ui_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 40),
  add constraint app_ui_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 32);

alter table public.app_ui_user_tile_grid_placement
  add constraint app_ui_user_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 40),
  add constraint app_ui_user_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 32),
  add constraint app_ui_user_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 40),
  add constraint app_ui_user_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 32);

comment on column public.app_ui_tile_styles.grid_col is
  'Colonna griglia 40×32 (0–39). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_row is
  'Riga griglia 40×32 (0–31). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_col_span is
  'Celle orizzontali occupate (1–40). Deriva da size_scale se null.';
comment on column public.app_ui_tile_styles.grid_row_span is
  'Celle verticali occupate (1–32). Deriva da size_scale se null.';

comment on table public.app_ui_tile_grid_placement is
  'Posizione tile sulla griglia 40×32, distinta per ogni pagina (layout_key).';

comment on table public.app_ui_user_tile_grid_placement is
  'Griglia 40×32 personale per layout_key (DT / Assistente DT).';

drop function public._drop_grid_check_constraints(regclass);

notify pgrst, 'reload schema';
