# Checklist da applicare A MANO – recupero password GESTOPRO360
(Nulla di questo è stato applicato: niente build, deploy, SQL o modifiche al database live.)

## 1. Supabase Dashboard → Authentication
- [ ] **URL Configuration**
  - Site URL: `https://gestopro360.it`
  - Redirect URLs: tenere solo `https://gestopro360.it/password-recovery`, `https://www.gestopro360.it/password-recovery`, `https://gestopro360.it/**`, `https://www.gestopro360.it/**` e `myapp://auth-callback` (solo se serve davvero l'app nativa).
  - Togliere dalla lista di produzione `pernotti.pages.dev`, `6cae88f3.pernotti.pages.dev`, `gestopro.pages.dev` e `localhost` (questi ultimi vanno solo nel progetto di sviluppo).
- [ ] **Providers → Email**
  - Email OTP Expiration = **3600** secondi.
  - **Secure password change = ON**: chi è già loggato deve reinserire la password o confermare con un codice.
  - **Secure email change = ON**.
- [ ] **Policies / Password**: Minimum length = **10**; Password requirements = **Letters and digits**; **Leaked password protection (HIBP) = ON** (piano Pro).
- [ ] **Emails → SMTP Settings**: SMTP personalizzato (Resend: host `smtp.resend.com`, porta 465, user `resend`, password = API key) con mittente `GESTOPRO360 <noreply@tuodominio>` e dominio verificato (SPF/DKIM/DMARC).
- [ ] **Emails → Templates → Reset Password**
  - Oggetto: `GESTOPRO360 - Imposta una nuova password`.
  - Corpo: incollare il contenuto di `supabase/templates/recovery.html`.
- [ ] **Emails → Templates**: attivare la notifica **Password changed**, se disponibile, oppure usare la funzione `notify-password-changed` (sezione 2).
- [ ] **Rate Limits**: Email sent ≤ 30/h; Token verifications predefinito.
- [ ] **Sessions** (opzionale, piano Pro): Inactivity timeout e Time-box per i ruoli admin.

## 2. Edge Functions (deploy SOLO dopo una prova in locale con `supabase functions serve`)
- [ ] Secrets:
  - `RESEND_API_KEY` (c'è già);
  - `PASSWORD_RESET_FROM_EMAIL` (mittente del dominio verificato);
  - `PASSWORD_RESET_FROM_NAME=GESTOPRO360`;
  - `RESET_PASSWORD_REDIRECT_URL=https://gestopro360.it/password-recovery` (facoltativo: deve stare nella allow-list);
  - `SECURITY_CONTACT_EMAIL` (facoltativo).
- [ ] Deploy:
  - `supabase functions deploy request-password-reset --no-verify-jwt`
  - `supabase functions deploy admin-reset-password`
  - `supabase functions deploy admin-set-password`
  - `supabase functions deploy notify-password-changed`
- [ ] Nota: `notify-password-changed` usa `SUPABASE_ANON_KEY`, che è automatica nelle Edge Functions.

## 3. SQL (da eseguire nel SQL editor dopo averlo letto; NON applicato)
Il cambio obbligatorio al primo accesso esiste già (`users.must_change_password`, impostato da `admin-set-password` e `admin-create-user`). Questo controllo impedisce al dipendente di togliersi il flag da solo, senza cambiare password:
```sql
-- 1) Controlla chi può aggiornare must_change_password
select polname, cmd, qual, with_check from pg_policies where tablename = 'users';

-- ATTENZIONE: auth.users.updated_at può cambiare anche al login; verificare prima in staging.
-- 2) Trigger: un utente non-admin può solo mettere il flag a FALSE e solo
--    se la password è stata cambiata negli ultimi 10 minuti.
create or replace function public.guard_must_change_password()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_updated timestamptz;
begin
  if new.must_change_password is distinct from old.must_change_password
     and auth.uid() = old.auth_id then
    if new.must_change_password = true then
      return new;
    end if;
    select updated_at into v_updated from auth.users where id = auth.uid();
    if v_updated is null or v_updated < now() - interval '10 minutes' then
      raise exception 'must_change_password: cambia prima la password';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_must_change_password on public.users;
create trigger trg_guard_must_change_password
before update of must_change_password on public.users
for each row execute function public.guard_must_change_password();
```

## 4. Dopo il deploy: prove
- [ ] Reset con un'email esistente e con una inesistente: stessa risposta, mail solo per quella esistente.
- [ ] Link usato due volte → «Link scaduto o già usato». Link dopo più di 60 minuti → idem.
- [ ] Da loggato, aprire `https://gestopro360.it/password-recovery` senza link → pagina «link non valido».
- [ ] Dopo il cambio: arriva la mail «password cambiata», gli altri dispositivi sono disconnessi, compare la finestra delle Passkey.
- [ ] Reset fatto da un admin → mail uguale con link `/password-recovery`; un utente NON admin che chiama `admin-reset-password` riceve 403.
