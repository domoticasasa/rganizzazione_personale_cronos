-- Split old role=admin into dedicated roles.
-- Mapping:
-- admin_type=1 -> admin_generale
-- admin_type=2 -> admin_pernottamenti
-- admin_type=3 -> admin_trenoaereo

UPDATE public.users
SET role = CASE
  WHEN COALESCE(admin_type, 1) = 2 THEN 'admin_pernottamenti'
  WHEN COALESCE(admin_type, 1) = 3 THEN 'admin_trenoaereo'
  ELSE 'admin_generale'
END
WHERE role = 'admin';

COMMENT ON COLUMN public.users.role IS
'Ruoli applicativi: admin_generale, admin_pernottamenti, admin_trenoaereo, dt, assistente_dt, caposquadra, user, dipendente.';
