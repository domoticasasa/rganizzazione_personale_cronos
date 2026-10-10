# Checklist modifiche legali – Gestopro360 (10/10/2026)

Modifiche fatte **solo nel codice** dopo l'audit `Legale/Audit_legale_app.md`.
Nessun build, nessun deploy, nessun SQL applicato al database online.
Backup completo del progetto prima delle modifiche:
`C:\flutter_projects\organizzazione_personale_cronos - mod_backup_20261010_legale`

## 1. SQL da applicare (Supabase → SQL editor, progetto `bjdimalvbdablzoctrsf`), in quest'ordine
1. `supabase/migrations/20261010180000_legale_alert_scadenze_workflow_admin_only.sql`
   - `alert_scadenze_workflow`: lettura solo admin (anche admin vista), scrittura solo admin (`is_cronos_admin_role()`).
   - Nota: DT e assistenti DT, nella pagina Alert scadenze, vedranno tutti gli stati come «DA GESTIRE» e non potranno cambiarli.
2. `supabase/migrations/20261010180100_legale_privacy_documenti_retention.sql`
   - tabelle `app_legal_settings`, `app_legal_documents`, `app_legal_acceptances`;
   - funzione `privacy_retention_cleanup()` (azzera le coordinate GPS più vecchie di 12 mesi, configurabile) + job pg_cron notturno alle 03:40 `privacy_retention_cleanup_daily`;
   - commento backup aggiornato a 60 giorni.
   - Dopo l'applicazione, per una prova manuale: `select public.privacy_retention_cleanup();`
3. Controlla in Authentication → Policies che su `alert_scadenze_workflow` non resti la vecchia policy `alert_scadenze_workflow_write` (using true).

## 2. Edge Function da deployare (quando decidi tu)
- Nuova: `supabase/functions/admin-employee-privacy` (export e cancellazione dati di un dipendente). Comando: `supabase functions deploy admin-employee-privacy`
- Modificata: `supabase/functions/daily-data-backup` → `RETENTION_DAYS = 60` (prima 10). Comando: `supabase functions deploy daily-data-backup`
  - Spazio: i backup restano 6 volte più a lungo, quindi lo spazio occupato dai bucket `cronos_data_backups` e `cronos_data_backups_replica` crescerà fino a circa 6 volte quello attuale. Controlla in «Utilizzo Supabase» che resti nei limiti del piano.

## 3. Da compilare
- Termini d'uso: compila i dati del fornitore (ragione sociale, P.IVA, sede, PEC, e-mail assistenza, data) in `lib/legal/legal_config.dart` **oppure** nella tabella `app_legal_settings`. Finché manca un dato l'app mostra «Termini d'uso in fase di pubblicazione».
- Informativa privacy: ogni cliente (titolare) deve compilare il modello 01. L'admin la incolla e la pubblica da Impostazioni → «Privacy e termini» → icona modifica. Il pulsante «Pubblica» rifiuta testi con parti ancora tra [ ]. Finché non è pubblicata i dipendenti vedono «Informativa in fase di pubblicazione: contatta il tuo datore di lavoro».
- `app_legal_settings.gps_retention_months` (default 12) se il cliente sceglie un periodo diverso.

## 4. Google Maps – limitare la chiave (Google Cloud Console)
La chiave in `web/index.html` non è stata cambiata. Nella console:
1. https://console.cloud.google.com → progetto della chiave → «API e servizi» → «Credenziali».
2. Apri la chiave usata in `web/index.html`.
3. «Restrizioni applicazione» → «Siti web (referrer HTTP)» e aggiungi: `https://gestopro360.it/*`, `https://*.gestopro360.it/*` (più eventuali domini `*.pages.dev` di Cloudflare se usati).
4. Per le app Android/iOS, se usano Maps, crea chiavi separate con restrizione «App Android» (nome pacchetto + SHA-1) e «App iOS» (bundle ID).
5. «Restrizioni API» → limita a «Maps JavaScript API» (ed eventuali altre API Maps realmente usate).
6. Salva e prova la mappa sul sito.

## 5. Da provare in app (dopo il prossimo build fatto da te)
- Alert scadenze come DT: menu stato disabilitato; come admin: modificabile.
- Buono pasto / viaggio mezzo: al primo uso compare la schermata «Posizione per il buono pasto» prima della richiesta di sistema. Le coordinate ora sono salvate con 4 decimali (circa 11 m).
- Link «Privacy e termini» sotto il © nel login e nelle sidebar; voce «Privacy e termini» e «Privacy dipendente» in Impostazioni.
- Privacy dipendente: «Esporta dati (ZIP)» e «Cancella dati» (richiede la Edge Function deployata).
- Web: scanner QR buoni pasto (jsQR ora da `web/js/jsQR.min.js`).

## Note legali (aggiunte 10/10/2026)
- Nuova scheda «Note legali» dentro «Privacy e termini» (testo doc 09).
- Usa gli stessi dati fornitore dei Termini più `fornitore_email` (e-mail di contatto) e `note_legali_data` (data ultimo aggiornamento): in `lib/legal/legal_config.dart` (`fornitoreEmail`, `noteLegaliData`) o in `app_legal_settings`. Finché manca un dato compare «Note legali in fase di pubblicazione».
- Le colonne sono già incluse nella migrazione legale di questo progetto (non ancora applicata).
