-- Lista dipendenti in POS (cantiere) per commessa — import Elenco Maestranze.

CREATE TABLE IF NOT EXISTS public.pos_commessa_lista_meta (
  commessa_id uuid PRIMARY KEY REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  data_ultimo_aggiornamento date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.pos_commessa_dipendenti (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commessa_id uuid NOT NULL REFERENCES public.commesse (id_uuid) ON DELETE CASCADE,
  personale_id uuid NOT NULL REFERENCES public.personale (id_uuid) ON DELETE CASCADE,
  cognome_import text,
  nome_import text,
  mansione text,
  idoneita_sanitaria date,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_uuid uuid REFERENCES public.users (id_uuid) ON DELETE SET NULL,
  UNIQUE (commessa_id, personale_id)
);

CREATE INDEX IF NOT EXISTS pos_commessa_dipendenti_commessa_idx
  ON public.pos_commessa_dipendenti (commessa_id);

CREATE INDEX IF NOT EXISTS pos_commessa_dipendenti_personale_idx
  ON public.pos_commessa_dipendenti (personale_id);

DROP TRIGGER IF EXISTS trg_pos_commessa_dipendenti_updated_at ON public.pos_commessa_dipendenti;
CREATE TRIGGER trg_pos_commessa_dipendenti_updated_at
BEFORE UPDATE ON public.pos_commessa_dipendenti
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_updated_at();
