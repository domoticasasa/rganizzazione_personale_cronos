Write-Host "🔧 PREPARAZIONE BUILD ANDROID..."

# 2) Clean
flutter clean

# 3) Pub get
flutter pub get

Write-Host "🚀 Compilazione APK..."
flutter build apk --release
Write-Host "✅ Build Android COMPLETATA"