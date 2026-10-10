-- RLS per assisitente_dt_permissions

ALTER TABLE public.assistente_dt_permissions ENABLE ROW LEVEL SECURITY;

-- Helper: id interno dell'utente corrente
-- (Supabase auth.uid() è uuid dell'utente Auth)

-- DT può leggere/gestire (grantor_dt_user_id = current users.id)
DO $$
BEGIN
  CREATE POLICY assistente_dt_permissions_dt_select
  ON public.assistente_dt_permissions
  FOR SELECT
  TO authenticated
  USING (
    grantor_dt_user_id = (
      SELECT u.id
      FROM public.users u
      WHERE u.auth_id = auth.uid()
        AND u.role = 'dt'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY assistente_dt_permissions_dt_insert
  ON public.assistente_dt_permissions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    grantor_dt_user_id = (
      SELECT u.id
      FROM public.users u
      WHERE u.auth_id = auth.uid()
        AND u.role = 'dt'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY assistente_dt_permissions_dt_delete
  ON public.assistente_dt_permissions
  FOR DELETE
  TO authenticated
  USING (
    grantor_dt_user_id = (
      SELECT u.id
      FROM public.users u
      WHERE u.auth_id = auth.uid()
        AND u.role = 'dt'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- Assistente può leggere i permessi a lui destinati (assistant_user_id = current users.id)
DO $$
BEGIN
  CREATE POLICY assistente_dt_permissions_assistant_select
  ON public.assistente_dt_permissions
  FOR SELECT
  TO authenticated
  USING (
    assistant_user_id = (
      SELECT u.id
      FROM public.users u
      WHERE u.auth_id = auth.uid()
    )
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

