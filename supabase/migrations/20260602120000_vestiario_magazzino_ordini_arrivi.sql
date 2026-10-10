-- Ordini e arrivi materiale vestiario.

ALTER TABLE public.vestiario_magazzino
  ADD COLUMN IF NOT EXISTS quantita_ordinata integer NOT NULL DEFAULT 0
    CHECK (quantita_ordinata >= 0),
  ADD COLUMN IF NOT EXISTS quantita_arrivata_totale integer NOT NULL DEFAULT 0
    CHECK (quantita_arrivata_totale >= 0);

-- Registra un arrivo: incrementa magazzino e totale arrivato, scala l'ordinato in sospeso.
CREATE OR REPLACE FUNCTION public.vestiario_magazzino_registra_arrivo(
  p_stagione text,
  p_articolo text,
  p_taglia text,
  p_quantita integer
)
RETURNS TABLE(
  quantita_magazzino integer,
  quantita_ordinata integer,
  quantita_arrivata_totale integer
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_mag integer;
  v_ord integer;
  v_arr integer;
BEGIN
  IF p_quantita IS NULL OR p_quantita <= 0 THEN
    RETURN;
  END IF;

  IF p_stagione NOT IN ('estivo', 'invernale') THEN
    RAISE EXCEPTION 'Stagione non valida: %', p_stagione;
  END IF;

  INSERT INTO public.vestiario_magazzino (
    stagione, articolo, taglia, quantita, quantita_ordinata, quantita_arrivata_totale
  )
  VALUES (p_stagione, p_articolo, p_taglia, 0, 0, 0)
  ON CONFLICT (stagione, articolo, taglia) DO NOTHING;

  SELECT m.quantita, m.quantita_ordinata, m.quantita_arrivata_totale
  INTO v_mag, v_ord, v_arr
  FROM public.vestiario_magazzino m
  WHERE m.stagione = p_stagione
    AND m.articolo = p_articolo
    AND m.taglia = p_taglia
  FOR UPDATE;

  v_mag := COALESCE(v_mag, 0) + p_quantita;
  v_arr := COALESCE(v_arr, 0) + p_quantita;
  v_ord := GREATEST(0, COALESCE(v_ord, 0) - p_quantita);

  UPDATE public.vestiario_magazzino m
  SET
    quantita = v_mag,
    quantita_ordinata = v_ord,
    quantita_arrivata_totale = v_arr
  WHERE m.stagione = p_stagione
    AND m.articolo = p_articolo
    AND m.taglia = p_taglia;

  quantita_magazzino := v_mag;
  quantita_ordinata := v_ord;
  quantita_arrivata_totale := v_arr;
  RETURN NEXT;
END;
$$;
