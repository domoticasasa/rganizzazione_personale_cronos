-- Posizione GPS al momento della scansione buono pasto.

alter table public.buoni_pasto_registrazioni
  add column if not exists latitudine double precision,
  add column if not exists longitudine double precision;

comment on column public.buoni_pasto_registrazioni.latitudine is
  'Latitudine GPS del dispositivo al momento della scansione QR.';
comment on column public.buoni_pasto_registrazioni.longitudine is
  'Longitudine GPS del dispositivo al momento della scansione QR.';

drop function if exists public.registra_buono_pasto(text);

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

  select p.id_uuid, coalesce(nullif(trim(p.full_name), ''), '—')
  into v_personale_id, v_nome
  from public.personale p
  where p.user_id::text = auth.uid()::text
    and coalesce(p.active, true) = true
  limit 1;

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

  select id_uuid into v_existing
  from public.buoni_pasto_registrazioni
  where personale_id_uuid = v_personale_id
    and data_pasto = v_data
    and tipo_pasto = v_tipo;

  if v_existing is not null then
    raise exception 'Hai già registrato il % per oggi (%).',
      v_tipo,
      to_char(v_data, 'DD/MM/YYYY');
  end if;

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

grant execute on function public.registra_buono_pasto(text, double precision, double precision)
  to authenticated;

notify pgrst, 'reload schema';
