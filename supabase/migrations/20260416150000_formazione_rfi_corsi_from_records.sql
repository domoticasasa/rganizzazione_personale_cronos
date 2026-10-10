-- Tabella RFI con schema compatibile UI "Formazione".
CREATE TABLE IF NOT EXISTS public.formazione_rfi_corsi (
  id bigserial PRIMARY KEY,
  personale_id text NOT NULL,
  corso text NOT NULL,
  ente text,
  primo_rilascio_aggiornamento text,
  data_attestato date,
  scadenza_attestato date,
  prima_data date,
  oda text,
  orario text,
  modalita text,
  struttura_link text,
  note text,
  dimessi text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS formazione_rfi_corsi_personale_idx
  ON public.formazione_rfi_corsi(personale_id);

CREATE INDEX IF NOT EXISTS formazione_rfi_corsi_corso_idx
  ON public.formazione_rfi_corsi(corso);

CREATE UNIQUE INDEX IF NOT EXISTS formazione_rfi_corsi_unique_person_course
  ON public.formazione_rfi_corsi(personale_id, corso);

-- Import/aggiornamento da formazione_rfi_records (già popolata da Excel aaa.xlsx).
WITH normalized AS (
  SELECT
    p.id_uuid AS personale_uuid,
    fr.track_key,
    fr.field_key,
    fr.value_date,
    fr.value_text
  FROM public.formazione_rfi_records fr
  JOIN public.personale p ON p.id = fr.personale_id
  WHERE p.id_uuid IS NOT NULL
    AND trim(p.id_uuid::text) <> ''
),
grouped AS (
  SELECT
    personale_uuid,
    track_key,
    min(value_date) FILTER (
      WHERE field_key IN ('data_attestato', 'definizione', 'data_consegna')
    ) AS data_attestato,
    max(value_date) FILTER (
      WHERE field_key IN ('scadenza', 'prossima_scadenza', 'rinnovo', 'data_sacdenza_verifica_annuale')
    ) AS scadenza_attestato,
    string_agg(
      DISTINCT value_text,
      ' | '
    ) FILTER (
      WHERE value_text IS NOT NULL
        AND trim(value_text) <> ''
        AND (value_date IS NULL)
        AND field_key NOT IN ('data_attestato', 'definizione', 'data_consegna', 'scadenza', 'prossima_scadenza', 'rinnovo', 'data_sacdenza_verifica_annuale')
    ) AS note_raw
  FROM normalized
  GROUP BY personale_uuid, track_key
),
mapped AS (
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
  personale_id,
  corso,
  data_attestato,
  scadenza_attestato,
  note,
  updated_at
)
SELECT
  personale_id,
  corso,
  data_attestato,
  scadenza_attestato,
  note,
  now()
FROM mapped
ON CONFLICT (personale_id, corso)
DO UPDATE SET
  data_attestato = EXCLUDED.data_attestato,
  scadenza_attestato = EXCLUDED.scadenza_attestato,
  note = EXCLUDED.note,
  updated_at = now();
