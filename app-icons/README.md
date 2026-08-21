# Pacchetto icone Gestopro360

Questa cartella contiene il pacchetto completo di icone della versione approvata (combo documento + G360).

## File principali

- `favicon.ico`
- `favicon-16x16.png`
- `favicon-32x32.png`
- `apple-touch-icon.png`
- `android-chrome-192x192.png`
- `android-chrome-512x512.png`
- `icon-192.png`
- `icon-512.png`
- `mstile-150x150.png`
- `site.webmanifest`
- `browserconfig.xml`

## Integrazione web (head)

```html
<link rel="icon" type="image/x-icon" href="app-icons/favicon.ico" />
<link rel="icon" type="image/png" sizes="32x32" href="app-icons/favicon-32x32.png" />
<link rel="icon" type="image/png" sizes="16x16" href="app-icons/favicon-16x16.png" />
<link rel="apple-touch-icon" sizes="180x180" href="app-icons/apple-touch-icon.png" />
<link rel="manifest" href="app-icons/site.webmanifest" />
<meta name="msapplication-config" content="app-icons/browserconfig.xml" />
<meta name="theme-color" content="#1C5DC3" />
```

## Integrazione Flutter launcher icons

Nel repository è stato aggiunto anche `flutter_launcher_icons.yaml`.
Quando hai il progetto Flutter completo (con `pubspec.yaml`), esegui:

```bash
flutter pub add --dev flutter_launcher_icons
flutter pub run flutter_launcher_icons:main -f flutter_launcher_icons.yaml
```
