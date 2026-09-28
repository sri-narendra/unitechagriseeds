# Unitech Dealer Android App

Minimal WebView wrapper for the dealer portal.

## What it does

Loads the dealer HTML pages from local assets. Same pages as the website, runs offline.

## How to build

### CLI (Windows, verified)

Prereqs on this machine:
- JDK 17 at `H:\javajdk`
- Android SDK at `H:\Android\sdk` (platform 34 + build-tools 34.0.0)
- Gradle 8.2 (wrapper auto-uses the local cached distribution)

```powershell
$env:JAVA_HOME = "H:\javajdk"
cd androidapp
.\gradlew.bat assembleDebug --console=plain
# output: androidapp\app\build\outputs\apk\debug\app-debug.apk
# copy to public\dealer-app.apk for distribution:
Copy-Item app\build\outputs\apk\debug\app-debug.apk ..\public\dealer-app.apk -Force
```

### Android Studio

1. Open `androidapp/` in Android Studio
2. Sync Gradle
3. Run on device/emulator

## Structure

```
androidapp/
├── MainActivity.kt          # WebView container
├── AndroidManifest.xml
├── activity_main.xml
├── strings.xml
├── colors.xml
├── themes.xml
├── build.gradle             # root build (AGP 8.2.0 + Kotlin 1.9.20)
├── settings.gradle.kts
├── gradle.properties
├── local.properties         # machine-local SDK path (not committed)
└── assets/dealer/           # HTML pages (same as website)
    ├── index.html
    ├── order.html
    ├── stock.html
    ├── sale.html
    ├── return.html
    └── shared.css
```

## How it works

- `MainActivity.kt` → loads `assets/dealer/index.html` in WebView
- Same HTML/JS/CSS as the website dealer portal
- Back button = WebView history navigation
- External links open in system browser

## Notes

- **Keep `app/src/main/assets/dealer/*` in sync with the `dealer/*` pages at
  the repo root (all 6 files) before every build**, then rebuild the APK —
  this is how portal changes reach the app.
- Toolchain: Gradle 8.2, AGP 8.2.0, Kotlin 1.9.20, compileSdk/targetSdk 34.
- App name: "Unitech Dealers"
- Green theme matching the web portal
- Min SDK 24 (Android 7.0+)
- Pages load from local assets (works offline)
