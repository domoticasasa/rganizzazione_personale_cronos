-- Timestamp per singolo campo/cella su tabelle principali.
-- Il JSONB field_timestamps conserva: { "nome_colonna": "2026-04-23T11:30:00Z", ... }

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
begin
  if tg_op = 'INSERT' then
    for k in select jsonb_object_keys(new_json)
    loop
      if k not in ('field_timestamps','created_at','updated_at','id','id_uuid') then
        ts := jsonb_set(ts, array[k], to_jsonb(nowv), true);
      end if;
    end loop;
    new.field_timestamps := ts;
    return new;
  end if;

  for k in select jsonb_object_keys(new_json)
  loop
    if k in ('field_timestamps','created_at','updated_at','id','id_uuid') then
      continue;
    end if;
    if (old_json -> k) is distinct from (new_json -> k) then
      ts := jsonb_set(ts, array[k], to_jsonb(nowv), true);
    elsif not (ts ? k) then
      -- Backfill leggero per record vecchi.
      ts := jsonb_set(ts, array[k], to_jsonb(coalesce(new.created_at, nowv)), true);
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
    'vestiario_dotazioni'
  ];
begin
  foreach t in array tables
  loop
    execute format('alter table public.%I add column if not exists field_timestamps jsonb not null default ''{}''::jsonb;', t);
    execute format('drop trigger if exists trg_%I_field_timestamps on public.%I;', t, t);
    execute format('create trigger trg_%I_field_timestamps before insert or update on public.%I for each row execute function public.set_field_timestamps();', t, t);
    execute format(
      'update public.%I set field_timestamps = jsonb_set(coalesce(field_timestamps,''{}''::jsonb), ''{_initialized}'', to_jsonb(now()), true) where coalesce(field_timestamps,''{}''::jsonb) = ''{}''::jsonb;',
      t
    );
  end loop;
end $$;

