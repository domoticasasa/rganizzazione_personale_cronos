ALTER TABLE public.dpi_dotazioni
  DROP CONSTRAINT IF EXISTS dpi_dotazioni_categoria_check;

ALTER TABLE public.dpi_dotazioni
  ADD CONSTRAINT dpi_dotazioni_categoria_check CHECK (
    categoria IN (
      'Elmetto',
      'Imbracatura',
      'Cordino',
      'Cordino Singolo con Dissipatore',
      'Cordino di Posizionamento',
      'Cordino Shock Absorber Doppio',
      'Guanti',
      'Occhiali',
      'Scarpe'
    )
  );

