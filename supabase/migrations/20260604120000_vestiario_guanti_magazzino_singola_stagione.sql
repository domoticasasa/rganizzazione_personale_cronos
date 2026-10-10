-- Guanti: un solo stock (stagione invernale). Unisce eventuali righe estive e rimuove i duplicati.

INSERT INTO public.vestiario_magazzino (
  stagione,
  articolo,
  taglia,
  quantita,
  quantita_ordinata,
  quantita_arrivata_totale
)
SELECT
  'invernale',
  e.articolo,
  e.taglia,
  e.quantita,
  e.quantita_ordinata,
  e.quantita_arrivata_totale
FROM public.vestiario_magazzino e
WHERE e.articolo = 'guanti'
  AND e.stagione = 'estivo'
ON CONFLICT (stagione, articolo, taglia) DO UPDATE SET
  quantita = public.vestiario_magazzino.quantita + EXCLUDED.quantita,
  quantita_ordinata = public.vestiario_magazzino.quantita_ordinata + EXCLUDED.quantita_ordinata,
  quantita_arrivata_totale = public.vestiario_magazzino.quantita_arrivata_totale + EXCLUDED.quantita_arrivata_totale,
  updated_at = now();

DELETE FROM public.vestiario_magazzino
WHERE articolo = 'guanti'
  AND stagione = 'estivo';
