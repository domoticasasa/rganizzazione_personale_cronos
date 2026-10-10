# Build + stamp revisione + deploy Cloudflare Pages (gestopro360).
# Uso:
#   powershell -File tool/deploy_web_cloudflare.ps1
#   powershell -File tool/deploy_web_cloudflare.ps1 -SkipBuild

param(
  [switch]$SkipBuild,
  [string]$MapsApiKey = $env:GOOGLE_MAPS_API_KEY,
  [string]$ProjectName = "gestopro360"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $SkipBuild) {
  Write-Host "==> flutter build web --release" -ForegroundColor Cyan
  $define = @()
  if ($MapsApiKey) {
    $define = @("--dart-define=GOOGLE_MAPS_API_KEY=$MapsApiKey")
  }
  & flutter build web --release @define
  if ($LASTEXITCODE -ne 0) { throw "flutter build web fallito ($LASTEXITCODE)" }
}

Write-Host "==> stamp revisione web" -ForegroundColor Cyan
& powershell -NoProfile -File (Join-Path $PSScriptRoot "stamp_web_revision.ps1")
if ($LASTEXITCODE -ne 0) { throw "stamp_web_revision fallito ($LASTEXITCODE)" }

Write-Host "==> wrangler pages deploy ($ProjectName)" -ForegroundColor Cyan
& npx --yes wrangler pages deploy build/web --project-name=$ProjectName --branch=main --commit-dirty=true
if ($LASTEXITCODE -ne 0) { throw "wrangler deploy fallito ($LASTEXITCODE)" }

Write-Host "Deploy OK → https://www.gestopro360.it" -ForegroundColor Green
