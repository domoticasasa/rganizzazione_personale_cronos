-- Griglia hub: da 8×4 a 10×6 (posizioni salvate 0–7 / 0–3 restano valide).

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

alter table public.app_ui_tile_styles
  add constraint app_ui_tile_styles_grid_col_check
    check (grid_col is null or (grid_col >= 0 and grid_col < 10)),
  add constraint app_ui_tile_styles_grid_row_check
    check (grid_row is null or (grid_row >= 0 and grid_row < 6)),
  add constraint app_ui_tile_styles_grid_col_span_check
    check (grid_col_span is null or (grid_col_span >= 1 and grid_col_span <= 10)),
  add constraint app_ui_tile_styles_grid_row_span_check
    check (grid_row_span is null or (grid_row_span >= 1 and grid_row_span <= 6));

alter table public.app_ui_tile_grid_placement
  add constraint app_ui_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 10),
  add constraint app_ui_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 6),
  add constraint app_ui_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 10),
  add constraint app_ui_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 6);

alter table public.app_ui_user_tile_grid_placement
  add constraint app_ui_user_tile_grid_placement_grid_col_check
    check (grid_col >= 0 and grid_col < 10),
  add constraint app_ui_user_tile_grid_placement_grid_row_check
    check (grid_row >= 0 and grid_row < 6),
  add constraint app_ui_user_tile_grid_placement_grid_col_span_check
    check (grid_col_span >= 1 and grid_col_span <= 10),
  add constraint app_ui_user_tile_grid_placement_grid_row_span_check
    check (grid_row_span >= 1 and grid_row_span <= 6);

comment on column public.app_ui_tile_styles.grid_col is
  'Colonna griglia 10×6 (0–9). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_row is
  'Riga griglia 10×6 (0–5). Null = posizione automatica.';
comment on column public.app_ui_tile_styles.grid_col_span is
  'Celle orizzontali occupate (1–10). Deriva da size_scale se null.';
comment on column public.app_ui_tile_styles.grid_row_span is
  'Celle verticali occupate (1–6). Deriva da size_scale se null.';

comment on table public.app_ui_tile_grid_placement is
  'Posizione tile sulla griglia 10×6, distinta per ogni pagina (layout_key).';

comment on table public.app_ui_user_tile_grid_placement is
  'Griglia 10×6 personale per layout_key (DT / Assistente DT).';

drop function public._drop_grid_check_constraints(regclass);

notify pgrst, 'reload schema';
