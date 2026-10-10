-- Inventario magazzino vestiario (per stagione, articolo e taglia).

CREATE TABLE IF NOT EXISTS public.vestiario_magazzino (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stagione text NOT NULL CHECK (stagione IN ('estivo', 'invernale')),
  articolo text NOT NULL,
  taglia text NOT NULL,
  quantita integer NOT NULL DEFAULT 0 CHECK (quantita >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (stagione, articolo, taglia)
);

CREATE INDEX IF NOT EXISTS vestiario_magazzino_stagione_idx
  ON public.vestiario_magazzino (stagione);

CREATE INDEX IF NOT EXISTS vestiario_magazzino_articolo_idx
  ON public.vestiario_magazzino (articolo);

DROP TRIGGER IF EXISTS trg_vestiario_magazzino_updated_at ON public.vestiario_magazzino;
CREATE TRIGGER trg_vestiario_magazzino_updated_at
BEFORE UPDATE ON public.vestiario_magazzino
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

-- Scarico atomico da assegnazioni (non scende sotto zero).
CREATE OR REPLACE FUNCTION public.vestiario_magazzino_scarica(
  p_stagione text,
  p_articolo text,
  p_taglia text,
  p_quantita integer
)
RETURNS TABLE(quantita_residua integer, insufficiente boolean)
LANGUAGE plpgsql
AS $$
DECLARE
  v_old integer;
  v_new integer;
BEGIN
  IF p_quantita IS NULL OR p_quantita <= 0 THEN
    RETURN;
  END IF;

  IF p_stagione NOT IN ('estivo', 'invernale') THEN
    RAISE EXCEPTION 'Stagione non valida: %', p_stagione;
  END IF;

  INSERT INTO public.vestiario_magazzino (stagione, articolo, taglia, quantita)
  VALUES (p_stagione, p_articolo, p_taglia, 0)
  ON CONFLICT (stagione, articolo, taglia) DO NOTHING;

  SELECT m.quantita INTO v_old
  FROM public.vestiario_magazzino m
  WHERE m.stagione = p_stagione
    AND m.articolo = p_articolo
    AND m.taglia = p_taglia
  FOR UPDATE;

  v_old := COALESCE(v_old, 0);
  v_new := GREATEST(0, v_old - p_quantita);

  UPDATE public.vestiario_magazzino m
  SET quantita = v_new
  WHERE m.stagione = p_stagione
    AND m.articolo = p_articolo
    AND m.taglia = p_taglia;

  quantita_residua := v_new;
  insufficiente := v_old < p_quantita;
  RETURN NEXT;
END;
$$;
