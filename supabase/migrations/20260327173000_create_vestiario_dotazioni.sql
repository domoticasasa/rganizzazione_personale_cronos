CREATE TABLE IF NOT EXISTS public.vestiario_dotazioni (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  personale_id uuid NOT NULL REFERENCES public.personale(id_uuid) ON DELETE CASCADE,
  categoria text NOT NULL,
  quantita_assegnata integer NOT NULL DEFAULT 0 CHECK (quantita_assegnata >= 0),
  taglia text,
  matricola text,
  scadenza date,
  marca text,
  data_produzione date,
  modello text,
  fornitore text,
  data_consegna date,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vestiario_dotazioni_personale_idx
  ON public.vestiario_dotazioni (personale_id);

CREATE INDEX IF NOT EXISTS vestiario_dotazioni_categoria_idx
  ON public.vestiario_dotazioni (categoria);

CREATE INDEX IF NOT EXISTS vestiario_dotazioni_created_at_idx
  ON public.vestiario_dotazioni (created_at DESC);

DROP TRIGGER IF EXISTS trg_vestiario_dotazioni_updated_at ON public.vestiario_dotazioni;
CREATE TRIGGER trg_vestiario_dotazioni_updated_at
BEFORE UPDATE ON public.vestiario_dotazioni
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

