-- Un solo pranzo e una sola cena al giorno per dipendente (anche con più record personale).

create or replace function public.current_personale_uuid()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bundle jsonb;
begin
  v_bundle := public.get_my_personale_profile();
  return nullif(v_bundle #>> '{personale,id_uuid}', '')::uuid;
end;
$$;

create or replace function public.stato_buoni_pasto_oggi()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_now_rome timestamptz;
  v_data date;
  v_hour int;
  v_tipo_corrente text;
  v_pranzo boolean := false;
  v_cena boolean := false;
begin
  v_now_rome := timezone('Europe/Rome', now());
  v_data := (v_now_rome)::date;
  v_hour := extract(hour from v_now_rome)::int;
  v_tipo_corrente := case when v_hour < 17 then 'pranzo' else 'cena' end;

  select
    coalesce(bool_or(r.tipo_pasto = 'pranzo'), false),
    coalesce(bool_or(r.tipo_pasto = 'cena'), false)
  into v_pranzo, v_cena
  from public.buoni_pasto_registrazioni r
  join public.personale p on p.id_uuid = r.personale_id_uuid
  where r.data_pasto = v_data
    and public.personale_belongs_to_current_auth(p);

  return jsonb_build_object(
    'data_pasto', v_data,
    'tipo_corrente', v_tipo_corrente,
    'pranzo_registrato', v_pranzo,
    'cena_registrata', v_cena
  );
end;
$$;

create or replace function public.registra_buono_pasto(
  p_qr_token text,
  p_latitudine double precision default null,
  p_longitudine double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bundle jsonb;
  v_personale jsonb;
  v_personale_id uuid;
  v_nome text;
  v_structure_id uuid;
  v_structure_name text;
  v_token text;
  v_now_rome timestamptz;
  v_data date;
  v_tipo text;
  v_hour int;
  v_existing uuid;
begin
  v_token := trim(coalesce(p_qr_token, ''));
  if v_token = '' then
    raise exception 'Token QR non valido.';
  end if;

  if upper(v_token) like 'CRONOS-BP:%' then
    v_token := trim(substring(v_token from position(':' in v_token) + 1));
  end if;

  v_bundle := public.get_my_personale_profile();
  v_personale := v_bundle -> 'personale';
  if v_personale is null then
    raise exception 'Profilo dipendente non trovato per questo account.';
  end if;

  v_personale_id := nullif(v_personale ->> 'id_uuid', '')::uuid;
  v_nome := coalesce(nullif(trim(v_personale ->> 'full_name'), ''), '—');

  if v_personale_id is null then
    raise exception 'Profilo dipendente non trovato per questo account.';
  end if;

  select r.structure_id_uuid, s.name
  into v_structure_id, v_structure_name
  from public.buoni_pasto_ristoranti r
  join public.structures s on s.id_uuid = r.structure_id_uuid
  where r.qr_token = v_token
    and r.attivo = true
    and coalesce(s.active, true) = true
    and s.is_ristorante = true
  limit 1;

  if v_structure_id is null then
    raise exception 'QR code non valido o ristorante non attivo.';
  end if;

  v_now_rome := timezone('Europe/Rome', now());
  v_data := (v_now_rome)::date;
  v_hour := extract(hour from v_now_rome)::int;

  if v_hour < 17 then
    v_tipo := 'pranzo';
  else
    v_tipo := 'cena';
  end if;

  select r.id_uuid
  into v_existing
  from public.buoni_pasto_registrazioni r
  join public.personale p on p.id_uuid = r.personale_id_uuid
  where r.data_pasto = v_data
    and r.tipo_pasto = v_tipo
    and public.personale_belongs_to_current_auth(p)
  limit 1;

  if v_existing is not null then
    raise exception 'Hai già registrato il % per oggi (%).',
      v_tipo,
      to_char(v_data, 'DD/MM/YYYY');
  end if;

  begin
    insert into public.buoni_pasto_registrazioni (
      structure_id_uuid,
      personale_id_uuid,
      dipendente_nome,
      registrato_at,
      data_pasto,
      tipo_pasto,
      qr_token_used,
      latitudine,
      longitudine
    ) values (
      v_structure_id,
      v_personale_id,
      v_nome,
      v_now_rome,
      v_data,
      v_tipo,
      v_token,
      p_latitudine,
      p_longitudine
    );
  exception
    when unique_violation then
      raise exception 'Hai già registrato il % per oggi (%).',
        v_tipo,
        to_char(v_data, 'DD/MM/YYYY');
  end;

  return jsonb_build_object(
    'ok', true,
    'structure_id_uuid', v_structure_id,
    'structure_name', v_structure_name,
    'dipendente_nome', v_nome,
    'data_pasto', v_data,
    'tipo_pasto', v_tipo,
    'registrato_at', v_now_rome,
    'latitudine', p_latitudine,
    'longitudine', p_longitudine
  );
end;
$$;

grant execute on function public.stato_buoni_pasto_oggi() to authenticated;
grant execute on function public.registra_buono_pasto(text, double precision, double precision)
  to authenticated;

notify pgrst, 'reload schema';
