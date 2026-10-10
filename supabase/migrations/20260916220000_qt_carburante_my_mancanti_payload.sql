-- Payload QT/RCC per dipendente: solo le proprie transazioni da giustificare.
-- Bypass RLS in modo controllato (security definer).

create or replace function public.cronos_norm_person_name(raw text)
returns text
language sql
immutable
as $$
  select trim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            lower(trim(coalesce(raw, ''))),
            '->.*$',
            ' ',
            'g'
          ),
          '\([^)]*\)',
          ' ',
          'g'
        ),
        '[^a-z0-9 ]',
        ' ',
        'g'
      ),
      '\s+',
      ' ',
      'g'
    )
  );
$$;

create or replace function public.cronos_norm_carta(raw text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(coalesce(raw, ''), '\D', '', 'g') <> ''
      then regexp_replace(coalesce(raw, ''), '\D', '', 'g')
    else regexp_replace(trim(coalesce(raw, '')), '\s+', '', 'g')
  end;
$$;

create or replace function public.cronos_carte_match(a text, b text)
returns boolean
language sql
immutable
as $$
  select case
    when nullif(public.cronos_norm_carta(a), '') is null
      or nullif(public.cronos_norm_carta(b), '') is null
      then false
    when public.cronos_norm_carta(a) = public.cronos_norm_carta(b) then true
    when length(public.cronos_norm_carta(a)) > length(public.cronos_norm_carta(b))
      and right(public.cronos_norm_carta(a), length(public.cronos_norm_carta(b)))
        = public.cronos_norm_carta(b)
      then true
    when length(public.cronos_norm_carta(b)) > length(public.cronos_norm_carta(a))
      and right(public.cronos_norm_carta(b), length(public.cronos_norm_carta(a)))
        = public.cronos_norm_carta(a)
      then true
    else false
  end;
$$;

create or replace function public.qt_carburante_my_mancanti_payload(
  p_anno integer,
  p_mese integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_my_name text;
  v_my_norm text;
  v_import_id uuid;
  v_has_import boolean := false;
  v_data_min date;
  v_data_max date;
  v_trx jsonb := '[]'::jsonb;
  v_rcc_stradali jsonb := '[]'::jsonb;
  v_rcc_mdo jsonb := '[]'::jsonb;
begin
  if p_anno is null or p_mese is null or p_mese < 1 or p_mese > 12 then
    return jsonb_build_object(
      'has_import', false,
      'anno', p_anno,
      'mese', p_mese,
      'transazioni', '[]'::jsonb,
      'rcc_stradali', '[]'::jsonb,
      'rcc_mdo', '[]'::jsonb
    );
  end if;

  select coalesce(
    nullif(trim(u.full_name), ''),
    nullif(trim(u.username), '')
  )
  into v_my_name
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if v_my_name is null or public.cronos_norm_person_name(v_my_name) = '' then
    return jsonb_build_object(
      'has_import', false,
      'anno', p_anno,
      'mese', p_mese,
      'transazioni', '[]'::jsonb,
      'rcc_stradali', '[]'::jsonb,
      'rcc_mdo', '[]'::jsonb
    );
  end if;
  v_my_norm := public.cronos_norm_person_name(v_my_name);

  select i.id_uuid
  into v_import_id
  from public.logistica_qt_fattura_import i
  where i.anno = p_anno
    and i.mese = p_mese
  limit 1;

  if v_import_id is null then
    return jsonb_build_object(
      'has_import', false,
      'anno', p_anno,
      'mese', p_mese,
      'transazioni', '[]'::jsonb,
      'rcc_stradali', '[]'::jsonb,
      'rcc_mdo', '[]'::jsonb
    );
  end if;
  v_has_import := true;

  -- Transazioni del mese dove il responsabile alla data = utente corrente.
  with multicard_base as (
    select
      m.multicard as carta_raw,
      public.cronos_norm_carta(m.multicard) as carta_norm,
      nullif(trim(m.assegnatario_attuale), '') as assegnatario_attuale,
      nullif(trim(m.mezzo_targa), '') as mezzo_targa,
      case
        when m.periodo_assegnatario_attuale is null then null
        else m.periodo_assegnatario_attuale::date
      end as periodo_dal_attuale,
      case
        when m.data_fine_assegnatario_attuale is null then null
        else m.data_fine_assegnatario_attuale::date
      end as periodo_al_attuale
    from public.logistica_multicard m
    where nullif(trim(m.multicard), '') is not null
  ),
  mezzi_fallback as (
    select
      lower(trim(ms.targa)) as targa_norm,
      nullif(trim(ms.assegnatario_attuale), '') as assegnatario
    from public.logistica_mezzi_stradali ms
    where nullif(trim(ms.targa), '') is not null
      and nullif(trim(ms.assegnatario_attuale), '') is not null
  ),
  storico as (
    select
      s.identificativo,
      public.cronos_norm_carta(s.identificativo) as carta_norm,
      nullif(trim(s.assegnatario), '') as assegnatario,
      s.periodo_dal::date as dal,
      s.periodo_al::date as al,
      coalesce(s.passaggio, 0) as passaggio
    from public.logistica_asset_assegnatari_storico s
    where s.tipo_asset = 'multicard'
      and nullif(trim(s.assegnatario), '') is not null
      and s.periodo_dal is not null
  ),
  trx as (
    select
      t.riga_excel,
      t.numero_carta,
      public.cronos_norm_carta(t.numero_carta) as carta_norm,
      t.prodotto,
      t.data_transazione::date as data_transazione,
      t.volume::float8 as volume,
      t.importo::float8 as importo,
      t.file_sorgente
    from public.logistica_qt_fattura_transazione t
    where t.import_id_uuid = v_import_id
  ),
  resolved as (
    select
      x.*,
      coalesce(
        (
          select s.assegnatario
          from storico s
          where public.cronos_carte_match(s.carta_norm, x.carta_norm)
            and s.dal <= x.data_transazione
            and (s.al is null or s.al >= x.data_transazione)
          order by
            (s.al is not null) desc,
            (coalesce(s.al, date '9999-12-31') - s.dal) asc,
            s.passaggio asc
          limit 1
        ),
        (
          select coalesce(
            mb.assegnatario_attuale,
            mf.assegnatario
          )
          from multicard_base mb
          left join mezzi_fallback mf
            on mf.targa_norm = lower(trim(coalesce(mb.mezzo_targa, '')))
          where public.cronos_carte_match(mb.carta_norm, x.carta_norm)
            and (
              mb.periodo_dal_attuale is null
              or (
                mb.periodo_dal_attuale <= x.data_transazione
                and (
                  mb.periodo_al_attuale is null
                  or mb.periodo_al_attuale >= x.data_transazione
                )
              )
            )
          limit 1
        ),
        (
          select coalesce(mb.assegnatario_attuale, mf.assegnatario)
          from multicard_base mb
          left join mezzi_fallback mf
            on mf.targa_norm = lower(trim(coalesce(mb.mezzo_targa, '')))
          where public.cronos_carte_match(mb.carta_norm, x.carta_norm)
          limit 1
        )
      ) as responsabile
    from trx x
  ),
  mine as (
    select *
    from resolved r
    where public.cronos_norm_person_name(r.responsabile) = v_my_norm
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'riga_excel', m.riga_excel,
          'numero_carta', m.numero_carta,
          'prodotto', m.prodotto,
          'data_transazione', m.data_transazione,
          'volume', m.volume,
          'importo', m.importo,
          'file_sorgente', m.file_sorgente,
          'responsabile', m.responsabile
        )
        order by m.data_transazione, m.numero_carta
      ),
      '[]'::jsonb
    ),
    min(m.data_transazione),
    max(m.data_transazione)
  into v_trx, v_data_min, v_data_max
  from mine m;

  if v_data_min is null then
    return jsonb_build_object(
      'has_import', v_has_import,
      'anno', p_anno,
      'mese', p_mese,
      'nome', v_my_name,
      'transazioni', '[]'::jsonb,
      'rcc_stradali', '[]'::jsonb,
      'rcc_mdo', '[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_uuid', r.id_uuid,
        'n_carta_carburante', r.n_carta_carburante,
        'data_rifornimento', r.data_rifornimento,
        'litri', r.litri,
        'euro', r.euro,
        'tipo_carburante', r.tipo_carburante,
        'nome_cognome', r.nome_cognome,
        'cantiere', r.cantiere
      )
    ),
    '[]'::jsonb
  )
  into v_rcc_stradali
  from public.logistica_rcc_carburante r
  where r.data_rifornimento between (v_data_min - 2) and (v_data_max + 2)
    and exists (
      select 1
      from jsonb_array_elements(v_trx) e
      where public.cronos_carte_match(
        e->>'numero_carta',
        r.n_carta_carburante
      )
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_uuid', r.id_uuid,
        'n_carta_carburante', r.n_carta_carburante,
        'data_rifornimento', r.data_rifornimento,
        'litri', r.litri,
        'euro', r.euro,
        'tipo_carburante', r.tipo_carburante,
        'nome_cognome', r.nome_cognome,
        'cantiere', r.cantiere
      )
    ),
    '[]'::jsonb
  )
  into v_rcc_mdo
  from public.logistica_rcc_mdo_carburante r
  where r.data_rifornimento between (v_data_min - 2) and (v_data_max + 2)
    and exists (
      select 1
      from jsonb_array_elements(v_trx) e
      where public.cronos_carte_match(
        e->>'numero_carta',
        r.n_carta_carburante
      )
    );

  return jsonb_build_object(
    'has_import', v_has_import,
    'anno', p_anno,
    'mese', p_mese,
    'nome', v_my_name,
    'transazioni', v_trx,
    'rcc_stradali', coalesce(v_rcc_stradali, '[]'::jsonb),
    'rcc_mdo', coalesce(v_rcc_mdo, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.cronos_norm_person_name(text) to authenticated;
grant execute on function public.cronos_norm_carta(text) to authenticated;
grant execute on function public.cronos_carte_match(text, text) to authenticated;
grant execute on function public.qt_carburante_my_mancanti_payload(integer, integer) to authenticated;

comment on function public.qt_carburante_my_mancanti_payload(integer, integer) is
  'Payload QT+RCC per giustificazioni mancanti del dipendente autenticato.';
