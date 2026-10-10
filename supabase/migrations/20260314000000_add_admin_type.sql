-- 1=admin senza notifiche, 2=admin pernottamenti, 3=admin treni/aerei (stesso ruolo)
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS admin_type smallint DEFAULT 1;

COMMENT ON COLUMN public.users.admin_type IS '1=no notifiche, 2=pernottamenti, 3=treni/aerei';
