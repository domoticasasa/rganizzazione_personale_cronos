# fix_encoding.ps1
# Ripulisce artefatti di encoding (UTF-8 interpretato come Windows-1252) e salva i file in UTF-8.
# Target: i 3 file admin + qualsiasi altro .dart che volessi aggiungere alla lista.

$ErrorActionPreference = 'Stop'

# === 1) Imposta i percorsi dei file da ripulire ===
$files = @(
  "lib/pages/admin_treni_page.dart",
  "lib/pages/admin_aerei_page.dart",
  "lib/pages/admin_pernottamenti_page.dart"
)

# Se i file stanno in un'altra cartella, modifica i percorsi sopra.

# === 2) Mappa sostituzioni comuni (correzioni encoding) ===
$map = [ordered]@{
  "â€“"   = "–"   # en dash
  "â€”"   = "—"   # em dash
  "â€˜"   = "‘"
  "â€™"   = "’"
  "â€œ"   = "“"
  "â€"   = "”"
  "â€\x9d"= "”"   # variante
  "â€¢"   = "•"
  "â€¦"   = "…"   # ellissi

  # Accentate italiane corrotte
  "Ã " = "à"
  "Ã¨" = "è"
  "Ã©" = "é"
  "Ã¬" = "ì"
  "Ã²" = "ò"
  "Ã¹" = "ù"
  "Ã€" = "À"
  "Ã‰" = "É"
  "ÃŒ" = "Ì"
  "Ã’" = "Ò"
  "Ã™" = "Ù"

  # Alcuni casi frequenti visti nei file esportati
  "SÃ¬" = "Sì"
  "NÂ°" = "N°"
  " \u00a0" = " "   # NBSP -> spazio normale
}

# Frasi intere tipiche sporche -> pulite
$phraseMap = [ordered]@{
  "Confermi lâ€™eliminazione?" = "Confermi l’eliminazione?"
  "Confermi l\u00e2\u20ac\u2122eliminazione?" = "Confermi l’eliminazione?"
  "Admin \u00e2\u20ac\u201d Treni" = "Admin — Treni"
  "Admin \u00e2\u20ac\u201d Aerei" = "Admin — Aerei"
  "Admin \u00e2\u20ac\u201c Pernottamenti" = "Admin — Pernottamenti"
  "\u00e2\u20ac\u201d Qualsiasi \u00e2\u20ac\u201d" = "— Qualsiasi —"
  "\u00e2\u20ac\u201d Chiunque \u00e2\u20ac\u201d" = "— Chiunque —"
  "\u00e2\u20ac\u201d" = "—"
}

# === 3) Funzione di pulizia singolo file ===
function Fix-File {
  param([string]$path)

  if (!(Test-Path $path)) {
    Write-Host "⚠️  File non trovato: $path" -ForegroundColor Yellow
    return
  }

  # Leggi come RAW (senza interpretazioni)
  $raw = Get-Content -LiteralPath $path -Raw -Encoding Byte
  # Prova a decodificare come UTF-8 (se già corretto non rompe)
  $text = [System.Text.Encoding]::UTF8.GetString($raw)

  # Backup
  Copy-Item -LiteralPath $path -Destination "$path.bak" -Force

  $count = 0

  # Sostituzioni da mappa caratteri
  foreach ($k in $map.Keys) {
    $before = $text
    $text = $text -replace [Regex]::Escape($k), [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $map[$k] }
    if ($text -ne $before) {
      $count += ([regex]::Matches($before, [regex]::Escape($k))).Count
    }
  }

  # Sostituzioni di frasi
  foreach ($k in $phraseMap.Keys) {
    $before = $text
    $text = $text -replace [Regex]::Escape($k), [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $phraseMap[$k] }
    if ($text -ne $before) {
      $count += ([regex]::Matches($before, [regex]::Escape($k))).Count
    }
  }

  # Salva in UTF-8 (senza BOM)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)

  Write-Host ("✅ Ripulito {0} (sostituzioni: {1})" -f $path, $count) -ForegroundColor Green
}

# === 4) Esecuzione ===
$tot = 0
foreach ($f in $files) {
  Fix-File -path $f
}

Write-Host ""
Write-Host "Suggerimento: flutter clean && flutter pub get && flutter run -d windows" -ForegroundColor Cyan