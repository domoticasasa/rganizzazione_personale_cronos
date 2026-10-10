Write-Host "🔧 PREPARAZIONE BUILD WINDOWS..."

# 2) Clean
flutter clean

# 3) Pub get
flutter pub get

# 4) Cancella build Windows vecchie e cache
Remove-Item -Recurse -Force windows\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force windows\CMakeFiles -ErrorAction SilentlyContinue
Remove-Item -Force windows\CMakeCache.txt -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force windows\flutter\ephemeral -ErrorAction SilentlyContinue

Write-Host "🚀 Compilazione Windows..."
flutter build windows
Write-Host "✅ Build Windows COMPLETATA"