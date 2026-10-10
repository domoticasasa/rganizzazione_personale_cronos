-- Squadre per pernottamenti: nome + batch di personale

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Tabella
CREATE TABLE IF NOT EXISTS public.pernotti_squads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dt_user_uuid uuid NOT NULL REFERENCES public.users(id_uuid) ON DELETE CASCADE,
  nome text NOT NULL,
  personale_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pernotti_squads_dt_user_uuid_idx
  ON public.pernotti_squads (dt_user_uuid);

-- updated_at (semplice trigger)
CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_pernotti_squads_updated_at ON public.pernotti_squads;
CREATE TRIGGER trg_pernotti_squads_updated_at
BEFORE UPDATE ON public.pernotti_squads
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

-- RLS
ALTER TABLE public.pernotti_squads ENABLE ROW LEVEL SECURITY;

-- DT: vede/crea/modifica le sue squadre
DO $$
BEGIN
  CREATE POLICY pernotti_squads_dt_select
  ON public.pernotti_squads
  FOR SELECT
  USING (
    dt_user_uuid = (
      SELECT u.id_uuid
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
  CREATE POLICY pernotti_squads_dt_insert
  ON public.pernotti_squads
  FOR INSERT
  WITH CHECK (
    dt_user_uuid = (
      SELECT u.id_uuid
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
  CREATE POLICY pernotti_squads_dt_update
  ON public.pernotti_squads
  FOR UPDATE
  USING (
    dt_user_uuid = (
      SELECT u.id_uuid
      FROM public.users u
      WHERE u.auth_id = auth.uid()
        AND u.role = 'dt'
    )
  )
  WITH CHECK (
    dt_user_uuid = (
      SELECT u.id_uuid
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
  CREATE POLICY pernotti_squads_dt_delete
  ON public.pernotti_squads
  FOR DELETE
  USING (
    dt_user_uuid = (
      SELECT u.id_uuid
      FROM public.users u
      WHERE u.auth_id = auth.uid()
        AND u.role = 'dt'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

