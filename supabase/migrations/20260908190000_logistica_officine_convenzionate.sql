-- Officine convenzionate (tagliandi / carrozzeria / pneumatici) — Logistica

create table if not exists public.logistica_officine_convenzionate (
  id_uuid uuid primary key default gen_random_uuid(),
  fornitore text not null,
  marchio text,
  tipologia text,
  citta text,
  via text,
  provincia text,
  telefono text,
  latitudine double precision,
  longitudine double precision,
  maps_url text,
  note text,
  attivo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_officine_provincia_idx
  on public.logistica_officine_convenzionate (provincia);
create index if not exists logistica_officine_citta_idx
  on public.logistica_officine_convenzionate (citta);
create index if not exists logistica_officine_fornitore_idx
  on public.logistica_officine_convenzionate (fornitore);

create or replace function public.set_logistica_officine_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid
    into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_logistica_officine_audit_fields
  on public.logistica_officine_convenzionate;
create trigger trg_logistica_officine_audit_fields
before insert or update on public.logistica_officine_convenzionate
for each row execute function public.set_logistica_officine_audit_fields();

alter table public.logistica_officine_convenzionate enable row level security;

drop policy if exists logistica_officine_select_role_allowed
  on public.logistica_officine_convenzionate;
create policy logistica_officine_select_role_allowed
on public.logistica_officine_convenzionate
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_officine_convenzionate')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_officine_insert_role_allowed
  on public.logistica_officine_convenzionate;
create policy logistica_officine_insert_role_allowed
on public.logistica_officine_convenzionate
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_officine_convenzionate')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_officine_update_role_allowed
  on public.logistica_officine_convenzionate;
create policy logistica_officine_update_role_allowed
on public.logistica_officine_convenzionate
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_officine_convenzionate')
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_officine_convenzionate')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_officine_delete_role_allowed
  on public.logistica_officine_convenzionate;
create policy logistica_officine_delete_role_allowed
on public.logistica_officine_convenzionate
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_officine_convenzionate')
  or public.has_custom_page_access('logistica')
);

grant select, insert, update, delete
  on public.logistica_officine_convenzionate to authenticated;

drop trigger if exists trg_app_activity_log on public.logistica_officine_convenzionate;
create trigger trg_app_activity_log
after insert or update or delete on public.logistica_officine_convenzionate
for each row execute function public.trg_log_app_activity();

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
    when 'logistica_officine_convenzionate' then 'Officine convenzionate'
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
    p_row->>'fornitore',
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

  if p_table = 'logistica_officine_convenzionate' then
    v_targa := nullif(trim(coalesce(p_row->>'citta', '')), '');
  end if;

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

insert into public.logistica_officine_convenzionate (fornitore, marchio, tipologia, citta, via, provincia, telefono, latitudine, longitudine, maps_url) values
('CAMPOBASSO MOTORI SRL', 'FIAT', 'TAGLIANDO , CARROZZERIA', 'SAN SEVERO', 'Via Michele Zannotti, 275', 'FOGGIA', '0882223620', 41.690555740773654, 15.394424857672265, 'https://maps.app.goo.gl/7GEQEeGwYMj1vNgq9'),
('CARROZZERIA BOVIO GIACOMO', NULL, 'CARROZZERIA', 'CAIRO MONTENOTTE', 'Strada Moglie Verdi, 4, 17014 Rocchetta Cairo SV', 'SAVONA', '019599924', 44.43097226680344, 8.30276397976187, 'https://maps.app.goo.gl/7weYcfZr1u7vA1qC8'),
('AUTOGOMMA DI BRIANO M. E PILOTTO G. S.N.C', NULL, 'PNEUMATICI', 'CAIRO MONTENOTTE', 'Via Pradonne, 19', 'SAVONA', '019512107', 44.393089671802194, 8.288625713006828, 'https://maps.app.goo.gl/HkykHK6ZW571XtuD6'),
('NUOVA ESSECIAUTO SAS DI CEPPI RICHARD & C.', 'GENERICO', 'PNEUMATICI, TAGLIANDI, CRISTALLI, CARROZZERIA', 'COSSERIA', 'Frazione Lidora, 48/a', 'SAVONA', '019510247', 44.36407992279833, 8.277334172938254, 'https://maps.app.goo.gl/uqeftAss4speDRFN9'),
('F.LLI VANCHERI SRL', 'RENAULT', 'OFFICINA CAMION', 'CALTANISSETTA', 'ctr, Niscima Nord', 'CALTANISSETTA', '0934568111', 37.47239419034804, 14.010113760318315, 'https://maps.app.goo.gl/e3d26JkjTP5tz24b7'),
('TURCO ROCCO', NULL, 'TAGLIANDO, PNEUMATICI', 'RIESI', 'VIA ENNA, 12', 'CALTANISSETTA', '3358429614 - ''0934 928274', 37.2780813082462, 14.081943823908814, 'https://maps.app.goo.gl/LmxQYnSdN4carWM99'),
('RS MOTORS SRL a socio unico', 'JEEP , FIAT', 'TAGLIANDO', 'CAIRO MONTENOTTE', 'Via Brigate Partigiane, 16', 'SAVONA', '019507941', 44.39054043443511, 8.281483780960556, 'https://maps.app.goo.gl/U8UbhF4JUh1Dy9bi8'),
('DRIVE MOTORS SRLS', 'FIAT, JEEP', 'TAGLIANDO, CARROZZERIA', 'COLLEFERRO', 'Via Casilina, km.51/700', 'ROMA', '069770427', 41.74094702441557, 13.012381225917729, 'https://maps.app.goo.gl/AF7HjFntJQasWRtp8'),
('SERVICE PIT STOP srl', 'FORD', 'TAGLIANDO', 'BAGHERIA', 'Via Federico II, 21/23', 'PALERMO', '091932688', 38.09069921226733, 13.50257733231315, 'https://maps.app.goo.gl/hz5wA5nqkD5yTx8E9'),
('AUTOGEM SNC', 'FORD', 'TAGLIANDO, MECCANICA, CARROZZERIA , PNEUMATICI', 'CARCARE', 'Via delle Moglie, 8', 'SAVONA', '019510087 / 335281482', 44.35038500661399, 8.29541962417071, 'https://maps.app.goo.gl/wGNGXKEeuEuwS2C49'),
('PNEUS CAR BARBATO SRL', NULL, 'PNEUMATICI, CRISTALLI', 'ACQUI TERME', 'Stradale Alessandria, 124 Ex, 15011 Barbato AL', 'ALESSANDRIA', '0144324940', 44.682376738711504, 8.505940070213628, 'https://maps.app.goo.gl/mjdDD7NGXjwM3Skb9'),
('AP SERVICE E GOMME SRL', 'FORD, FIAT', 'TAGLIANDO', 'PALESTRINA', 'Via Pedemontana, 50, 00036 Palestrina RM', 'ROMA', '069536061', 41.83959986854158, 12.875931454750909, 'https://maps.app.goo.gl/RPYmrLVjkk9VDzDm7'),
('CATTANEO PAOLO', 'FORD', 'TAGLIANDO', 'TERNO', 'Via Roma, 57, 24030 Terno d''Isola BG', 'BERGAMO', '035904163', 45.79248928789045, 9.524619835769071, 'https://maps.app.goo.gl/UPv3Z2vddJxVCLgU8'),
('CO.RI', NULL, 'TAGLIANDO', 'CUMIANA', 'Via Giuseppe Chiantore, 1, 10040 Cumiana TO', 'TORINO', '0119071151', 44.95045646819849, 7.392335326044432, 'https://maps.app.goo.gl/vGKGhwBNurNYTEbT7'),
('CENTROCAR DI CAMILLERI', NULL, 'OFFICINA CAMION', 'CESANO MADERNO', 'Via Sant''Eurosia, 33, 20811 Cesano Maderno MB', 'MONZA BRIANZA', '0362570880', 45.62438814746805, 9.16046271072913, 'https://maps.app.goo.gl/VLv4ZXLYugBU5hv66'),
('OFFICINA MECCANICA BRUNO', NULL, 'OFFICINA CAMION', 'PALAZO SAN GERVASIO', 'Viale Martiri Di Via Fani, 48, 85026 Palazzo San Gervasio PZ', 'POTENZA', '097244300', 40.932796879674434, 15.973454385403674, 'https://maps.app.goo.gl/eXNdEBTahK3FHbsFA'),
('OFFICINA BACCINO', NULL, 'OFFICINA CAMION', 'CAIRO MONTENOTTE', 'Via Cortemilia, 73/B, 17014 Cairo Montenotte SV', 'SAVONA', '019504105', 44.41315224132039, 8.274197056532628, 'https://maps.app.goo.gl/zQFZ2d2MDTpW3BEd7'),
('RIVIERAUTO GALVAGNO', 'FORD', 'TAGLIANDO', 'ALBENGA', 'Regione Cavallo, 24, 17031 Albenga SV', 'SAVONA', '0182540707', 44.07452885413088, 8.195894558230162, 'https://maps.app.goo.gl/KUEoCGH74dp5wPY1A'),
('PNEUMATICI MELE', 'GENERICO', 'PNEUMATICI, TAGLIANDI, CRISTALLI', 'ACQUAVIVA DELLE FONTI', 'Via Molise S.p.per Sammichele Lotto 54, 70021 Zona Industriale BA', 'BARI', '080762353', 41.562941989990144, 17.043107896237874, 'https://maps.app.goo.gl/KY5TwN85HJzFpFYw6'),
('TICCONI PNEUMATICI', NULL, 'PNEUMATICI', 'COLLEFERRO', 'Via Casilina, 00034 Colleferro RM', 'ROMA', '069770059', 41.748149889499956, 12.993767937409036, 'https://maps.app.goo.gl/ky9w9Km3Et6esBnY6'),
('OFFICINE BONELLO', NULL, 'OFFICINA CAMION', 'GRUGLIASCO', 'Via S. Paolo, 86/12, 10095 Grugliasco TO', 'TORINO', '011784055 - 335.6550670', 45.04601917980842, 7.592051481869782, 'https://maps.app.goo.gl/5Kv8TTA5wV3a1Cfx9'),
('PRADELLA SRL', NULL, 'TAGLIANDO', 'SUZZARA', 'Str. Valle Saliceto, 2/A, 46029 Suzzara MN', 'MANTOVA', '0376535395', 44.98693625210516, 10.768632086506576, 'https://maps.app.goo.gl/cc1zeSos12Vwe7xeA'),
('FDL AUTO', 'FORD', 'TAGLIANDO, PNEUMATICI', 'LECCO', 'Via della Pergola, 49/a, 23900 Lecco LC', 'LECCO', '0341369083', 45.84403168218718, 9.406609509983392, 'https://maps.app.goo.gl/ogt3rPYj9kHpL1Ax8'),
('BARONE PAOLO', 'GENERICO', 'PNEUMATICI, TAGLIANDI, REVISIONI, ELETTRAUTO, MECCANICA', 'CATANIA', 'Via Antonino Longo, 68/70/72, 95125 Catania CT', 'CATANIA', '095446028', 37.514181714124604, 15.0823831122721, 'https://maps.app.goo.gl/4tx11fVcAxM6npXDA'),
('MONTEBELLO GOMME SRL', NULL, 'PNEUMATICI', 'MONTEBELLO VICENTINO', 'SS 11, Via Cà Sordis, 12, 36054', 'VICENZA', '0444440414 - STEFANO', 45.46518665427895, 11.405854086506576, 'https://maps.app.goo.gl/aHkriUHtcLMsxtRy7'),
('MONTEBELLO GOMME SRL', 'GENERICO', 'TAGLIANDO, MECCANICA', 'ARZIGNANO', 'Via vicenza, 48', 'VICENZA', '0444440414 - STEFANO', 45.51525916822302, 11.352654073013147, 'https://maps.app.goo.gl/LZcHvTirLSroKRTTA'),
('FERRARO BRUNO SNC', NULL, 'TAGLIANDO, PNEUMATICI', 'MILLESIMO', 'Via Goffredo Mameli, 17017 Millesimo SV', 'SAVONA', '019564085', 44.367141639520824, 8.201383956637814, 'https://maps.app.goo.gl/EBbEZ9ySksuVYCRx8'),
('ITALIANO VITTORIO', 'GENERICO', 'PNEUMATICI, TAGLIANDI, REVISIONI, ELETTRAUTO, MECCANICA', 'BUTERA', 'Via falconara snc', 'CALTANISSETTA', '0934347316', 37.189690256503134, 14.179981917563019, 'https://maps.app.goo.gl/uTZWN3cxSVwP4Cha7');
