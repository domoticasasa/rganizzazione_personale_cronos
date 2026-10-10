-- Allinea automaticamente il registro storico assegnatari (4 passaggi)
-- alla creazione/aggiornamento di mezzi stradali e multicard.

create or replace function public.logistica_telepass_is_empty(p_raw text)
returns boolean
language sql
immutable
as $$
  select case
    when nullif(trim(coalesce(p_raw, '')), '') is null then true
    when lower(trim(p_raw)) in ('--', '-', '—') then true
    when lower(trim(p_raw)) like '%no telepass%' then true
    else false
  end;
$$;

create or replace function public.ensure_logistica_asset_assegnatari_storico(
  p_tipo_asset text,
  p_identificativo text,
  p_mezzo_targa text default null,
  p_mezzo_id_uuid uuid default null,
  p_multicard_id_uuid uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i int;
  v_id text := nullif(trim(p_identificativo), '');
begin
  if v_id is null then
    return;
  end if;

  for i in 1..4 loop
    insert into public.logistica_asset_assegnatari_storico (
      tipo_asset,
      identificativo,
      passaggio,
      mezzo_targa,
      mezzo_id_uuid,
      multicard_id_uuid
    )
    values (
      p_tipo_asset,
      v_id,
      i,
      nullif(trim(p_mezzo_targa), ''),
      p_mezzo_id_uuid,
      p_multicard_id_uuid
    )
    on conflict (tipo_asset, identificativo, passaggio) do update
    set
      mezzo_targa = coalesce(
        nullif(trim(excluded.mezzo_targa), ''),
        logistica_asset_assegnatari_storico.mezzo_targa
      ),
      mezzo_id_uuid = coalesce(
        excluded.mezzo_id_uuid,
        logistica_asset_assegnatari_storico.mezzo_id_uuid
      ),
      multicard_id_uuid = coalesce(
        excluded.multicard_id_uuid,
        logistica_asset_assegnatari_storico.multicard_id_uuid
      ),
      updated_at = now();
  end loop;
end;
$$;

create or replace function public.trg_logistica_mezzi_storico_register()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_logistica_asset_assegnatari_storico(
    'mezzo_stradale',
    new.targa,
    new.targa,
    new.id_uuid,
    null
  );

  if not public.logistica_telepass_is_empty(new.telepass) then
    perform public.ensure_logistica_asset_assegnatari_storico(
      'telepass',
      trim(new.telepass),
      new.targa,
      new.id_uuid,
      null
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_storico_register
  on public.logistica_mezzi_stradali;
create trigger trg_logistica_mezzi_storico_register
after insert or update of targa, telepass
on public.logistica_mezzi_stradali
for each row
execute function public.trg_logistica_mezzi_storico_register();

create or replace function public.trg_logistica_multicard_storico_register()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mezzo_id uuid;
begin
  if nullif(trim(new.multicard), '') is null then
    return new;
  end if;

  select m.id_uuid
    into v_mezzo_id
  from public.logistica_mezzi_stradali m
  where lower(trim(coalesce(m.targa, ''))) = lower(trim(coalesce(new.mezzo_targa, '')))
  limit 1;

  perform public.ensure_logistica_asset_assegnatari_storico(
    'multicard',
    new.multicard,
    new.mezzo_targa,
    v_mezzo_id,
    new.id_uuid
  );

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.logistica_multicard') is not null then
    drop trigger if exists trg_logistica_multicard_storico_register
      on public.logistica_multicard;
    create trigger trg_logistica_multicard_storico_register
    after insert or update of multicard, mezzo_targa
    on public.logistica_multicard
    for each row
    execute function public.trg_logistica_multicard_storico_register();
  end if;
end $$;

-- Backfill mezzi e multicard già presenti.
do $$
declare
  r record;
  v_mezzo_id uuid;
begin
  for r in
    select id_uuid, targa, telepass
    from public.logistica_mezzi_stradali
    where nullif(trim(targa), '') is not null
  loop
    perform public.ensure_logistica_asset_assegnatari_storico(
      'mezzo_stradale', r.targa, r.targa, r.id_uuid, null
    );
    if not public.logistica_telepass_is_empty(r.telepass) then
      perform public.ensure_logistica_asset_assegnatari_storico(
        'telepass', trim(r.telepass), r.targa, r.id_uuid, null
      );
    end if;
  end loop;

  if to_regclass('public.logistica_multicard') is not null then
    for r in
      select c.id_uuid, c.multicard, c.mezzo_targa
      from public.logistica_multicard c
      where nullif(trim(c.multicard), '') is not null
    loop
      select m.id_uuid into v_mezzo_id
      from public.logistica_mezzi_stradali m
      where lower(trim(coalesce(m.targa, ''))) =
            lower(trim(coalesce(r.mezzo_targa, '')))
      limit 1;

      perform public.ensure_logistica_asset_assegnatari_storico(
        'multicard', r.multicard, r.mezzo_targa, v_mezzo_id, r.id_uuid
      );
    end loop;
  end if;
end $$;
