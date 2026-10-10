-- Log app: inserimenti, modifiche, cancellazioni sulle tabelle operative + etichette.

create or replace function public.app_activity_table_label(p_table text)
returns text
language sql
immutable
as $$
  select case p_table
    when 'logistica_rcc_carburante' then 'Registro RCC'
    when 'logistica_rcc_mdo_carburante' then 'Registro MDO'
    when 'logistica_mezzi_stradali' then 'Mezzi stradali'
    when 'logistica_multicard' then 'Multicard'
    when 'logistica_telepass' then 'Telepass'
    when 'logistica_noleggio' then 'Noleggio'
    when 'logistica_attrezzature' then 'Attrezzature'
    when 'logistica_box' then 'Box'
    when 'logistica_casette_ps' then 'Casette PS'
    when 'logistica_mdo_ferroviari' then 'MDO ferroviari'
    when 'logistica_mdo_proprieta' then 'MDO proprietà'
    when 'logistica_qt_fattura_import' then 'Fattura carburante'
    when 'logistica_qt_fattura_transazione' then 'Transazione QT'
    when 'visite_mediche_programmazione' then 'Visite mediche'
    when 'formazione_corsi' then 'Formazione D.Lgs'
    when 'formazione_rfi_records' then 'Formazione RFI'
    when 'formazioni' then 'Formazioni'
    when 'uqsa_attestati' then 'Attestati UQSA'
    when 'estintori' then 'Estintori'
    when 'dipendente_assenze' then 'Assenze'
    when 'dislocazione_personale' then 'Dislocazione'
    when 'personale' then 'Anagrafica personale'
    when 'bookings' then 'Pernottamenti'
    when 'bookings_treno' then 'Prenotazioni treno'
    when 'bookings_aereo' then 'Prenotazioni aereo'
    when 'dpi_dotazioni' then 'DPI'
    when 'vestiario_dotazioni' then 'Vestiario'
    when 'vestiario_magazzino' then 'Magazzino vestiario'
    when 'pos_commessa_dipendenti' then 'POS dipendenti'
    when 'pos_commessa_mezzi_stradali' then 'POS mezzi'
    when 'pos_commessa_mdo_ferroviari' then 'POS MDO'
    when 'pos_commessa_mdo_proprieta' then 'POS MDO proprietà'
    when 'doc_firma_batches' then 'Documenti firma'
    when 'doc_firma_assignments' then 'Assegnazioni firma'
    when 'commesse' then 'Commesse'
    when 'user_agenda_entries' then 'Agenda'
    else replace(p_table, '_', ' ')
  end;
$$;

create or replace function public.app_activity_row_label(p_table text, p_row jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v_id text;
  v_who text;
begin
  v_who := nullif(trim(coalesce(
    p_row->>'nome_cognome',
    p_row->>'full_name',
    p_row->>'dipendente_nome',
    p_row->>'nominativo',
    p_row->>'assegnatario_attuale',
    p_row->>'targa',
    p_row->>'targa_matricola',
    p_row->>'multicard',
    p_row->>'corso',
    p_row->>'titolo',
    p_row->>'articolo',
    p_row->>'nome',
    p_row->>'username',
    ''
  )), '');

  v_id := coalesce(
    nullif(p_row->>'id_uuid', ''),
    nullif(p_row->>'id', '')
  );

  return trim(both ' —' from concat_ws(
    ' — ',
    public.app_activity_table_label(p_table),
    v_who,
    case
      when v_id is null then null
      when length(v_id) > 10 then right(v_id, 8)
      else v_id
    end
  ));
end;
$$;

create or replace function public.trg_log_app_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text;
  v_row jsonb;
begin
  if tg_table_name = 'app_activity_logs' then
    return coalesce(new, old);
  end if;
  if auth.uid() is null then
    return coalesce(new, old);
  end if;

  v_action := case tg_op
    when 'INSERT' then 'insert'
    when 'UPDATE' then 'update'
    when 'DELETE' then 'delete'
    else lower(tg_op)
  end;

  if tg_op = 'UPDATE' and new is not distinct from old then
    return new;
  end if;

  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  perform public._insert_app_activity_log(
    v_action,
    public.app_activity_row_label(tg_table_name, v_row)
  );
  return coalesce(new, old);
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select c.relname as tbl
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relname not like 'app_ui_%'
      and c.relname not like 'app_chat_%'
      and c.relname not like 'notification%'
      and c.relname not in (
        'app_activity_logs',
        'logs',
        'users',
        'app_branding',
        'app_page_registry',
        'device_tokens',
        'web_push_subscriptions',
        'windows_channels',
        'doc_firma_otp',
        'user_outlook_connections',
        'formazione_programmazione_config',
        'vestiario_fabbisogno_annuo_config',
        'viaggio_stradale_settings',
        'booking_overdue_hourly_log',
        'dt_pending_approval_hourly_log',
        'logistica_mezzi_km_reminder_log',
        'pos_commessa_lista_meta',
        'pos_commessa_mdo_lista_meta',
        'pos_commessa_mdo_proprieta_lista_meta',
        'pos_commessa_mezzi_stradali_lista_meta'
      )
  loop
    execute format('drop trigger if exists trg_app_activity_log on public.%I', r.tbl);
    execute format(
      'create trigger trg_app_activity_log
       after insert or update or delete on public.%I
       for each row execute function public.trg_log_app_activity()',
      r.tbl
    );
  end loop;
end
$$;
