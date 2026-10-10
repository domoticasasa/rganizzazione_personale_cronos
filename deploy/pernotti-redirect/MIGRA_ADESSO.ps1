# Deploy migrazione dominio (esegui da cartella progetto)
# 1) Redirect pernotti.pages.dev -> gestopro360.it
# 2) (opzionale) build+deploy app su progetto gestopro

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..\..

Write-Host "`n=== Login Cloudflare (si apre il browser) ===" -ForegroundColor Cyan
npx --yes wrangler login

Write-Host "`n=== Deploy redirector su progetto Pages 'pernotti' ===" -ForegroundColor Cyan
npx --yes wrangler pages deploy deploy/pernotti-redirect --project-name=pernotti

Write-Host "`nFATTO: apri https://pernotti.pages.dev — deve andare su gestopro360.it" -ForegroundColor Green
Write-Host @"

IMPORTANTE DNS (una sola volta, su IONOS):
  gestopro360.it oggi punta a IONOS (pagina vuota), non all'app.
  In Cloudflare Pages > progetto gestopro > Custom domains:
  - Aggiungi gestopro360.it
  - Copia i record CNAME/A che ti mostra Cloudflare
  - Incollali nel pannello DNS di IONOS (sostituisci i record attuali)

Poi l'app ufficiale e': https://gestopro360.it
(ora funziona gia' su https://gestopro.pages.dev)

"@
