-- Annulla Rimborso spese (feature creata per errore su questa app).

drop policy if exists rimborso_spese_storage_select on storage.objects;
drop policy if exists rimborso_spese_storage_insert on storage.objects;
drop policy if exists rimborso_spese_storage_update on storage.objects;
drop policy if exists rimborso_spese_storage_delete on storage.objects;

drop table if exists public.rimborso_spese_allegati cascade;
drop table if exists public.rimborso_spese_voci cascade;
drop table if exists public.rimborso_spese_richieste cascade;

drop function if exists public.set_rimborso_spese_updated_at();
drop function if exists public.is_rimborso_spese_reader();
drop function if exists public.can_write_rimborso_spese();

-- Togli il tile dai layout già salvati.
update public.app_ui_layout_order
set item_keys = coalesce((
  select jsonb_agg(elem)
  from jsonb_array_elements(item_keys) as t(elem)
  where elem #>> '{}' is distinct from 'rimborso_spese'
), '[]'::jsonb)
where exists (
  select 1
  from jsonb_array_elements(item_keys) as t(elem)
  where elem #>> '{}' = 'rimborso_spese'
);

delete from public.app_ui_user_tile_style
where item_key = 'rimborso_spese';
delete from public.app_ui_user_tile_grid_placement
where item_key = 'rimborso_spese';
delete from public.app_ui_tile_styles
where item_key = 'rimborso_spese';
delete from public.app_ui_tile_grid_placement
where item_key = 'rimborso_spese';

do $$
begin
  if to_regclass('public.app_ui_user_layout_order') is not null then
    execute $sql$
      update public.app_ui_user_layout_order
      set item_keys = coalesce((
        select jsonb_agg(elem)
        from jsonb_array_elements(item_keys) as t(elem)
        where elem #>> '{}' is distinct from 'rimborso_spese'
      ), '[]'::jsonb)
      where exists (
        select 1
        from jsonb_array_elements(item_keys) as t(elem)
        where elem #>> '{}' = 'rimborso_spese'
      )
    $sql$;
  end if;
end $$;
