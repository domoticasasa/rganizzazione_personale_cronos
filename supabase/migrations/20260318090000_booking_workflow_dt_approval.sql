-- Workflow richieste (user -> DT -> admin) per treni/aerei
-- Stati:
-- - INVIATA_AL_DT: richiesta creata da dipendente/user, visibile solo al DT assegnato
-- - RIFIUTATA_DAL_DT: rifiutata dal DT (opzionale motivo)
-- - INVIATA_ADMIN: approvata dal DT e inoltrata agli admin_type=3
--
-- NB: per compatibilità con dati esistenti, default = INVIATA_ADMIN.

DO $$
BEGIN
  -- === TRENI ===
  ALTER TABLE public.bookings_treno
    ADD COLUMN IF NOT EXISTS workflow_status text NOT NULL DEFAULT 'INVIATA_ADMIN',
    ADD COLUMN IF NOT EXISTS requested_by_user_id integer NULL,
    ADD COLUMN IF NOT EXISTS assigned_dt_user_uuid uuid NULL,
    ADD COLUMN IF NOT EXISTS dt_decision_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS dt_reject_reason text NULL;

  -- FK: requested_by_user_id -> users.id
  BEGIN
    ALTER TABLE public.bookings_treno
      ADD CONSTRAINT bookings_treno_requested_by_user_id_fkey
      FOREIGN KEY (requested_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  -- FK: assigned_dt_user_uuid -> users.id_uuid
  BEGIN
    ALTER TABLE public.bookings_treno
      ADD CONSTRAINT bookings_treno_assigned_dt_user_uuid_fkey
      FOREIGN KEY (assigned_dt_user_uuid) REFERENCES public.users(id_uuid) ON DELETE SET NULL;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  -- CHECK: workflow_status values
  BEGIN
    ALTER TABLE public.bookings_treno
      ADD CONSTRAINT bookings_treno_workflow_status_check
      CHECK (workflow_status IN ('INVIATA_AL_DT','RIFIUTATA_DAL_DT','INVIATA_ADMIN'));
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  CREATE INDEX IF NOT EXISTS bookings_treno_workflow_status_idx
    ON public.bookings_treno (workflow_status);
  CREATE INDEX IF NOT EXISTS bookings_treno_assigned_dt_user_uuid_idx
    ON public.bookings_treno (assigned_dt_user_uuid);

  -- === AEREI ===
  ALTER TABLE public.bookings_aereo
    ADD COLUMN IF NOT EXISTS workflow_status text NOT NULL DEFAULT 'INVIATA_ADMIN',
    ADD COLUMN IF NOT EXISTS requested_by_user_id integer NULL,
    ADD COLUMN IF NOT EXISTS assigned_dt_user_uuid uuid NULL,
    ADD COLUMN IF NOT EXISTS dt_decision_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS dt_reject_reason text NULL;

  BEGIN
    ALTER TABLE public.bookings_aereo
      ADD CONSTRAINT bookings_aereo_requested_by_user_id_fkey
      FOREIGN KEY (requested_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER TABLE public.bookings_aereo
      ADD CONSTRAINT bookings_aereo_assigned_dt_user_uuid_fkey
      FOREIGN KEY (assigned_dt_user_uuid) REFERENCES public.users(id_uuid) ON DELETE SET NULL;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER TABLE public.bookings_aereo
      ADD CONSTRAINT bookings_aereo_workflow_status_check
      CHECK (workflow_status IN ('INVIATA_AL_DT','RIFIUTATA_DAL_DT','INVIATA_ADMIN'));
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  CREATE INDEX IF NOT EXISTS bookings_aereo_workflow_status_idx
    ON public.bookings_aereo (workflow_status);
  CREATE INDEX IF NOT EXISTS bookings_aereo_assigned_dt_user_uuid_idx
    ON public.bookings_aereo (assigned_dt_user_uuid);
END $$;

