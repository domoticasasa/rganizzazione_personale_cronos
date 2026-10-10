# Gotenberg — PDF identico al Mod.RFP_03 Excel (web)

Su **web** non c’è Excel: l’unico modo per ottenere un PDF **identico** al file `.xlsx` compilato è convertire l’xlsx con **LibreOffice** tramite [Gotenberg](https://gotenberg.dev/).

I tentativi con pdf-lib / overlay non replicano layout, merge celle e immagini del template: **non vanno usati** per Mod.RFP_03.

## Architettura

```
App web → xlsx compilato (Mod.RFP_03)
       → 1) ExcelTS in browser (assets/rfp03_excel_to_pdf.js)
       → 2) Supabase Edge Function convert-office-pdf + Gotenberg (fallback)
       → PDF
```

Su **Windows desktop**, se Gotenberg non risponde, fallback su **Excel COM** (come prima).

## Deploy Gotenberg su Railway (consigliato, ~5 min, senza Docker locale)

1. Account su [railway.app](https://railway.app)
2. **New Project** → **Empty Project** → **Add Service** → **GitHub Repo** (questo repository)
3. Nelle impostazioni del servizio:
   - **Root Directory**: `deploy/gotenberg`
   - **Builder**: Dockerfile
4. **Settings** → **Networking** → **Generate Domain** (es. `gotenberg-production-xxxx.up.railway.app`)
5. Verifica: `https://TUO-DOMINIO/health` → deve rispondere OK
6. Imposta il secret Supabase (progetto `bjdimalvbdablzoctrsf`):

```bash
supabase secrets set GOTENBERG_URL=https://TUO-DOMINIO.up.railway.app --project-ref bjdimalvbdablzoctrsf
supabase functions deploy convert-office-pdf --project-ref bjdimalvbdablzoctrsf
```

7. Riesporta PDF dalla web app.

> **Nota:** non aggiungere `/forms/...` al secret — solo l’URL base (es. `https://gotenberg-xxx.up.railway.app`).

## Deploy alternativi

- **Render.com**: Web Service, Docker, root `deploy/gotenberg`, stesso Dockerfile
- **VPS**: `docker compose up -d` nella cartella `deploy/gotenberg` + reverse proxy HTTPS (Caddy/Nginx)
- **Locale** (solo test): Docker Desktop + `docker compose up -d` → `GOTENBERG_URL=http://host.docker.internal:3000` non funziona da Supabase Cloud (serve URL pubblico HTTPS)

## Test manuale conversione

```bash
curl -X POST https://TUO-DOMINIO/forms/libreoffice/convert \
  -F "files=@Mod.RFP_03.xlsx" \
  -o test.pdf
```

## Costi indicativi

Railway/Render: piano hobby spesso sufficiente (Gotenberg ~512MB RAM, conversioni sporadiche).

## Funzioni Supabase

| Function | Uso |
|----------|-----|
| `convert-office-pdf` | **Produzione** — xlsx → PDF via Gotenberg |
| `render-rfp03-pdf` | Deprecata — layout approssimato, non usare |
