-- Struttura dati RFI importata da Excel (solo sorgente import, non UI Excel).
CREATE TABLE IF NOT EXISTS public.formazione_rfi_records (
  id bigserial PRIMARY KEY,
  personale_id integer NOT NULL,
  track_key text NOT NULL,
  field_key text NOT NULL,
  value_date date,
  source_file text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS formazione_rfi_records_personale_idx
  ON public.formazione_rfi_records(personale_id);

CREATE INDEX IF NOT EXISTS formazione_rfi_records_track_field_idx
  ON public.formazione_rfi_records(track_key, field_key);

CREATE UNIQUE INDEX IF NOT EXISTS formazione_rfi_records_unique_cell
  ON public.formazione_rfi_records(personale_id, track_key, field_key);
