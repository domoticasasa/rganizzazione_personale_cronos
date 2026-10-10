-- bookings / bookings_treno / bookings_aereo non hanno updated_at (né sempre *_user_uuid).
-- set_field_timestamps() accedeva a NEW.updated_at → errore 42703 in UPDATE status.

create or replace function public.set_field_timestamps()
returns trigger
language plpgsql
as $$
declare
  k text;
  new_json jsonb := to_jsonb(new);
  old_json jsonb := to_jsonb(old);
  ts jsonb := coalesce(new.field_timestamps, '{}'::jsonb);
  nowv timestamptz := now();
  v_user_uuid uuid;
  v_entry jsonb;
  v_at timestamptz;
  v_by text;
  skip_keys text[] := array[
    'field_timestamps', 'created_at', 'updated_at', 'id', 'id_uuid',
    'created_by_user_uuid', 'updated_by_user_uuid', 'created_by', 'updated_by',
    'active'
  ];
begin
  select u.id_uuid
    into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  v_entry := jsonb_build_object(
    'at', to_jsonb(nowv),
    'by', coalesce(v_user_uuid::text, '')
  );

  if tg_op = 'INSERT' then
    for k in select jsonb_object_keys(new_json)
    loop
      if k = any (skip_keys) then
        continue;
      end if;
      ts := jsonb_set(ts, array[k], v_entry, true);
    end loop;
    new.field_timestamps := ts;
    return new;
  end if;

  for k in select jsonb_object_keys(new_json)
  loop
    if k = any (skip_keys) then
      continue;
    end if;
    if (old_json -> k) is distinct from (new_json -> k) then
      ts := jsonb_set(ts, array[k], v_entry, true);
    elsif not (ts ? k) then
      v_at := coalesce(
        nullif(new_json ->> 'updated_at', '')::timestamptz,
        nullif(new_json ->> 'created_at', '')::timestamptz,
        nowv
      );
      v_by := coalesce(
        nullif(trim(new_json ->> 'updated_by_user_uuid'), ''),
        nullif(trim(new_json ->> 'created_by_user_uuid'), ''),
        nullif(trim(new_json ->> 'updated_by'), ''),
        nullif(trim(new_json ->> 'created_by'), ''),
        nullif(trim(new_json ->> 'dt_user_uuid'), ''),
        v_user_uuid::text,
        ''
      );
      ts := jsonb_set(
        ts,
        array[k],
        jsonb_build_object('at', to_jsonb(v_at), 'by', v_by),
        true
      );
    end if;
  end loop;

  new.field_timestamps := ts;
  return new;
end;
$$;
