-- Dotazioni DPI assegnate al personale
-- Campi richiesti: categoria, quantita assegnata, marca, data produzione, matricola, modello

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.dpi_dotazioni (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  personale_id uuid NOT NULL REFERENCES public.personale(id_uuid) ON DELETE CASCADE,
  categoria text NOT NULL,
  quantita_assegnata integer NOT NULL DEFAULT 1 CHECK (quantita_assegnata >= 0),
  marca text,
  data_produzione date,
  matricola text,
  modello text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dpi_dotazioni_categoria_check CHECK (
    categoria IN ('Elmetto', 'Imbracatura', 'Cordino', 'Guanti', 'Occhiali', 'Scarpe')
  ),
  CONSTRAINT dpi_dotazioni_matricola_unique UNIQUE (matricola)
);

CREATE INDEX IF NOT EXISTS dpi_dotazioni_personale_idx
  ON public.dpi_dotazioni (personale_id);

CREATE INDEX IF NOT EXISTS dpi_dotazioni_categoria_idx
  ON public.dpi_dotazioni (categoria);

-- Trigger updated_at riutilizzando helper già presente nel progetto.
DROP TRIGGER IF EXISTS trg_dpi_dotazioni_updated_at ON public.dpi_dotazioni;
CREATE TRIGGER trg_dpi_dotazioni_updated_at
BEFORE UPDATE ON public.dpi_dotazioni
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

