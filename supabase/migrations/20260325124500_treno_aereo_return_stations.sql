-- Stazioni/Aeroporti di ritorno (possono differire dall'andata)

ALTER TABLE public.bookings_treno
  ADD COLUMN IF NOT EXISTS stazione_partenza_ritorno text,
  ADD COLUMN IF NOT EXISTS stazione_arrivo_ritorno text;

CREATE INDEX IF NOT EXISTS bookings_treno_stazione_partenza_ritorno_idx
  ON public.bookings_treno (stazione_partenza_ritorno);

CREATE INDEX IF NOT EXISTS bookings_treno_stazione_arrivo_ritorno_idx
  ON public.bookings_treno (stazione_arrivo_ritorno);

ALTER TABLE public.bookings_aereo
  ADD COLUMN IF NOT EXISTS aeroporto_partenza_ritorno text,
  ADD COLUMN IF NOT EXISTS aeroporto_arrivo_ritorno text;

CREATE INDEX IF NOT EXISTS bookings_aereo_aeroporto_partenza_ritorno_idx
  ON public.bookings_aereo (aeroporto_partenza_ritorno);

CREATE INDEX IF NOT EXISTS bookings_aereo_aeroporto_arrivo_ritorno_idx
  ON public.bookings_aereo (aeroporto_arrivo_ritorno);

