# VidBrowser — Port a Flutter/Android

Port de tu app PyQt6 (navegador Chromium + descargador con yt-dlp + ad-block)
a Flutter, usando el WebView nativo de Android (Chromium) y **Chaquopy** para
correr Python/yt-dlp embebido dentro de la app.

## Cómo quedaron mapeadas las piezas originales

| Original (PyQt6)                     | Flutter/Android                                  |
|---------------------------------------|---------------------------------------------------|
| `QWebEngineView`                      | `flutter_inappwebview` (WebView Chromium nativo)   |
| `AdBlockInterceptor`                  | `lib/services/adblock_service.dart` + `shouldInterceptRequest` |
| `DownloadWorker._download_direct`     | `lib/services/direct_download_service.dart` (Dio)  |
| `DownloadWorker._download_ytdlp`      | `android/app/src/main/python/downloader.py` (Chaquopy) |
| `extract_pimpbunny_com`               | Misma función, portada 1:1 dentro de `downloader.py` |
| `QTableWidget` de descargas           | `lib/widgets/download_panel.dart`                  |
| `QInputDialog` (elegir calidad)       | `showDialog` con `SimpleDialog`                    |

## Requisitos para compilar

1. **Flutter SDK** instalado (`flutter doctor` sin errores de Android).
2. **Android Studio** con NDK 25.2.9519653 instalado (Chaquopy lo necesita).
3. Una **licencia de Chaquopy**: es gratis para apps open-source; para apps
   comerciales/cerradas requiere licencia paga (revisá https://chaquo.com/chaquopy/ —
   esto es importante, no lo omitas antes de publicar).

## Pasos

```bash
cd vidbrowser
flutter pub get
flutter run          # para probar en un dispositivo/emulador conectado
flutter build apk --release --target-platform android-arm64
```

El primer build tarda más de lo normal porque Chaquopy descarga el intérprete
de Python y hace `pip install yt-dlp requests` dentro del proceso de Gradle.

## ⚠️ Cosas que tenés que ajustar vos

- **`applicationId`**: cambiá `com.tuempresa.vidbrowser` en `android/app/build.gradle`
  y en la carpeta de Kotlin (`android/app/src/main/kotlin/com/tuempresa/vidbrowser`)
  por tu propio ID de paquete.
- **Firma de release**: el build actual usa la firma de debug
  (`signingConfig = signingConfigs.debug`). Para publicar necesitás tu propio keystore.
- **Ícono de la app**: falta `android/app/src/main/res/mipmap-*/ic_launcher.png`
  (no vienen incluidos). Generalos con `flutter_launcher_icons` o Android Studio.
- **Permisos de Android 13+**: en dispositivos modernos, para guardar en
  `Descargas` puede convenir usar `MediaStore` en vez de escritura directa a
  archivo; dejé `requestLegacyExternalStorage` activado como solución rápida,
  pero no es la forma recomendada a largo plazo por Google.

## Limitaciones conocidas de este port

- **Tamaño del APK**: al embeber Python + yt-dlp, el APK crece
  significativamente (+30-50MB) comparado con una app Flutter normal.
- **shouldInterceptRequest solo filtra por dominio**, igual que el original;
  no reescribe ni modifica contenido HTML/CSS de la página como hacen
  ad-blockers más avanzados (uBlock, etc.).
- **Chaquopy solo corre en Android**, no en iOS. Si más adelante querés una
  versión iOS, esa parte (yt-dlp) tendría que migrar a un backend propio.

## Advertencia importante sobre Google Play

Apps que descargan video de plataformas como YouTube suelen chocar con los
**Términos de Servicio de esos sitios** y, dependiendo del contenido
descargado, con derechos de autor. Google Play además **rechaza o da de baja**
regularmente apps de este tipo (el caso más conocido es Snaptube, que nunca
estuvo en Play Store). Si tu plan es distribuirla fuera de Play (APK directo,
F-Droid con salvedades, etc.) no hay problema técnico; si es publicarla en
Play Store, es un riesgo real de rechazo que vale la pena que tengas en cuenta
antes de invertir más tiempo en esto.
