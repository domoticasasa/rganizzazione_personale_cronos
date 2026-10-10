-- Aggiunge «visite_mediche» all'ordine Home DT (globale e override utente).

create or replace function public._append_home_dt_key_after_json(
  keys jsonb,
  key_to_add text,
  after_key text
) returns jsonb
language plpgsql
immutable
as $$
declare
  arr text[];
  idx int;
begin
  if keys is null or jsonb_typeof(keys) <> 'array' then
    return jsonb_build_array(key_to_add);
  end if;

  select coalesce(array_agg(value order by ord), array[]::text[])
  into arr
  from jsonb_array_elements_text(keys) with ordinality as t(value, ord);

  if key_to_add = any(arr) then
    return keys;
  end if;

  idx := array_position(arr, after_key);
  if idx is null then
    arr := arr || array[key_to_add];
  else
    arr := arr[1:idx] || array[key_to_add] || arr[idx + 1:array_length(arr, 1)];
  end if;

  return to_jsonb(arr);
end;
$$;

update public.app_ui_layout_order
set item_keys = public._append_home_dt_key_after_json(
  item_keys,
  'visite_mediche',
  'richieste_ferie_permessi'
)
where layout_key = 'home_dt'
  and not (item_keys @> '["visite_mediche"]'::jsonb);

update public.app_ui_user_layout_order
set item_keys = public._append_home_dt_key_after_json(
  item_keys,
  'visite_mediche',
  'richieste_ferie_permessi'
)
where layout_key = 'home_dt'
  and not (item_keys @> '["visite_mediche"]'::jsonb);

update public.app_ui_layout_order
set item_keys = (
  select coalesce(jsonb_agg(elem), '[]'::jsonb)
  from jsonb_array_elements_text(item_keys) as elem
  where elem <> 'visite_mediche'
)
where layout_key = '__hidden_item_keys__'
  and item_keys @> '["visite_mediche"]'::jsonb;

drop function public._append_home_dt_key_after_json(jsonb, text, text);
