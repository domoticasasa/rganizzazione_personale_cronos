# Redirect pernotti.pages.dev → www.gestopro360.it

**Stato (già fatto da CLI):**
- `https://pernotti.pages.dev` → **301** → `https://www.gestopro360.it`
- App live: progetto Pages **`gestopro360`** (`gestopro360.pages.dev` + `www.gestopro360.it`)
- Dominio apex `gestopro360.it` **aggiunto** al progetto (stato pending finché non cambia il DNS su IONOS)

## Una cosa sola rimasta (IONOS)

`gestopro360.it` oggi punta ancora a IONOS (pagina vuota). Su IONOS DNS:

| Tipo | Nome | Valore |
|------|------|--------|
| CNAME | `www` | `gestopro360.pages.dev` |
| CNAME o ALIAS | `@` (apex) | `gestopro360.pages.dev` |

Se IONOS non permette CNAME sull’apex (`@`), usa i nameserver Cloudflare oppure un record ALIAS/ANAME verso `gestopro360.pages.dev`.

Finché l’apex non è attivo, usa **`https://www.gestopro360.it`**.

## Redeploy redirector

```bash
npx wrangler pages deploy deploy/pernotti-redirect --project-name=pernotti --branch=main --commit-dirty=true
```

## Deploy app

```bash
flutter build web --release
powershell -File tool/stamp_web_revision.ps1
npx wrangler pages deploy build/web --project-name=gestopro360 --branch=main --commit-dirty=true

# Oppure in un colpo solo:
# powershell -File tool/deploy_web_cloudflare.ps1
```

## Supabase Auth

Vedi [SUPABASE_AUTH_URLS.md](SUPABASE_AUTH_URLS.md).
