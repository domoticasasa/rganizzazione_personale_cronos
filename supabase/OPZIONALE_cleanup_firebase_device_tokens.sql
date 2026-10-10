-- OPZIONALE - pulizia DB dopo la rimozione di Firebase/FCM (10/10/2026)
-- NON e' una migration: eseguilo a mano nel SQL Editor di Supabase solo se vuoi.
-- L'app e le Edge Functions non leggono/scrivono piu' public.device_tokens.
-- Prima: fai un backup (o esporta la tabella).

-- 1) Controllo: quanti token ci sono
select count(*) as token_fcm from public.device_tokens;

-- 2) Svuota i token FCM (dati personali non piu' necessari)
delete from public.device_tokens;

-- 3) (Facoltativo) elimina la tabella.
--    Attenzione: la migration 20260825140000_app_activity_logs_mutations.sql cita
--    'device_tokens' in un elenco di tabelle: verifica che trigger/funzioni non
--    la richiedano prima di eseguire il drop.
-- drop table if exists public.device_tokens cascade;

-- 4) Secret Edge Functions non piu' usati (da togliere in Dashboard > Edge Functions > Secrets):
--    GOOGLE_PROJECT_ID, GOOGLE_CLIENT_EMAIL, GOOGLE_PRIVATE_KEY
--    (solo se non servono ad altro).