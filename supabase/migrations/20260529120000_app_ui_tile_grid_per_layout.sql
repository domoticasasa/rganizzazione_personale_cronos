-- Posizione griglia 8×4 per pagina (layout_key + item_key).

create table if not exists public.app_ui_tile_grid_placement (
  layout_key text not null,
  item_key text not null,
  grid_col smallint not null
    check (grid_col >= 0 and grid_col < 8),
  grid_row smallint not null
    check (grid_row >= 0 and grid_row < 4),
  grid_col_span smallint not null default 1
    check (grid_col_span >= 1 and grid_col_span <= 8),
  grid_row_span smallint not null default 1
    check (grid_row_span >= 1 and grid_row_span <= 4),
  updated_at timestamptz not null default now(),
  primary key (layout_key, item_key)
);

comment on table public.app_ui_tile_grid_placement is
  'Posizione tile sulla griglia 8×4, distinta per ogni pagina (layout_key).';

grant select on public.app_ui_tile_grid_placement to authenticated;
grant insert, update, delete on public.app_ui_tile_grid_placement to authenticated;

alter table public.app_ui_tile_grid_placement enable row level security;

drop policy if exists app_ui_tile_grid_placement_select on public.app_ui_tile_grid_placement;
create policy app_ui_tile_grid_placement_select
on public.app_ui_tile_grid_placement
for select
to authenticated
using (true);

drop policy if exists app_ui_tile_grid_placement_write on public.app_ui_tile_grid_placement;
create policy app_ui_tile_grid_placement_write
on public.app_ui_tile_grid_placement
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());

-- Copia posizioni legacy solo se le colonne griglia esistono già.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_ui_tile_styles'
      and column_name = 'grid_col'
  ) then
    insert into public.app_ui_tile_grid_placement (
      layout_key,
      item_key,
      grid_col,
      grid_row,
      grid_col_span,
      grid_row_span
    )
    select
      lo.layout_key,
      ts.item_key,
      ts.grid_col,
      ts.grid_row,
      coalesce(ts.grid_col_span, 1),
      coalesce(ts.grid_row_span, 1)
    from public.app_ui_tile_styles ts
    join public.app_ui_layout_order lo
      on lo.item_keys @> jsonb_build_array(ts.item_key)
    where ts.grid_col is not null
      and ts.grid_row is not null
    on conflict (layout_key, item_key) do nothing;
  end if;
end $$;

-- Ricarica cache API PostgREST (Supabase).
notify pgrst, 'reload schema';
