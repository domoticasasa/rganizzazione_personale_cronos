-- Magazzino unificato: una sola riga stock per articolo+taglia (estivo, tranne guanti → invernale).
-- Unisce eventuali giacenze duplicate su stagione invernale nella riga canonica.

UPDATE public.vestiario_magazzino AS e
SET
  quantita = e.quantita + COALESCE(i.quantita, 0),
  quantita_ordinata = e.quantita_ordinata + COALESCE(i.quantita_ordinata, 0),
  quantita_arrivata_totale = e.quantita_arrivata_totale + COALESCE(i.quantita_arrivata_totale, 0)
FROM public.vestiario_magazzino AS i
WHERE e.stagione = 'estivo'
  AND i.stagione = 'invernale'
  AND e.articolo = i.articolo
  AND e.taglia = i.taglia
  AND e.articolo <> 'guanti'
  AND i.articolo <> 'guanti';

INSERT INTO public.vestiario_magazzino (
  stagione,
  articolo,
  taglia,
  quantita,
  quantita_ordinata,
  quantita_arrivata_totale
)
SELECT
  'estivo',
  i.articolo,
  i.taglia,
  i.quantita,
  i.quantita_ordinata,
  i.quantita_arrivata_totale
FROM public.vestiario_magazzino AS i
WHERE i.stagione = 'invernale'
  AND i.articolo <> 'guanti'
  AND NOT EXISTS (
    SELECT 1
    FROM public.vestiario_magazzino AS e
    WHERE e.stagione = 'estivo'
      AND e.articolo = i.articolo
      AND e.taglia = i.taglia
  );

DELETE FROM public.vestiario_magazzino
WHERE stagione = 'invernale'
  AND articolo <> 'guanti';
