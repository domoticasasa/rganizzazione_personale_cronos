-- A / A-R support for train and flight bookings

DO $$
BEGIN
  -- =========================
  -- TRENI
  -- =========================
  ALTER TABLE public.bookings_treno
    ADD COLUMN IF NOT EXISTS viaggio_tipo text NOT NULL DEFAULT 'A',
    ADD COLUMN IF NOT EXISTS data_ritorno date NULL,
    ADD COLUMN IF NOT EXISTS orario_ritorno text NULL;

  BEGIN
    ALTER TABLE public.bookings_treno
      ADD CONSTRAINT bookings_treno_viaggio_tipo_check
      CHECK (viaggio_tipo IN ('A', 'AR'));
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  -- Se viaggio è A (solo andata), i campi ritorno devono essere null.
  BEGIN
    ALTER TABLE public.bookings_treno
      ADD CONSTRAINT bookings_treno_ritorno_consistency_check
      CHECK (
        (viaggio_tipo = 'A' AND data_ritorno IS NULL AND orario_ritorno IS NULL)
        OR
        (viaggio_tipo = 'AR' AND data_ritorno IS NOT NULL AND orario_ritorno IS NOT NULL)
      );
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  CREATE INDEX IF NOT EXISTS bookings_treno_viaggio_tipo_idx
    ON public.bookings_treno (viaggio_tipo);

  -- =========================
  -- AEREI
  -- =========================
  ALTER TABLE public.bookings_aereo
    ADD COLUMN IF NOT EXISTS viaggio_tipo text NOT NULL DEFAULT 'A',
    ADD COLUMN IF NOT EXISTS data_ritorno date NULL,
    ADD COLUMN IF NOT EXISTS orario_ritorno text NULL;

  BEGIN
    ALTER TABLE public.bookings_aereo
      ADD CONSTRAINT bookings_aereo_viaggio_tipo_check
      CHECK (viaggio_tipo IN ('A', 'AR'));
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER TABLE public.bookings_aereo
      ADD CONSTRAINT bookings_aereo_ritorno_consistency_check
      CHECK (
        (viaggio_tipo = 'A' AND data_ritorno IS NULL AND orario_ritorno IS NULL)
        OR
        (viaggio_tipo = 'AR' AND data_ritorno IS NOT NULL AND orario_ritorno IS NOT NULL)
      );
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  CREATE INDEX IF NOT EXISTS bookings_aereo_viaggio_tipo_idx
    ON public.bookings_aereo (viaggio_tipo);
END $$;

