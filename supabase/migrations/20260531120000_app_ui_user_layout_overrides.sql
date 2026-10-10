-- Layout Home/hub personalizzato per DT e Assistente DT (non modifica il layout globale).

create or replace function public.cronos_current_user_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select u.id
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;
$$;

comment on function public.cronos_current_user_id() is
  'users.id dell''utente autenticato corrente.';

-- Ordine tile per utente (stessa struttura di app_ui_layout_order).
create table if not exists public.app_ui_user_layout_order (
  user_id integer not null references public.users (id) on delete cascade,
  layout_key text not null,
  item_keys jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, layout_key)
);

comment on table public.app_ui_user_layout_order is
  'Ordine tile hub/home personale (DT / Assistente DT).';

-- Aspetto tile personale (override su app_ui_tile_styles globale).
create table if not exists public.app_ui_user_tile_style (
  user_id integer not null references public.users (id) on delete cascade,
  item_key text not null,
  custom_label text,
  background_color text,
  text_color text,
  icon_color text,
  size_scale real not null default 1.0
    check (size_scale >= 0.5 and size_scale <= 2.0),
  icon_codepoint integer,
  font_family text,
  title_font_size real,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_key)
);

comment on table public.app_ui_user_tile_style is
  'Stile tile personale (DT / Assistente DT).';

-- Posizione griglia 8×4 personale per pagina.
create table if not exists public.app_ui_user_tile_grid_placement (
  user_id integer not null references public.users (id) on delete cascade,
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
  primary key (user_id, layout_key, item_key)
);

comment on table public.app_ui_user_tile_grid_placement is
  'Griglia 8×4 personale per layout_key (DT / Assistente DT).';

grant select, insert, update, delete on public.app_ui_user_layout_order to authenticated;
grant select, insert, update, delete on public.app_ui_user_tile_style to authenticated;
grant select, insert, update, delete on public.app_ui_user_tile_grid_placement to authenticated;

alter table public.app_ui_user_layout_order enable row level security;
alter table public.app_ui_user_tile_style enable row level security;
alter table public.app_ui_user_tile_grid_placement enable row level security;

drop policy if exists app_ui_user_layout_order_own on public.app_ui_user_layout_order;
create policy app_ui_user_layout_order_own
on public.app_ui_user_layout_order
for all
to authenticated
using (user_id = public.cronos_current_user_id())
with check (user_id = public.cronos_current_user_id());

drop policy if exists app_ui_user_tile_style_own on public.app_ui_user_tile_style;
create policy app_ui_user_tile_style_own
on public.app_ui_user_tile_style
for all
to authenticated
using (user_id = public.cronos_current_user_id())
with check (user_id = public.cronos_current_user_id());

drop policy if exists app_ui_user_tile_grid_placement_own on public.app_ui_user_tile_grid_placement;
create policy app_ui_user_tile_grid_placement_own
on public.app_ui_user_tile_grid_placement
for all
to authenticated
using (user_id = public.cronos_current_user_id())
with check (user_id = public.cronos_current_user_id());

-- Layout globale: solo admin (DT usa tabelle utente).
drop policy if exists app_ui_layout_order_write on public.app_ui_layout_order;
create policy app_ui_layout_order_write
on public.app_ui_layout_order
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());

drop policy if exists app_ui_tile_styles_write on public.app_ui_tile_styles;
create policy app_ui_tile_styles_write
on public.app_ui_tile_styles
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());

notify pgrst, 'reload schema';
