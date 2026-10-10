CREATE TABLE IF NOT EXISTS public.personale_taglie (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  personale_id uuid NOT NULL REFERENCES public.personale(id_uuid) ON DELETE CASCADE,
  taglia_tshirt text,
  taglia_pantalone text,
  taglia_felpa text,
  taglia_giacca text,
  taglia_gilet text,
  taglia_scarpe text,
  taglia_guanti text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT personale_taglie_personale_unique UNIQUE (personale_id)
);

CREATE INDEX IF NOT EXISTS personale_taglie_personale_idx
  ON public.personale_taglie (personale_id);

DROP TRIGGER IF EXISTS trg_personale_taglie_updated_at ON public.personale_taglie;
CREATE TRIGGER trg_personale_taglie_updated_at
BEFORE UPDATE ON public.personale_taglie
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

