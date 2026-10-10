# ISTRUZIONI PER L'AGENTE CURSOR – Gestopro360 (build + deploy)
Progetto: `C:\flutter_projects\organizzazione_personale_cronos - mod` · Data modifiche: 10/10/2026

> Regole per l'agente:
> - Esegui i passi **nell'ordine**. Non saltare i backup.
> - I passi marcati **🔴 CONFERMA ALEXANDRU** si eseguono solo dopo il suo «sì» esplicito in chat.
> - Non cancellare mai dati, progetti o utenti di tua iniziativa.
> - Non mettere segreti (chiavi, password) nei file del repository né nei messaggi di commit.

## 0. Riepilogo delle modifiche
- **Sicurezza e privacy (audit legale):**
  - `alert_scadenze_workflow` riservata agli admin.
  - Pagina «Privacy e termini» con informativa, Termini d'uso e Note legali; link sotto il © nel login e nelle sidebar.
  - Schermata informativa prima del permesso GPS; coordinate salvate con 4 decimali.
  - Cancellazione automatica GPS dopo 12 mesi.
  - «Privacy dipendente»: export ZIP e cancellazione dati di un dipendente.
  - jsQR locale invece che da CDN.
  - Notifiche senza tipo di assenza sanitaria.
  - Log solo in debug; `.gitignore` per i file `.env`.
  - Backup conservati 60 giorni (prima 10).
  - `user_admin_service.dart` punta al progetto attuale (non più `vvnpamypxexdtvruzecp`).
- **Controllo admin aggiunto** nelle Edge Function `admin-delete-user`, `admin-create-user`, `admin-sync-users`, `promote-admin`.
  - Prima chiunque poteva chiamarle; con `promote-admin` chiunque poteva diventare admin.
- **Firebase rimosso** dal codice.
- **Recupero password rifatto:** `request-password-reset`, `admin-reset-password`, `admin-set-password`, `notify-password-changed`, `_shared/send_password_reset.ts`, `password_recovery_gate.dart`, template `supabase/templates/recovery.html`.
  - Test end-to-end: tutti PASS (vedi sezione 9).
- **Backup del codice:**
  - `C:\flutter_projects\organizzazione_personale_cronos - mod_backup_20261010_legale`
  - `..._backup_20261010_nofirebase`
  - `..._backup_20261010_pwreset`
- **Checklist di dettaglio:** `CHECKLIST_modifiche_legali.md`, `CHECKLIST_recupero_password_supabase.md`, `OPZIONALE_cleanup_firebase_device_tokens.sql`.

## 1. Git
1. `git status`. Le modifiche sono state committate il 10/10/2026 con il messaggio «Sicurezza, privacy e recupero password - 2026-10-10». Se restano file modificati, fai un commit escludendo `.env*`, `build/`, `.dart_tool/`.
2. Non fare `push` senza **🔴 CONFERMA ALEXANDRU**.

## 2. Backup del database (prima di qualsiasi SQL)
Database: **Supabase cloud, progetto `bjdimalvbdablzoctrsf`** (eu-west-1).
1. Dashboard → Database → Backups: verifica che esista un backup di oggi.
2. Fai anche un dump locale: `supabase db dump --project-ref bjdimalvbdablzoctrsf -f backup_pre_legale_<data>.sql` (oppure `pg_dump` con la connection string che ti dà Alexandru). **Non salvarlo nel repository.**

## 3. Migrazioni SQL – 🔴 CONFERMA ALEXANDRU prima di eseguirle
Esegui nel SQL editor del progetto **bjdimalvbdablzoctrsf**, in quest'ordine:
1. `supabase/migrations/20261010180000_legale_alert_scadenze_workflow_admin_only.sql`
2. `supabase/migrations/20261010180100_legale_privacy_documenti_retention.sql`
   - Crea le tabelle `app_legal_*` e la funzione `privacy_retention_cleanup()`, più il job pg_cron delle 03:40.
3. Trigger `guard_must_change_password`: è nel paragrafo 3 di `CHECKLIST_recupero_password_supabase.md`. Leggi l'avvertenza su `auth.users.updated_at` e chiedi conferma.

Controlli dopo l'esecuzione:
- `select polname from pg_policies where tablename='alert_scadenze_workflow';` → **non** deve comparire `alert_scadenze_workflow_write`.
- `select public.privacy_retention_cleanup();` → deve restituire un JSON.
- `select jobname from cron.job;` → deve comparire `privacy_retention_cleanup_daily`.

## 4. Edge Functions – deploy (`supabase link --project-ref bjdimalvbdablzoctrsf`)
**Secrets** (`supabase secrets list` / `supabase secrets set ...`). I valori li fornisce Alexandru:
- `RESEND_API_KEY` (già presente)
- `PASSWORD_RESET_FROM_EMAIL` (mittente del dominio verificato)
- `PASSWORD_RESET_FROM_NAME=GESTOPRO360`
- `RESET_PASSWORD_REDIRECT_URL=https://gestopro360.it/password-recovery`
- `SECURITY_CONTACT_EMAIL` (facoltativo)

Deploy, una funzione alla volta. Dopo ogni deploy controlla i log:
```
supabase functions deploy request-password-reset --no-verify-jwt
supabase functions deploy admin-reset-password
supabase functions deploy admin-set-password
supabase functions deploy notify-password-changed
supabase functions deploy admin-delete-user
supabase functions deploy admin-create-user
supabase functions deploy admin-sync-users
supabase functions deploy promote-admin
supabase functions deploy admin-employee-privacy
supabase functions deploy daily-data-backup
supabase functions deploy admin-send-notification
supabase functions deploy send-notification
supabase functions deploy app-chat-notify
```
- Le ultime tre sono senza Firebase.
- Dopo il deploy di queste tre e un test delle notifiche web push (**🔴 CONFERMA ALEXANDRU**):
  1. Rimuovi i secrets Firebase: `supabase secrets unset GOOGLE_PROJECT_ID GOOGLE_CLIENT_EMAIL GOOGLE_PRIVATE_KEY`.
  2. Esegui `supabase/OPZIONALE_cleanup_firebase_device_tokens.sql`. Cancella i token FCM salvati: è irreversibile.
- `daily-data-backup`: con 60 giorni lo spazio dei bucket di backup crescerà fino a circa 6 volte quello attuale. Controlla il piano.

## 5. Impostazioni Supabase Dashboard (Authentication) – 🔴 CONFERMA ALEXANDRU
I dettagli completi sono in `CHECKLIST_recupero_password_supabase.md`.
- **URL Configuration:**
  - Site URL `https://gestopro360.it`.
  - Redirect URLs: solo `https://gestopro360.it/password-recovery`, `https://www.gestopro360.it/password-recovery`, `https://gestopro360.it/**`, `https://www.gestopro360.it/**` (più `myapp://auth-callback` solo se serve all'app nativa).
  - Togli `*.pages.dev` e `localhost`.
- **Email provider:**
  - OTP Expiration **3600**.
  - **Secure password change ON**.
  - Secure email change ON.
- **Password:**
  - minimo **10** caratteri, **lettere e numeri**;
  - **Leaked password protection ON**.
- **SMTP:** Resend (`smtp.resend.com`, porta 465, user `resend`, password = API key), mittente del dominio verificato (SPF/DKIM/DMARC).
- **Template «Reset Password»:**
  - oggetto `GESTOPRO360 - Imposta una nuova password`;
  - corpo = contenuto di `supabase/templates/recovery.html` (in italiano).
- **Rate limit:** email ≤ 30/h.

## 6. Dati del fornitore (Termini d'uso e Note legali)
Chiedi ad Alexandru (**🔴 CONFERMA ALEXANDRU**, non inventare nulla):
- ragione sociale;
- P.IVA;
- sede;
- PEC;
- e-mail di contatto;
- e-mail di assistenza;
- data dei Termini;
- data delle Note legali.

Inseriscili in **uno** dei due posti:
- `lib/legal/legal_config.dart` (`fornitoreRagioneSociale`, `fornitorePiva`, `fornitoreSede`, `fornitorePec`, `fornitoreEmail`, `emailAssistenza`, `terminiData`, `noteLegaliData`);
- oppure `update public.app_legal_settings set ... where id = 1;`. In questo caso compila anche `azienda_nome`.

Finché manca un dato l'app mostra un messaggio neutro. Questo è corretto, non è un errore.

L'**informativa privacy** la pubblica l'admin del cliente dall'app (Impostazioni → Privacy e termini → icona modifica → Pubblica), con il testo completato del modello 01.

## 7. Build e deploy web
- Usa **solo** lo script del progetto: `powershell -File tool\deploy_web_cloudflare.ps1` (progetto Cloudflare Pages `gestopro360`).
  - Esegue build, stamp della revisione e `wrangler pages deploy`.
- Serve `GOOGLE_MAPS_API_KEY` nell'ambiente (o `-MapsApiKey`) e `wrangler login`.
- **Mai trascinare `build\web` a mano** nel pannello Cloudflare: si perdono `_headers`, `_redirects` e le funzioni, e le API smettono di funzionare.
- APK/iOS: solo se Alexandru lo chiede.

## 8. Subito dopo il deploy: controllo admin (falla di `promote-admin`)
Esegui ed esporta il risultato, poi **mostralo ad Alexandru** perché individui eventuali admin sconosciuti. Non modificare nulla da solo:
```sql
select u.id, u.full_name, u.email, u.role, u.created_at,
       a.created_at as auth_created_at, a.updated_at as auth_updated_at,
       a.last_sign_in_at, a.raw_app_meta_data->>'role' as auth_role
from public.users u
left join auth.users a on a.id = u.auth_id
where lower(coalesce(u.role,'')) like 'admin%'
   or lower(coalesce(a.raw_app_meta_data->>'role','')) like 'admin%'
order by a.updated_at desc nulls last;
```
Se ci sono ruoli admin sospetti: **🔴 CONFERMA ALEXANDRU** prima di cambiarli.

## 9. Vecchio progetto `vvnpamypxexdtvruzecp` – SOLO REPORT
- Con l'accesso di Alexandru, verifica se è attivo o in pausa e se contiene dati reali.
  - Conta le righe di `users`, `personale`, `bookings` e delle altre tabelle; controlla i bucket storage.
- **Riporta** solo i numeri, con date e tabelle.
- **Non cancellare né mettere in pausa nulla**: la decisione è manuale di Alexandru.
- Se contiene dati reali, legale chiede di cancellarlo oppure di inserirlo nei documenti privacy.

## 10. Chiave Google Maps (Google Cloud Console) – la fa Alexandru o l'agente con il suo accesso
1. console.cloud.google.com → progetto della chiave → API e servizi → Credenziali → apri la chiave usata dal web.
2. Restrizioni applicazione → **Referrer HTTP**: `https://gestopro360.it/*`, `https://*.gestopro360.it/*` (più `https://gestopro360.pages.dev/*` se serve).
3. Restrizioni API → solo **Maps JavaScript API** (più le altre API Maps realmente usate).
4. App Android/iOS: chiavi separate, con nome pacchetto + SHA-1 / bundle ID.
5. Salva e prova la mappa sul sito.

## 11. Test dopo il deploy
**Recupero password** (da `RISULTATI_TEST.md`):
- Reset con e-mail esistente → mail italiana con link `/password-recovery`; e-mail inesistente → stessa risposta, nessuna mail.
- 4 richieste in fila → 1 sola mail (rate limit).
- Regole password: meno di 10 caratteri / solo lettere / spazi → errori in italiano.
- Password cambiata: vecchia rifiutata, nuova OK, altre sessioni disconnesse, mail «password cambiata».
- Link riusato o più vecchio di 60 minuti → «Link scaduto o già usato».
- `/password-recovery` senza link → login.
- `admin-reset-password`: dipendente 403, admin OK.
- Dopo il cambio compare «Controlla le tue Passkey».

**Sicurezza:**
- `promote-admin`, `admin-delete-user`, `admin-create-user`, `admin-sync-users` chiamate da un dipendente → **403**.

**Funzioni legali:**
- Link «Privacy e termini» nel login e nelle sidebar; schede Informativa / Termini / Note legali, con messaggio neutro se i dati mancano.
- Admin: pubblicazione dell'informativa; il pulsante «Pubblica» rifiuta testi con [ ].
- Alert scadenze: un DT vede il menu stato disabilitato, un admin lo modifica.
- Buono pasto / viaggio mezzo: compare la schermata GPS prima del permesso; le coordinate hanno 4 decimali.
- Impostazioni → Privacy dipendente: «Esporta dati (ZIP)» su un dipendente di prova.
  - «Cancella dati» **solo su un dipendente di prova** e con **🔴 CONFERMA ALEXANDRU**.
- Web: scanner QR dei buoni pasto funzionante (jsQR locale).
- Notifiche: nessun riferimento a Firebase; arrivano le web push.
- Backup: la pagina mostra «retention 60 giorni».

## 12. Problemi noti ancora aperti (non bloccanti, da segnalare)
- `admin-send-notification` è chiamabile da qualsiasi utente loggato (serve all'app). Va limitata con un controllo più fine.
- Tesseract.js (OCR ricevute) viene ancora caricato da cdn.jsdelivr.net.
- AppChatService parte anche durante la sessione di recupero password.
- DT e assistenti DT non possono più cambiare lo stato degli alert scadenze (solo admin).
- La cancellazione automatica degli ex dipendenti dopo X anni non è implementata: manca il periodo deciso dal cliente.
- GestoproOre (altro progetto): `admin-reset-password` risponde «email inviata» ma non invia nulla.
