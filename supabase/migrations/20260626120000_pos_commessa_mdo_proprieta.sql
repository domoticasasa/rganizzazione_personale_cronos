-- Elenco MdO (proprietà / noleggio) in POS per commessa — import allegato 02.2.

CREATE TABLE IF NOT EXISTS public.pos_commessa_mdo_proprieta_lista_meta (
  commessa_id uuid PRIMARY KEY REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  data_ultimo_aggiornamento date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.pos_commessa_mdo_proprieta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commessa_id uuid NOT NULL REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  mdo_id uuid NOT NULL REFERENCES public.logistica_mdo_proprieta (id_uuid) ON DELETE CASCADE,
  codifica_import text,
  targa_import text,
  descrizione_import text,
  proprieta_import text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL,
  UNIQUE (commessa_id, mdo_id)
);

CREATE INDEX IF NOT EXISTS pos_commessa_mdo_proprieta_commessa_idx
  ON public.pos_commessa_mdo_proprieta (commessa_id);

CREATE INDEX IF NOT EXISTS pos_commessa_mdo_proprieta_mdo_idx
  ON public.pos_commessa_mdo_proprieta (mdo_id);

DROP TRIGGER IF EXISTS trg_pos_commessa_mdo_proprieta_updated_at ON public.pos_commessa_mdo_proprieta;
CREATE TRIGGER trg_pos_commessa_mdo_proprieta_updated_at
BEFORE UPDATE ON public.pos_commessa_mdo_proprieta
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

INSERT INTO public.app_page_registry (page_key, label, active)
VALUES ('pos_mdo_proprieta_lista', 'Elenco MdO POS', true)
ON CONFLICT (page_key) DO UPDATE
SET label = excluded.label,
    active = true;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mdo_proprieta_lista_meta TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mdo_proprieta TO authenticated;

ALTER TABLE public.pos_commessa_mdo_proprieta_lista_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_commessa_mdo_proprieta ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mdo_proprieta_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_user()
      OR public.has_custom_page_access('pos_mdo_proprieta_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mdo_proprieta_user() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mdo_proprieta_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_manager()
      OR public.has_custom_page_access('pos_mdo_proprieta_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mdo_proprieta_manager() TO authenticated;

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_lista_meta_select ON public.pos_commessa_mdo_proprieta_lista_meta;
CREATE POLICY pos_commessa_mdo_proprieta_lista_meta_select
ON public.pos_commessa_mdo_proprieta_lista_meta FOR SELECT TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_user());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_lista_meta_insert ON public.pos_commessa_mdo_proprieta_lista_meta;
CREATE POLICY pos_commessa_mdo_proprieta_lista_meta_insert
ON public.pos_commessa_mdo_proprieta_lista_meta FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mdo_proprieta_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_lista_meta_update ON public.pos_commessa_mdo_proprieta_lista_meta;
CREATE POLICY pos_commessa_mdo_proprieta_lista_meta_update
ON public.pos_commessa_mdo_proprieta_lista_meta FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_manager())
WITH CHECK (public.is_pos_commessa_mdo_proprieta_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_lista_meta_delete ON public.pos_commessa_mdo_proprieta_lista_meta;
CREATE POLICY pos_commessa_mdo_proprieta_lista_meta_delete
ON public.pos_commessa_mdo_proprieta_lista_meta FOR DELETE TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_select ON public.pos_commessa_mdo_proprieta;
CREATE POLICY pos_commessa_mdo_proprieta_select
ON public.pos_commessa_mdo_proprieta FOR SELECT TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_user());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_insert ON public.pos_commessa_mdo_proprieta;
CREATE POLICY pos_commessa_mdo_proprieta_insert
ON public.pos_commessa_mdo_proprieta FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mdo_proprieta_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_update ON public.pos_commessa_mdo_proprieta;
CREATE POLICY pos_commessa_mdo_proprieta_update
ON public.pos_commessa_mdo_proprieta FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_manager())
WITH CHECK (public.is_pos_commessa_mdo_proprieta_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_proprieta_delete ON public.pos_commessa_mdo_proprieta;
CREATE POLICY pos_commessa_mdo_proprieta_delete
ON public.pos_commessa_mdo_proprieta FOR DELETE TO authenticated
USING (public.is_pos_commessa_mdo_proprieta_manager());
