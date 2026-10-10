-- Refresh RFI corsi con nomi tab identici all'Excel attuale.
DELETE FROM public.formazione_rfi_corsi;

WITH src(full_cn, full_nc, corso, data_attestato, scadenza_attestato, note) AS (
  VALUES
  ('Benzo Andrea','Andrea Benzo','MI IA MO FNM','2023-02-10'::date,'2025-12-31'::date,NULL),
  ('Bernini Gian Luca Albert','Gian Luca Albert Bernini','PROFILI RFI TE-DITTE 3 e 25kv (Mantenimento 3 Anni) (Rinnovo 6 anni)','2022-12-16'::date,'2027-12-31'::date,'2025-10-28 00:00:00 | 2027-12-31 00:00:00 | 2027-12-31 00:00:00'),
  ('Bernini Gian Luca Albert','Gian Luca Albert Bernini','PROFILI RFI IS0 (Scadenza 5 anni)','2023-11-04'::date,'2028-12-31'::date,NULL),
  ('Bruni Giovanni','Giovanni Bruni','CONVERSIONE/ABILITAZIONE FSE','2023-08-02'::date,NULL,NULL),
  ('Bruni Giovanni','Giovanni Bruni','CONVERSIONE/ABILITAZIONE EAV',NULL,NULL,'X'),
  ('Capasso Vincenzo','Vincenzo Capasso','CONVERSIONE/ABILITAZIONE FSE','2025-12-04'::date,NULL,'2025-12-02 00:00:00'),
  ('Capasso Vincenzo','Vincenzo Capasso','CONVERSIONE/ABILITAZIONE EAV',NULL,NULL,'X | X'),
  ('Cibuc Alexandru','Alexandru Cibuc','PROFILI RFI TE-DITTE 3 e 25kv (Mantenimento 3 Anni) (Rinnovo 6 anni)','2025-10-28'::date,'2027-12-31'::date,'2027-12-31 00:00:00 | 2027-12-31 00:00:00'),
  ('Di Cara Claudio','Claudio Di Cara','PROFILI RFI TE-DITTE 3 e 25kv (Mantenimento 3 Anni) (Rinnovo 6 anni)','2017-03-20'::date,'2023-12-31'::date,NULL),
  ('Di Cara Claudio','Claudio Di Cara','PROFILI RFI IS0 (Scadenza 5 anni)','2017-03-20'::date,'2022-12-31'::date,NULL),
  ('Federico Corinno','Corinno Federico','CONVERSIONE/ABILITAZIONE FSE',NULL,NULL,'X'),
  ('Federico Corinno','Corinno Federico','CONVERSIONE/ABILITAZIONE EAV',NULL,NULL,'X'),
  ('Guarnaschella Giuseppe','Giuseppe Guarnaschella','PROFILI RFI IS0 (Scadenza 5 anni)','2023-02-03'::date,'2028-12-31'::date,NULL),
  ('Guarnaschella Giuseppe','Giuseppe Guarnaschella','CONVERSIONE/ABILITAZIONE FSE','2025-12-04'::date,NULL,'2025-12-02 00:00:00'),
  ('Guarnaschella Giuseppe','Giuseppe Guarnaschella','CONVERSIONE/ABILITAZIONE EAV',NULL,NULL,'X'),
  ('Merli Andrea','Andrea Merli','CONVERSIONE/ABILITAZIONE FSE','2025-12-04'::date,NULL,NULL),
  ('Merli Andrea','Andrea Merli','CONVERSIONE/ABILITAZIONE EAV',NULL,NULL,'X'),
  ('Migliore Michele','Michele Migliore','CONVERSIONE/ABILITAZIONE FSE','2025-12-04'::date,NULL,NULL),
  ('Xhima Ardjan','Ardjan Xhima','PROFILI RFI TE-DITTE 3 e 25kv (Mantenimento 3 Anni) (Rinnovo 6 anni)','2024-02-04'::date,'2027-12-31'::date,NULL)
), matched AS (
  SELECT DISTINCT ON (s.full_cn, s.corso)
    p.id_uuid::text AS personale_id,
    s.corso,
    s.data_attestato,
    s.scadenza_attestato,
    s.note,
    CASE
      WHEN lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_cn), '\s+', ' ', 'g')) THEN 0
      ELSE 1
    END AS rank_match
  FROM src s
  JOIN public.personale p ON
       lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_cn), '\s+', ' ', 'g'))
    OR lower(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_nc), '\s+', ' ', 'g'))
  WHERE p.id_uuid IS NOT NULL AND trim(p.id_uuid::text) <> ''
  ORDER BY s.full_cn, s.corso, rank_match, p.id
)
INSERT INTO public.formazione_rfi_corsi(
  personale_id, corso, data_attestato, scadenza_attestato, note, updated_at
)
SELECT personale_id, corso, data_attestato, scadenza_attestato, note, now()
FROM matched
ON CONFLICT (personale_id, corso)
DO UPDATE SET
  data_attestato = EXCLUDED.data_attestato,
  scadenza_attestato = EXCLUDED.scadenza_attestato,
  note = EXCLUDED.note,
  updated_at = now();