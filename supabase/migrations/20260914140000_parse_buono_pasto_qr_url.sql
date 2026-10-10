-- QR buono pasto: accetta URL HTTPS `?bp=` (fotocamera nativa) oltre a CRONOS-BP:

create or replace function public.parse_buono_pasto_qr_token(p_raw text)
returns text
language plpgsql
immutable
as $$
declare
  v_token text;
  v_bp text;
begin
  v_token := trim(coalesce(p_raw, ''));
  if v_token = '' then
    return null;
  end if;

  v_bp := substring(v_token from '[?&][Bb][Pp]=([^&#]+)');
  if v_bp is not null and trim(v_bp) <> '' then
    v_token := trim(v_bp);
  end if;

  if upper(v_token) like 'CRONOS-BP:%' then
    v_token := trim(substring(v_token from position(':' in v_token) + 1));
  end if;

  if v_token = '' then
    return null;
  end if;
  return v_token;
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
  v_token := public.parse_buono_pasto_qr_token(p_qr_token);
  if v_token is null then
    raise exception 'Token QR non valido.';
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

grant execute on function public.parse_buono_pasto_qr_token(text) to authenticated;
grant execute on function public.registra_buono_pasto(text, double precision, double precision)
  to authenticated;

notify pgrst, 'reload schema';
