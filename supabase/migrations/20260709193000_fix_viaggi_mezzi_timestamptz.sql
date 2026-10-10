-- I viaggi mezzi usavano timezone('Europe/Rome', now()) in colonne timestamptz:
-- l'ora italiana veniva interpretata come UTC (+1/+2h in visualizzazione).
-- Correzione: salvare now() (istante UTC) e riallineare i record esistenti.

update public.logistica_mezzi_stradali_viaggi
set
  iniziato_at = (iniziato_at at time zone 'UTC') at time zone 'Europe/Rome',
  chiuso_at = case
    when chiuso_at is not null
    then (chiuso_at at time zone 'UTC') at time zone 'Europe/Rome'
    else null
  end
where iniziato_at is not null;

update public.logistica_mezzi_stradali m
set km_aggiornato_il = (m.km_aggiornato_il at time zone 'UTC') at time zone 'Europe/Rome'
where m.km_aggiornato_il is not null
  and exists (
    select 1
    from public.logistica_mezzi_stradali_viaggi v
    where v.mezzo_id_uuid = m.id_uuid
      and v.chiuso_at is not null
      and v.chiuso_at >= m.km_aggiornato_il - interval '5 seconds'
      and v.chiuso_at <= m.km_aggiornato_il + interval '5 seconds'
  );

create or replace function public.registra_scansione_viaggio_mezzo(
  p_qr_token text,
  p_km bigint,
  p_latitudine double precision default null,
  p_longitudine double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_bundle jsonb;
  v_personale jsonb;
  v_personale_id uuid;
  v_nome text;
  v_user_uuid uuid;
  v_mezzo public.logistica_mezzi_stradali%rowtype;
  v_viaggio public.logistica_mezzi_stradali_viaggi%rowtype;
  v_now timestamptz;
  v_km bigint;
  v_km_percorsi bigint;
begin
  v_token := public.parse_viaggio_mezzo_qr_token(p_qr_token);
  if v_token is null then
    raise exception 'QR code non valido.';
  end if;

  v_km := p_km;
  if v_km is null or v_km < 0 then
    raise exception 'Inserisci un chilometraggio valido.';
  end if;

  v_bundle := public.get_my_personale_profile();
  v_personale := v_bundle -> 'personale';
  if v_personale is null then
    raise exception 'Profilo dipendente non trovato per questo account.';
  end if;

  v_personale_id := nullif(v_personale ->> 'id_uuid', '')::uuid;
  v_nome := coalesce(nullif(trim(v_personale ->> 'full_name'), ''), '—');
  v_user_uuid := public.current_user_uuid();

  if v_personale_id is null or v_user_uuid is null then
    raise exception 'Profilo dipendente non trovato per questo account.';
  end if;

  select m.*
    into v_mezzo
  from public.logistica_mezzi_stradali m
  where m.qr_token = v_token
    and coalesce(m.active, true) = true
  limit 1;

  if not found then
    raise exception 'QR code non valido o mezzo non attivo.';
  end if;

  v_now := now();

  select v.*
    into v_viaggio
  from public.logistica_mezzi_stradali_viaggi v
  where v.mezzo_id_uuid = v_mezzo.id_uuid
    and v.stato = 'aperto'
  limit 1;

  if found then
    if v_viaggio.conducente_user_uuid is distinct from v_user_uuid then
      raise exception 'Viaggio già in corso da %.', v_viaggio.conducente_nome;
    end if;
    if v_km < v_viaggio.km_partenza then
      raise exception 'Il chilometraggio finale (%) non può essere inferiore a quello iniziale (%).',
        v_km, v_viaggio.km_partenza;
    end if;

    v_km_percorsi := v_km - v_viaggio.km_partenza;

    update public.logistica_mezzi_stradali_viaggi
    set
      stato = 'chiuso',
      km_arrivo = v_km,
      km_percorsi = v_km_percorsi,
      chiuso_at = v_now,
      lat_fine = p_latitudine,
      lon_fine = p_longitudine
    where id_uuid = v_viaggio.id_uuid;

    if coalesce(v_mezzo.km_attuali, 0) < v_km then
      update public.logistica_mezzi_stradali
      set
        km_attuali = v_km,
        km_aggiornato_il = v_now
      where id_uuid = v_mezzo.id_uuid;
    end if;

    return jsonb_build_object(
      'ok', true,
      'azione', 'chiusura',
      'viaggio_id_uuid', v_viaggio.id_uuid,
      'mezzo_id_uuid', v_mezzo.id_uuid,
      'targa', v_mezzo.targa,
      'marca', v_mezzo.marca,
      'modello', v_mezzo.modello,
      'conducente_nome', v_nome,
      'km_partenza', v_viaggio.km_partenza,
      'km_arrivo', v_km,
      'km_percorsi', v_km_percorsi,
      'iniziato_at', v_viaggio.iniziato_at,
      'chiuso_at', v_now,
      'lat_fine', p_latitudine,
      'lon_fine', p_longitudine
    );
  end if;

  insert into public.logistica_mezzi_stradali_viaggi (
    mezzo_id_uuid,
    personale_id_uuid,
    conducente_user_uuid,
    conducente_nome,
    stato,
    km_partenza,
    iniziato_at,
    lat_inizio,
    lon_inizio,
    qr_token_used
  ) values (
    v_mezzo.id_uuid,
    v_personale_id,
    v_user_uuid,
    v_nome,
    'aperto',
    v_km,
    v_now,
    p_latitudine,
    p_longitudine,
    v_token
  )
  returning * into v_viaggio;

  return jsonb_build_object(
    'ok', true,
    'azione', 'apertura',
    'viaggio_id_uuid', v_viaggio.id_uuid,
    'mezzo_id_uuid', v_mezzo.id_uuid,
    'targa', v_mezzo.targa,
    'marca', v_mezzo.marca,
    'modello', v_mezzo.modello,
    'conducente_nome', v_nome,
    'km_partenza', v_km,
    'iniziato_at', v_now,
    'lat_inizio', p_latitudine,
    'lon_inizio', p_longitudine
  );
exception
  when unique_violation then
    raise exception 'Esiste già un viaggio aperto su questo mezzo.';
end;
$$;

grant execute on function public.registra_scansione_viaggio_mezzo(text, bigint, double precision, double precision)
  to authenticated;
