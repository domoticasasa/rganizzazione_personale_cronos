-- Viaggi mezzi stradali: QR per mezzo, apertura/chiusura con km e GPS.

alter table public.logistica_mezzi_stradali
  add column if not exists qr_token text;

create unique index if not exists logistica_mezzi_stradali_qr_token_idx
  on public.logistica_mezzi_stradali (qr_token)
  where qr_token is not null and trim(qr_token) <> '';

update public.logistica_mezzi_stradali
set qr_token = replace(gen_random_uuid()::text, '-', '')
where coalesce(trim(qr_token), '') = '';

alter table public.logistica_mezzi_stradali
  alter column qr_token set default replace(gen_random_uuid()::text, '-', '');

create or replace function public.ensure_logistica_mezzo_qr_token()
returns trigger
language plpgsql
as $$
begin
  if coalesce(trim(new.qr_token), '') = '' then
    new.qr_token := replace(gen_random_uuid()::text, '-', '');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_ensure_qr on public.logistica_mezzi_stradali;
create trigger trg_logistica_mezzi_ensure_qr
before insert on public.logistica_mezzi_stradali
for each row execute function public.ensure_logistica_mezzo_qr_token();

create table if not exists public.logistica_mezzi_stradali_viaggi (
  id_uuid uuid primary key default gen_random_uuid(),
  mezzo_id_uuid uuid not null references public.logistica_mezzi_stradali (id_uuid) on delete restrict,
  personale_id_uuid uuid references public.personale (id_uuid) on delete set null,
  conducente_user_uuid uuid references public.users (id_uuid) on delete set null,
  conducente_nome text not null,
  stato text not null,
  km_partenza bigint not null,
  km_arrivo bigint,
  km_percorsi bigint,
  iniziato_at timestamptz not null,
  chiuso_at timestamptz,
  lat_inizio double precision,
  lon_inizio double precision,
  lat_fine double precision,
  lon_fine double precision,
  qr_token_used text,
  created_at timestamptz not null default now(),
  constraint logistica_mezzi_viaggi_stato_check check (stato in ('aperto', 'chiuso')),
  constraint logistica_mezzi_viaggi_km_arrivo_check check (
    km_arrivo is null or km_arrivo >= km_partenza
  )
);

create unique index if not exists logistica_mezzi_viaggi_one_open_per_mezzo_idx
  on public.logistica_mezzi_stradali_viaggi (mezzo_id_uuid)
  where stato = 'aperto';

create index if not exists logistica_mezzi_viaggi_mezzo_inizio_idx
  on public.logistica_mezzi_stradali_viaggi (mezzo_id_uuid, iniziato_at desc);

create index if not exists logistica_mezzi_viaggi_conducente_idx
  on public.logistica_mezzi_stradali_viaggi (conducente_user_uuid, iniziato_at desc);

create or replace function public.is_viaggi_mezzi_logistica_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'logistica',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('viaggi_mezzi_stradali')
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica');
$$;

create or replace function public.mezzo_assegnatario_is_current_user(p_mezzo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.logistica_mezzi_stradali m
    where m.id_uuid = p_mezzo_id
      and m.assegnatario_user_uuid = public.current_user_uuid()
  );
$$;

create or replace function public.parse_viaggio_mezzo_qr_token(p_raw text)
returns text
language plpgsql
immutable
as $$
declare
  v_token text;
begin
  v_token := trim(coalesce(p_raw, ''));
  if v_token = '' then
    return null;
  end if;
  if upper(v_token) like 'CRONOS-VM:%' then
    v_token := trim(substring(v_token from position(':' in v_token) + 1));
  end if;
  if v_token = '' then
    return null;
  end if;
  return v_token;
end;
$$;

create or replace function public.stato_viaggio_mezzo_scansione(p_qr_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_token text;
  v_mezzo public.logistica_mezzi_stradali%rowtype;
  v_viaggio public.logistica_mezzi_stradali_viaggi%rowtype;
  v_user_uuid uuid;
begin
  v_token := public.parse_viaggio_mezzo_qr_token(p_qr_token);
  if v_token is null then
    raise exception 'QR code non valido.';
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

  v_user_uuid := public.current_user_uuid();

  select v.*
    into v_viaggio
  from public.logistica_mezzi_stradali_viaggi v
  where v.mezzo_id_uuid = v_mezzo.id_uuid
    and v.stato = 'aperto'
  limit 1;

  if found then
    if v_viaggio.conducente_user_uuid is distinct from v_user_uuid then
      return jsonb_build_object(
        'azione_attesa', 'bloccato',
        'messaggio', format(
          'Viaggio già in corso da %s dal %s.',
          v_viaggio.conducente_nome,
          to_char(timezone('Europe/Rome', v_viaggio.iniziato_at), 'DD/MM/YYYY HH24:MI')
        ),
        'mezzo_id_uuid', v_mezzo.id_uuid,
        'targa', v_mezzo.targa,
        'marca', v_mezzo.marca,
        'modello', v_mezzo.modello,
        'km_attuali', v_mezzo.km_attuali
      );
    end if;

    return jsonb_build_object(
      'azione_attesa', 'chiusura',
      'mezzo_id_uuid', v_mezzo.id_uuid,
      'targa', v_mezzo.targa,
      'marca', v_mezzo.marca,
      'modello', v_mezzo.modello,
      'km_attuali', v_mezzo.km_attuali,
      'viaggio_id_uuid', v_viaggio.id_uuid,
      'km_partenza', v_viaggio.km_partenza,
      'iniziato_at', v_viaggio.iniziato_at
    );
  end if;

  return jsonb_build_object(
    'azione_attesa', 'apertura',
    'mezzo_id_uuid', v_mezzo.id_uuid,
    'targa', v_mezzo.targa,
    'marca', v_mezzo.marca,
    'modello', v_mezzo.modello,
    'km_attuali', v_mezzo.km_attuali
  );
end;
$$;

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
  v_now_rome timestamptz;
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

  v_now_rome := timezone('Europe/Rome', now());

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
      chiuso_at = v_now_rome,
      lat_fine = p_latitudine,
      lon_fine = p_longitudine
    where id_uuid = v_viaggio.id_uuid;

    if coalesce(v_mezzo.km_attuali, 0) < v_km then
      update public.logistica_mezzi_stradali
      set
        km_attuali = v_km,
        km_aggiornato_il = v_now_rome
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
      'chiuso_at', v_now_rome,
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
    v_now_rome,
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
    'iniziato_at', v_now_rome,
    'lat_inizio', p_latitudine,
    'lon_inizio', p_longitudine
  );
exception
  when unique_violation then
    raise exception 'Esiste già un viaggio aperto su questo mezzo.';
end;
$$;

grant execute on function public.stato_viaggio_mezzo_scansione(text) to authenticated;
grant execute on function public.registra_scansione_viaggio_mezzo(text, bigint, double precision, double precision)
  to authenticated;
grant execute on function public.is_viaggi_mezzi_logistica_admin() to authenticated;

create or replace function public.ensure_mezzo_viaggio_qr_token(p_mezzo_id_uuid uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if p_mezzo_id_uuid is null then
    raise exception 'Mezzo non valido.';
  end if;

  if not (
    public.is_viaggi_mezzi_logistica_admin()
    or public.mezzo_assegnatario_is_current_user(p_mezzo_id_uuid)
  ) then
    raise exception 'Non autorizzato a esportare il QR di questo mezzo.';
  end if;

  select m.qr_token
    into v_token
  from public.logistica_mezzi_stradali m
  where m.id_uuid = p_mezzo_id_uuid
    and coalesce(m.active, true) = true
  limit 1;

  if not found then
    raise exception 'Mezzo non trovato.';
  end if;

  if coalesce(trim(v_token), '') <> '' then
    return v_token;
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '');
  update public.logistica_mezzi_stradali
  set qr_token = v_token
  where id_uuid = p_mezzo_id_uuid;

  return v_token;
end;
$$;

grant execute on function public.ensure_mezzo_viaggio_qr_token(uuid) to authenticated;

alter table public.logistica_mezzi_stradali_viaggi enable row level security;

drop policy if exists logistica_mezzi_viaggi_select on public.logistica_mezzi_stradali_viaggi;
create policy logistica_mezzi_viaggi_select
on public.logistica_mezzi_stradali_viaggi
for select
to authenticated
using (
  public.is_viaggi_mezzi_logistica_admin()
  or conducente_user_uuid = public.current_user_uuid()
  or public.mezzo_assegnatario_is_current_user(mezzo_id_uuid)
);

insert into public.app_page_registry (page_key, label, active)
values
  ('viaggi_mezzi_stradali', 'Viaggi mezzi stradali (logistica)', true),
  ('viaggi_mezzi_scan', 'Scansiona viaggio mezzo', true),
  ('viaggi_mezzi_riepilogo', 'I miei viaggi mezzo', true),
  ('viaggi_mezzi_assegnatario', 'Viaggi sui miei mezzi', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
