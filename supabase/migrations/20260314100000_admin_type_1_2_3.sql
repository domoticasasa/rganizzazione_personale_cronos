-- Correzione schema admin_type: 1=no notifiche, 2=pernottamenti, 3=treni/aerei
-- Converti valori vecchi (1=treni, 2=aerei, 3=pernottamenti, 4=no notifiche) in nuovo schema
UPDATE public.users
SET admin_type = CASE
  WHEN admin_type = 4 OR admin_type IS NULL THEN 1
  WHEN admin_type = 1 OR admin_type = 2 THEN 3
  WHEN admin_type = 3 THEN 2
  ELSE 1
END
WHERE role = 'admin';

ALTER TABLE public.users ALTER COLUMN admin_type SET DEFAULT 1;
COMMENT ON COLUMN public.users.admin_type IS '1=no notifiche, 2=pernottamenti, 3=treni/aerei';
