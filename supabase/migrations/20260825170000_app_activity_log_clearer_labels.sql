-- Log app: descrizioni più chiare; non registrare sync/aperture come «Modifica».

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
    when 'logistica_asset_assegnatari_storico' then 'Storico assegnatari'
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
  v_code text;
  v_who text;
  v_targa text;
begin
  v_code := nullif(trim(coalesce(
    p_row->>'telepass',
    p_row->>'multicard',
    p_row->>'identificativo',
    p_row->>'corso',
    p_row->>'titolo',
    p_row->>'articolo',
    p_row->>'nome',
    ''
  )), '');

  v_who := nullif(trim(coalesce(
    p_row->>'nome_cognome',
    p_row->>'full_name',
    p_row->>'dipendente_nome',
    p_row->>'nominativo',
    p_row->>'assegnatario_attuale',
    p_row->>'username',
    ''
  )), '');

  v_targa := nullif(trim(coalesce(
    p_row->>'mezzo_targa',
    p_row->>'targa',
    p_row->>'targa_matricola',
    ''
  )), '');

  if v_targa is not null and v_targa = v_code then
    v_targa := null;
  end if;

  return nullif(trim(both ' · ' from concat_ws(
    ' · ',
    public.app_activity_table_label(p_table),
    v_code,
    v_targa,
    v_who
  )), '');
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
  v_new jsonb;
  v_old jsonb;
begin
  if tg_table_name = 'app_activity_logs' then
    return coalesce(new, old);
  end if;
  if tg_table_name in (
    'logistica_asset_assegnatari_storico',
    'field_timestamps'
  ) then
    return coalesce(new, old);
  end if;
  if auth.uid() is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' then
    v_new := to_jsonb(new)
      - 'updated_at'
      - 'created_at'
      - 'field_timestamps'
      - 'updated_by_user_uuid'
      - 'created_by_user_uuid';
    v_old := to_jsonb(old)
      - 'updated_at'
      - 'created_at'
      - 'field_timestamps'
      - 'updated_by_user_uuid'
      - 'created_by_user_uuid';
    if v_new is not distinct from v_old then
      return new;
    end if;
  end if;

  v_action := case tg_op
    when 'INSERT' then 'insert'
    when 'UPDATE' then 'update'
    when 'DELETE' then 'delete'
    else lower(tg_op)
  end;

  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  perform public._insert_app_activity_log(
    v_action,
    public.app_activity_row_label(tg_table_name, v_row)
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_app_activity_log on public.logistica_asset_assegnatari_storico;
