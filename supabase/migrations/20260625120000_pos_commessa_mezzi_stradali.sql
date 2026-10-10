-- Elenco mezzi stradali in POS per commessa — import allegato 02.1.

CREATE TABLE IF NOT EXISTS public.pos_commessa_mezzi_stradali_lista_meta (
  commessa_id uuid PRIMARY KEY REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  data_ultimo_aggiornamento date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.pos_commessa_mezzi_stradali (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commessa_id uuid NOT NULL REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  mezzo_id uuid NOT NULL REFERENCES public.logistica_mezzi_stradali (id_uuid) ON DELETE CASCADE,
  codifica_import text,
  targa_import text,
  modello_import text,
  tipologia_import text,
  proprieta_import text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL,
  UNIQUE (commessa_id, mezzo_id)
);

CREATE INDEX IF NOT EXISTS pos_commessa_mezzi_stradali_commessa_idx
  ON public.pos_commessa_mezzi_stradali (commessa_id);

CREATE INDEX IF NOT EXISTS pos_commessa_mezzi_stradali_mezzo_idx
  ON public.pos_commessa_mezzi_stradali (mezzo_id);

DROP TRIGGER IF EXISTS trg_pos_commessa_mezzi_stradali_updated_at ON public.pos_commessa_mezzi_stradali;
CREATE TRIGGER trg_pos_commessa_mezzi_stradali_updated_at
BEFORE UPDATE ON public.pos_commessa_mezzi_stradali
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();

INSERT INTO public.app_page_registry (page_key, label, active)
VALUES ('pos_mezzi_stradali_lista', 'Elenco Mezzi Stradali POS', true)
ON CONFLICT (page_key) DO UPDATE
SET label = excluded.label,
    active = true;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mezzi_stradali_lista_meta TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_commessa_mezzi_stradali TO authenticated;

ALTER TABLE public.pos_commessa_mezzi_stradali_lista_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_commessa_mezzi_stradali ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mezzi_stradali_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_user()
      OR public.has_custom_page_access('pos_mezzi_stradali_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mezzi_stradali_user() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_pos_commessa_mezzi_stradali_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_pos_commessa_dipendenti_manager()
      OR public.has_custom_page_access('pos_mezzi_stradali_lista');
$$;

GRANT EXECUTE ON FUNCTION public.is_pos_commessa_mezzi_stradali_manager() TO authenticated;

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_lista_meta_select ON public.pos_commessa_mezzi_stradali_lista_meta;
CREATE POLICY pos_commessa_mezzi_stradali_lista_meta_select
ON public.pos_commessa_mezzi_stradali_lista_meta FOR SELECT TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_user());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_lista_meta_insert ON public.pos_commessa_mezzi_stradali_lista_meta;
CREATE POLICY pos_commessa_mezzi_stradali_lista_meta_insert
ON public.pos_commessa_mezzi_stradali_lista_meta FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mezzi_stradali_manager());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_lista_meta_update ON public.pos_commessa_mezzi_stradali_lista_meta;
CREATE POLICY pos_commessa_mezzi_stradali_lista_meta_update
ON public.pos_commessa_mezzi_stradali_lista_meta FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_manager())
WITH CHECK (public.is_pos_commessa_mezzi_stradali_manager());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_lista_meta_delete ON public.pos_commessa_mezzi_stradali_lista_meta;
CREATE POLICY pos_commessa_mezzi_stradali_lista_meta_delete
ON public.pos_commessa_mezzi_stradali_lista_meta FOR DELETE TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_manager());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_select ON public.pos_commessa_mezzi_stradali;
CREATE POLICY pos_commessa_mezzi_stradali_select
ON public.pos_commessa_mezzi_stradali FOR SELECT TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_user());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_insert ON public.pos_commessa_mezzi_stradali;
CREATE POLICY pos_commessa_mezzi_stradali_insert
ON public.pos_commessa_mezzi_stradali FOR INSERT TO authenticated
WITH CHECK (public.is_pos_commessa_mezzi_stradali_manager());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_update ON public.pos_commessa_mezzi_stradali;
CREATE POLICY pos_commessa_mezzi_stradali_update
ON public.pos_commessa_mezzi_stradali FOR UPDATE TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_manager())
WITH CHECK (public.is_pos_commessa_mezzi_stradali_manager());

DROP POLICY IF EXISTS pos_commessa_mezzi_stradali_delete ON public.pos_commessa_mezzi_stradali;
CREATE POLICY pos_commessa_mezzi_stradali_delete
ON public.pos_commessa_mezzi_stradali FOR DELETE TO authenticated
USING (public.is_pos_commessa_mezzi_stradali_manager());
