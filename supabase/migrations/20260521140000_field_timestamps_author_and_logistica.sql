-- Timestamp per cella con autore: { "colonna": { "at": "...", "by": "uuid" } }
-- Estende field_timestamps alle tabelle logistica principali.

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
      ts := jsonb_set(
        ts,
        array[k],
        jsonb_build_object(
          'at', to_jsonb(coalesce(new.updated_at, new.created_at, nowv)),
          'by', coalesce(
            nullif(trim(new.updated_by_user_uuid::text), ''),
            nullif(trim(new.created_by_user_uuid::text), ''),
            v_user_uuid::text,
            ''
          )
        ),
        true
      );
    end if;
  end loop;

  new.field_timestamps := ts;
  return new;
end;
$$;

do $$
declare
  t text;
  tables text[] := array[
    'bookings',
    'bookings_treno',
    'bookings_aereo',
    'logistica_box',
    'logistica_mdo_ferroviari',
    'logistica_casette_ps',
    'estintori',
    'dpi_dotazioni',
    'vestiario_dotazioni',
    'logistica_mezzi_stradali',
    'logistica_multicard',
    'logistica_rcc_carburante',
    'logistica_rcc_mdo_carburante',
    'logistica_attrezzature',
    'logistica_noleggio'
  ];
begin
  foreach t in array tables
  loop
    if to_regclass(format('public.%I', t)) is null then
      continue;
    end if;
    execute format(
      'alter table public.%I add column if not exists field_timestamps jsonb not null default ''{}''::jsonb;',
      t
    );
    execute format(
      'drop trigger if exists trg_%I_field_timestamps on public.%I;',
      t, t
    );
    execute format(
      'create trigger trg_%I_field_timestamps before insert or update on public.%I for each row execute function public.set_field_timestamps();',
      t, t
    );
  end loop;
end $$;

-- Converte valori legacy (solo ISO) in oggetti {at, by} usando audit di riga.
create or replace function public.normalize_field_timestamps_legacy(p_row jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  ts jsonb := coalesce(p_row -> 'field_timestamps', '{}'::jsonb);
  k text;
  v jsonb;
  by_text text;
  at_val timestamptz;
  out_ts jsonb := '{}'::jsonb;
begin
  by_text := coalesce(
    nullif(trim(p_row ->> 'updated_by_user_uuid'), ''),
    nullif(trim(p_row ->> 'created_by_user_uuid'), ''),
    ''
  );
  for k, v in select * from jsonb_each(ts)
  loop
    if k = '_initialized' then
      continue;
    end if;
    if jsonb_typeof(v) = 'string' then
      at_val := (v #>> '{}')::timestamptz;
      out_ts := jsonb_set(
        out_ts,
        array[k],
        jsonb_build_object('at', to_jsonb(at_val), 'by', by_text),
        true
      );
    elsif jsonb_typeof(v) = 'object' then
      out_ts := jsonb_set(out_ts, array[k], v, true);
    end if;
  end loop;
  return out_ts;
end;
$$;

do $$
declare
  t text;
  tables text[] := array[
    'bookings',
    'bookings_treno',
    'bookings_aereo',
    'logistica_box',
    'logistica_mdo_ferroviari',
    'logistica_casette_ps',
    'estintori',
    'dpi_dotazioni',
    'vestiario_dotazioni',
    'logistica_mezzi_stradali',
    'logistica_multicard',
    'logistica_rcc_carburante',
    'logistica_rcc_mdo_carburante',
    'logistica_attrezzature',
    'logistica_noleggio'
  ];
  sql text;
begin
  foreach t in array tables
  loop
    if to_regclass(format('public.%I', t)) is null then
      continue;
    end if;
    sql := format(
      $q$
      update public.%I r
      set field_timestamps = public.normalize_field_timestamps_legacy(to_jsonb(r))
      where coalesce(r.field_timestamps, '{}'::jsonb) <> '{}'::jsonb;
      $q$,
      t
    );
    execute sql;
  end loop;
end $$;
