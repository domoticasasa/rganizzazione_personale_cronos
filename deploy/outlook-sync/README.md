# Sync Outlook ↔ Agenda CRONOS

Collegamento Microsoft Graph con account **lavoro/scuola**. In app il pulsante è solo **Collega Outlook** / **Scollega**; la sync parte da sola.

Gli **avvisi locali** (Nuova voce → Avviso) funzionano anche senza Azure.

## Per i dipendenti (account Outlook aziendale)

Non serve registrare nulla su Azure.

1. IT abilita una volta la sync (sezione sotto).
2. Nell’agenda: **Collega Outlook**.
3. Login Microsoft con l’account aziendale → sync automatica.

Non esiste un’alternativa ufficiale “senza app Azure”: Microsoft Graph richiede sempre un Client ID. La registrazione è **una sola**, lato GESTOPRO / IT, non per ogni utente.

## Setup tecnico (una sola volta — IT / chi pubblica l’app)

### 1. App Azure (SPA)

1. Portale Azure → **Microsoft Entra ID** → **App registrations** → **New registration**
2. Nome: es. `GESTOPRO360 Outlook`
3. Tipi di account: **Accounts in any organizational directory** (multitenant) oppure solo il tenant azienda
4. Redirect URI (piattaforma **Single-page application**):
   - `https://www.gestopro360.it/auth/outlook/callback`
   - sviluppo: `http://localhost:PORT/auth/outlook/callback`
5. Copia **Application (client) ID**

### API permissions (delegated)

- `User.Read`
- `Calendars.ReadWrite`
- `offline_access`

Grant **admin consent** sul tenant se richiesto (comune con account aziendali).

### Authentication

- SPA / PKCE, **nessun client secret**.
- Redirect URI come sopra.

### 2. Build Flutter / CI

```bash
flutter build web --release --dart-define=MS_GRAPH_CLIENT_ID=<CLIENT_ID>
```

Opzionale: `--dart-define=MS_GRAPH_TENANT=organizations` (default) oppure ID del tenant azienda.

Metti `MS_GRAPH_CLIENT_ID` nei secret CI (workflow Cloudflare Pages) così produzione è sempre abilitata.

## 3. Database

Migration: `supabase/migrations/20260802130000_outlook_agenda_sync.sql`

## 4. Comportamento

- Header agenda: Collega / Scollega
- Sync: apertura agenda, dopo CRUD, timer ~5 min
- Voci: `event` / `reminder` con `starts_at`
- Avviso → Graph `reminderMinutesBeforeStart`

## Limiti v1

- Un avviso per voce, calendario default, sync con app aperta
- Senza Client ID in build: messaggio di setup IT; avvisi locali ok
