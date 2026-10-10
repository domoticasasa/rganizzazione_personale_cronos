-- DPI: aggiunge data_consegna e data_revisione
-- e aggiorna il vincolo categoria con "Cordino Shock Absorber Doppio".

ALTER TABLE public.dpi_dotazioni
  ADD COLUMN IF NOT EXISTS data_consegna date,
  ADD COLUMN IF NOT EXISTS data_revisione date;

ALTER TABLE public.dpi_dotazioni
  DROP CONSTRAINT IF EXISTS dpi_dotazioni_categoria_check;

ALTER TABLE public.dpi_dotazioni
  ADD CONSTRAINT dpi_dotazioni_categoria_check CHECK (
    categoria IN (
      'Elmetto',
      'Imbracatura',
      'Cordino',
      'Cordino Shock Absorber Doppio',
      'Guanti',
      'Occhiali',
      'Scarpe'
    )
  );

