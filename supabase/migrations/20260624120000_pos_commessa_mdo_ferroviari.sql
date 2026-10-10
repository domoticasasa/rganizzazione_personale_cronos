-- Elenco MdO ferroviari in POS per commessa — import allegato 02.3.

CREATE TABLE IF NOT EXISTS public.pos_commessa_mdo_lista_meta (
  commessa_id uuid PRIMARY KEY REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  data_ultimo_aggiornamento date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.pos_commessa_mdo_ferroviari (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commessa_id uuid NOT NULL REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  mdo_id uuid NOT NULL REFERENCES public.logistica_mdo_ferroviari (id_uuid) ON DELETE CASCADE,
  codifica_import text,
  targa_import text,
  descrizione_import text,
  proprieta_import text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL,
  UNIQUE (commessa_id, mdo_id)
);

CREATE INDEX IF NOT EXISTS pos_commessa_mdo_ferroviari_commessa_idx
  ON public.pos_commessa_mdo_ferroviari (commessa_id);

CREATE INDEX IF NOT EXISTS pos_commessa_mdo_ferroviari_mdo_idx
  ON public.pos_commessa_mdo_ferroviari (mdo_id);

DROP TRIGGER IF EXISTS trg_pos_commessa_mdo_ferroviari_updated_at ON public.pos_commessa_mdo_ferroviari;
CREATE TRIGGER trg_pos_commessa_mdo_ferroviari_updated_at
BEFORE UPDATE ON public.pos_commessa_mdo_ferroviari
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

INSERT INTO public.app_page_registry (page_key, label, active)
VALUES ('pos_mdo_ferroviari_lista', 'Elenco MdO Ferroviari POS', true)
ON CONFLICT (page_key) DO UPDATE
SET label = excluded.label,
    active = true;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mdo_lista_meta TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mdo_ferroviari TO authenticated;

ALTER TABLE public.pos_commessa_mdo_lista_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_commessa_mdo_ferroviari ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mdo_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_user()
      OR public.has_custom_page_access('pos_mdo_ferroviari_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mdo_user() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mdo_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_manager()
      OR public.has_custom_page_access('pos_mdo_ferroviari_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mdo_manager() TO authenticated;

DROP POLICY IF EXISTS pos_commessa_mdo_lista_meta_select ON public.pos_commessa_mdo_lista_meta;
CREATE POLICY pos_commessa_mdo_lista_meta_select
ON public.pos_commessa_mdo_lista_meta FOR SELECT TO authenticated
USING (public.is_pos_commessa_mdo_user());

DROP POLICY IF EXISTS pos_commessa_mdo_lista_meta_insert ON public.pos_commessa_mdo_lista_meta;
CREATE POLICY pos_commessa_mdo_lista_meta_insert
ON public.pos_commessa_mdo_lista_meta FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mdo_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_lista_meta_update ON public.pos_commessa_mdo_lista_meta;
CREATE POLICY pos_commessa_mdo_lista_meta_update
ON public.pos_commessa_mdo_lista_meta FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mdo_manager())
WITH CHECK (public.is_pos_commessa_mdo_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_lista_meta_delete ON public.pos_commessa_mdo_lista_meta;
CREATE POLICY pos_commessa_mdo_lista_meta_delete
ON public.pos_commessa_mdo_lista_meta FOR DELETE TO authenticated
USING (public.is_pos_commessa_mdo_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_ferroviari_select ON public.pos_commessa_mdo_ferroviari;
CREATE POLICY pos_commessa_mdo_ferroviari_select
ON public.pos_commessa_mdo_ferroviari FOR SELECT TO authenticated
USING (public.is_pos_commessa_mdo_user());

DROP POLICY IF EXISTS pos_commessa_mdo_ferroviari_insert ON public.pos_commessa_mdo_ferroviari;
CREATE POLICY pos_commessa_mdo_ferroviari_insert
ON public.pos_commessa_mdo_ferroviari FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mdo_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_ferroviari_update ON public.pos_commessa_mdo_ferroviari;
CREATE POLICY pos_commessa_mdo_ferroviari_update
ON public.pos_commessa_mdo_ferroviari FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mdo_manager())
WITH CHECK (public.is_pos_commessa_mdo_manager());

DROP POLICY IF EXISTS pos_commessa_mdo_ferroviari_delete ON public.pos_commessa_mdo_ferroviari;
CREATE POLICY pos_commessa_mdo_ferroviari_delete
ON public.pos_commessa_mdo_ferroviari FOR DELETE TO authenticated
USING (public.is_pos_commessa_mdo_manager());
