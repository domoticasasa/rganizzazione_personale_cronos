-- Workflow "richiesta modifica" per pernottamenti (tabella public.bookings)
-- DT può proporre modifiche; Admin può confermare/applicare.

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS modifica_payload jsonb,
  ADD COLUMN IF NOT EXISTS modifica_note text,
  ADD COLUMN IF NOT EXISTS modifica_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS modifica_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS modifica_confirmed_by integer;

CREATE INDEX IF NOT EXISTS bookings_modifica_requested_at_idx
  ON public.bookings (modifica_requested_at);

