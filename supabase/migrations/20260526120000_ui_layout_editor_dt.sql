-- Consente a DT e Assistente DT di salvare ordine/stili pulsanti Home (layout condiviso globale).

create or replace function public.is_cronos_ui_layout_editor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_treno_aereo',
        'dt',
        'assistente_dt'
      )
  );
$$;

comment on function public.is_cronos_ui_layout_editor() is
  'Admin, DT e Assistente DT: possono aggiornare ordine/stili pulsanti hub/home.';

drop policy if exists app_ui_layout_order_write on public.app_ui_layout_order;
create policy app_ui_layout_order_write
on public.app_ui_layout_order
for all
to authenticated
using (public.is_cronos_ui_layout_editor())
with check (public.is_cronos_ui_layout_editor());

drop policy if exists app_ui_tile_styles_write on public.app_ui_tile_styles;
create policy app_ui_tile_styles_write
on public.app_ui_tile_styles
for all
to authenticated
using (public.is_cronos_ui_layout_editor())
with check (public.is_cronos_ui_layout_editor());
