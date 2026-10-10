-- Categorie DPI gestibili da app (dinamiche)

CREATE TABLE IF NOT EXISTS public.dpi_categories (
  name text PRIMARY KEY,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_dpi_categories_updated_at ON public.dpi_categories;
CREATE TRIGGER trg_dpi_categories_updated_at
BEFORE UPDATE ON public.dpi_categories
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

ALTER TABLE public.dpi_dotazioni
  DROP CONSTRAINT IF EXISTS dpi_dotazioni_categoria_check;

INSERT INTO public.dpi_categories (name, active)
VALUES
  ('Elmetto', true),
  ('Imbracatura', true),
  ('Cordino', true),
  ('Cordino Shock Absorber Doppio', true),
  ('Guanti', true),
  ('Occhiali', true),
  ('Scarpe', true)
ON CONFLICT (name) DO UPDATE
SET active = EXCLUDED.active;

