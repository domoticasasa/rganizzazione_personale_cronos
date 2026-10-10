# Scrive build/web/app_revision.json (opzionale: il client aggiorna anche via ETag di main.dart.js).
# Chiamato automaticamente da tool/deploy_web_cloudflare.ps1 e dalla CI GitHub.

param(
  [string]$BuildWebDir = "build/web"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root $BuildWebDir
if (-not (Test-Path $outDir)) {
  throw "Cartella non trovata: $outDir (esegui prima flutter build web)"
}

$sha = ""
try {
  $sha = (git -C $root rev-parse --short HEAD 2>$null).Trim()
} catch {}
if (-not $sha) { $sha = "local" }

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$revision = "$sha-$stamp"
$payload = @{
  revision = $revision
  built_at = [DateTime]::UtcNow.ToString("o")
  git_sha  = $sha
} | ConvertTo-Json -Compress

$target = Join-Path $outDir "app_revision.json"
Set-Content -Path $target -Value $payload -Encoding utf8
Write-Host "Scritto $target -> revision=$revision"
