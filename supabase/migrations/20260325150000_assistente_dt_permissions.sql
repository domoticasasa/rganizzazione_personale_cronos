-- Permessi concessi da un DT agli Assistenti DT
-- DT (grantor_dt_user_*) concede accesso a uno o più Assistenti (assistant_user_id)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.assistente_dt_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- DT che concede (grantor)
  grantor_dt_user_id   integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  grantor_dt_user_uuid uuid    NOT NULL REFERENCES public.users(id_uuid) ON DELETE CASCADE,

  -- Assistente a cui viene concesso
  assistant_user_id integer NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (grantor_dt_user_id, assistant_user_id)
);

CREATE INDEX IF NOT EXISTS assistente_dt_permissions_assistant_idx
  ON public.assistente_dt_permissions (assistant_user_id);

CREATE INDEX IF NOT EXISTS assistente_dt_permissions_grantor_idx
  ON public.assistente_dt_permissions (grantor_dt_user_id);

