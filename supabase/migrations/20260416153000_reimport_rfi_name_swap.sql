-- Reimport RFI da aaa.xlsx con matching robusto su nome/cognome invertiti.
ALTER TABLE public.formazione_rfi_records
  ADD COLUMN IF NOT EXISTS value_text text;

-- Pulisce i soli dati provenienti dal file Excel.
DELETE FROM public.formazione_rfi_records
WHERE source_file = 'aaa.xlsx';

WITH src(row_id, cognome, nome, track_key, field_key, value_date, value_text) AS (
  VALUES
  (1, 'Benzo', 'Andrea', 'mi_ia_mo_fnm', 'data_attestato', '2023-02-10'::date, '2023-02-10 00:00:00'),
  (2, 'Benzo', 'Andrea', 'mi_ia_mo_fnm', 'scadenza', '2025-12-31'::date, '2025-12-31 00:00:00'),
  (3, 'Bernini', 'Gian Luca Albert', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'data_attestato_1_rilascio_o_ultimo_rinnovo', '2022-12-16'::date, '2022-12-16 00:00:00'),
  (4, 'Bernini', 'Gian Luca Albert', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'mantenimento_1_dopo_36_mesi_da_pr_o_rn', '2025-10-28'::date, '2025-10-28 00:00:00'),
  (5, 'Bernini', 'Gian Luca Albert', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'mantenimento_2_dopo_60_mesi_da_pr_o_rn_e_dopo_24_mesi_ma_mc1', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (6, 'Bernini', 'Gian Luca Albert', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'rinnovo_dopo_60_mesi_da_pr_o_ultimo_rn_e_dopo_mc2', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (7, 'Bernini', 'Gian Luca Albert', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'prossima_scadenza', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (8, 'Bernini', 'Gian Luca Albert', 'profili_rfi_is0_scadenza_5_anni', 'data_attestato', '2023-11-04'::date, '2023-11-04 00:00:00'),
  (9, 'Bernini', 'Gian Luca Albert', 'profili_rfi_is0_scadenza_5_anni', 'scadenza', '2028-12-31'::date, '2028-12-31 00:00:00'),
  (10, 'Bruni', 'Giovanni', 'conversione_abilitazione_fse', 'mi_mepc', '2023-08-02'::date, '2023-08-02 00:00:00'),
  (11, 'Bruni', 'Giovanni', 'conversione_abilitazione_eav', 'mi_mepc', NULL, 'X'),
  (12, 'Capasso', 'Vincenzo', 'conversione_abilitazione_fse', 'mi_mepc', '2025-12-04'::date, '2025-12-04 00:00:00'),
  (13, 'Capasso', 'Vincenzo', 'conversione_abilitazione_fse', 'mdo', '2025-12-02'::date, '2025-12-02 00:00:00'),
  (14, 'Capasso', 'Vincenzo', 'conversione_abilitazione_eav', 'mi_mepc', NULL, 'X'),
  (15, 'Capasso', 'Vincenzo', 'conversione_abilitazione_eav', 'mdo', NULL, 'X'),
  (16, 'Cibuc', 'Alexandru', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'mantenimento_1_dopo_36_mesi_da_pr_o_rn', '2025-10-28'::date, '2025-10-28 00:00:00'),
  (17, 'Cibuc', 'Alexandru', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'mantenimento_2_dopo_60_mesi_da_pr_o_rn_e_dopo_24_mesi_ma_mc1', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (18, 'Cibuc', 'Alexandru', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'rinnovo_dopo_60_mesi_da_pr_o_ultimo_rn_e_dopo_mc2', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (19, 'Cibuc', 'Alexandru', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'prossima_scadenza', '2027-12-31'::date, '2027-12-31 00:00:00'),
  (20, 'Di Cara', 'Claudio', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'data_attestato_1_rilascio_o_ultimo_rinnovo', '2017-03-20'::date, '2017-03-20 00:00:00'),
  (21, 'Di Cara', 'Claudio', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'prossima_scadenza', '2023-12-31'::date, '2023-12-31 00:00:00'),
  (22, 'Di Cara', 'Claudio', 'profili_rfi_is0_scadenza_5_anni', 'data_attestato', '2017-03-20'::date, '2017-03-20 00:00:00'),
  (23, 'Di Cara', 'Claudio', 'profili_rfi_is0_scadenza_5_anni', 'scadenza', '2022-12-31'::date, '2022-12-31 00:00:00'),
  (24, 'Federico', 'Corinno', 'conversione_abilitazione_fse', 'mdo', NULL, 'X'),
  (25, 'Federico', 'Corinno', 'conversione_abilitazione_eav', 'mdo', NULL, 'X'),
  (26, 'Guarnaschella', 'Giuseppe', 'profili_rfi_is0_scadenza_5_anni', 'data_attestato', '2023-02-03'::date, '2023-02-03 00:00:00'),
  (27, 'Guarnaschella', 'Giuseppe', 'profili_rfi_is0_scadenza_5_anni', 'scadenza', '2028-12-31'::date, '2028-12-31 00:00:00'),
  (28, 'Guarnaschella', 'Giuseppe', 'conversione_abilitazione_fse', 'mi_mepc', '2025-12-04'::date, '2025-12-04 00:00:00'),
  (29, 'Guarnaschella', 'Giuseppe', 'conversione_abilitazione_fse', 'mdo', '2025-12-02'::date, '2025-12-02 00:00:00'),
  (30, 'Guarnaschella', 'Giuseppe', 'conversione_abilitazione_eav', 'mdo', NULL, 'X'),
  (31, 'Merli', 'Andrea', 'conversione_abilitazione_fse', 'mi_mepc', '2025-12-04'::date, '2025-12-04 00:00:00'),
  (32, 'Merli', 'Andrea', 'conversione_abilitazione_eav', 'mi_mepc', NULL, 'X'),
  (33, 'Migliore', 'Michele', 'conversione_abilitazione_fse', 'mi_mepc', '2025-12-04'::date, '2025-12-04 00:00:00'),
  (34, 'Xhima', 'Ardjan', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'data_attestato_1_rilascio_o_ultimo_rinnovo', '2024-02-04'::date, '2024-02-04 00:00:00'),
  (35, 'Xhima', 'Ardjan', 'profili_rfi_te_ditte_3_e_25kv_mantenimento_3_anni_rinnovo_6_anni', 'prossima_scadenza', '2027-12-31'::date, '2027-12-31 00:00:00')
), candidates AS (
  SELECT
    s.row_id,
    p.id AS personale_id,
    p.id_uuid::text AS personale_uuid,
    s.track_key,
    s.field_key,
    s.value_date,
    s.value_text,
    CASE
      WHEN lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) =
           lower(regexp_replace(trim(s.cognome || ' ' || s.nome), '\s+', ' ', 'g')) THEN 0
      ELSE 1
    END AS match_rank
  FROM src s
  JOIN public.personale p ON
       lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(s.cognome || ' ' || s.nome), '\s+', ' ', 'g'))
    OR lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(s.nome || ' ' || s.cognome), '\s+', ' ', 'g'))
), resolved AS (
  SELECT DISTINCT ON (row_id)
    personale_id,
    personale_uuid AS personale_id_uuid,
    track_key,
    field_key,
    value_date,
    value_text
  FROM candidates
  ORDER BY row_id, match_rank, personale_id
)
INSERT INTO public.formazione_rfi_records(
  personale_id, track_key, field_key, value_date, value_text, source_file, updated_at
)
SELECT
  personale_id, track_key, field_key, value_date, value_text, 'aaa.xlsx', now()
FROM resolved
ON CONFLICT (personale_id, track_key, field_key)
DO UPDATE SET
  value_date = EXCLUDED.value_date,
  value_text = EXCLUDED.value_text,
  source_file = EXCLUDED.source_file,
  updated_at = now();

-- Refresh tabella compatibile con UI Formazione RFI.
DELETE FROM public.formazione_rfi_corsi;

WITH normalized AS (
  SELECT
    p.id_uuid::text AS personale_uuid,
    fr.track_key,
    fr.field_key,
    fr.value_date,
    fr.value_text
  FROM public.formazione_rfi_records fr
  JOIN public.personale p ON p.id = fr.personale_id
  WHERE p.id_uuid IS NOT NULL
    AND trim(p.id_uuid::text) <> ''
), grouped AS (
  SELECT
    personale_uuid,
    track_key,
    min(value_date) FILTER (WHERE field_key IN ('data_attestato', 'definizione', 'data_consegna')) AS data_attestato,
    max(value_date) FILTER (WHERE field_key IN ('scadenza', 'prossima_scadenza', 'rinnovo', 'data_sacdenza_verifica_annuale')) AS scadenza_attestato,
    string_agg(DISTINCT value_text, ' | ') FILTER (
      WHERE value_text IS NOT NULL AND trim(value_text) <> ''
        AND (value_date IS NULL)
        AND field_key NOT IN ('data_attestato','definizione','data_consegna','scadenza','prossima_scadenza','rinnovo','data_sacdenza_verifica_annuale')
    ) AS note_raw
  FROM normalized
  GROUP BY personale_uuid, track_key
), mapped AS (
  SELECT
    personale_uuid AS personale_id,
    initcap(replace(track_key, '_', ' ')) AS corso,
    data_attestato,
    scadenza_attestato,
    CASE
      WHEN note_raw IS NULL THEN NULL
      WHEN length(note_raw) <= 2000 THEN note_raw
      ELSE left(note_raw, 2000)
    END AS note
  FROM grouped
)
INSERT INTO public.formazione_rfi_corsi (
  personale_id, corso, data_attestato, scadenza_attestato, note, updated_at
)
SELECT personale_id, corso, data_attestato, scadenza_attestato, note, now()
FROM mapped
ON CONFLICT (personale_id, corso)
DO UPDATE SET
  data_attestato = EXCLUDED.data_attestato,
  scadenza_attestato = EXCLUDED.scadenza_attestato,
  note = EXCLUDED.note,
  updated_at = now();