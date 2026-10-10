-- Email struttura (per invio elenco pernottamenti in IN_ATTESA)
ALTER TABLE public.structures
ADD COLUMN IF NOT EXISTS email text;

COMMENT ON COLUMN public.structures.email IS
'Email della struttura per invio conferme/elenchi pernottamenti via Outlook';

