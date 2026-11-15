# QuestMap IRL — Código de la app

Navegación GPS con estética de videojuego. SwiftUI, iOS 17+, **gratuita y sin compras**.

## Montaje en Xcode (un solo comando)
El proyecto Xcode se genera con XcodeGen a partir de `project.yml` (raíz del repositorio). Ya incluye Info.plist, permisos, Background Modes, entitlements y target de tests.

En un Mac, desde la carpeta raíz:
```bash
sh setup-mac.sh
```

Sin Mac: el workflow `.github/workflows/ios-build.yml` compila y pasa los tests en un Mac de GitHub; `ios-ipa.yml` genera un `.ipa` sin firmar.

Para ejecutar en un iPhone real, pon tu Team ID en `project.yml` (`DEVELOPMENT_TEAM`) y vuelve a generar.

## Mapa de módulos
| Carpeta | Contenido |
|---|---|
| `App/` | Entrada, contenedor SwiftData, composición de servicios, `RootView` |
| `Core/Theme` | `MapTheme` (tokens), `ThemeCatalog` (los 6 temas), `Color(hex:)` |
| `Core/Models` | SwiftData: `UserSettings`, `SavedPlace`, `TripRecord`, `VisitedCell` |
| `Domain/` | Lógica pura testeable: `NavigationEngine`, `FogGrid`, `Achievements`, `ManeuverFormatter` |
| `Services/` | Core Location, MKDirections, MKLocalSearch, voz, enlaces de compartir |
| `Data/` | `TripRepository` (guarda viajes y niebla) |
| `Features/` | Onboarding, Home, Search, ActiveNavigation, Settings, Profile |
| `DesignSystem/` | `MapOverlayView`, `routeLayers`, `QuestPanel`, `PlayerMarker`, `GPSIndicator` |
| `Tests/` | Motor de navegación, niebla, gamificación, temas y formato de maniobras |

## Pantalla completa
- `Info.plist` propio con `UILaunchScreen` (sin él, iOS ejecuta la app en modo compatibilidad con bandas negras) y `UIRequiresFullScreen`.
- El mapa usa `.ignoresSafeArea()`; el HUD va en `safeAreaInset(edge:)`, de modo que respeta Dynamic Island, notch e indicador de inicio en todos los iPhone.
- `GeometryReader` fija el tamaño real de la pantalla en Home y en navegación activa.
- Dynamic Type: los textos grandes llevan `minimumScaleFactor` y `lineLimit` para no recortarse.

## GPS
- Precisión `kCLLocationAccuracyNearestTenMeters` en reposo y `BestForNavigation` durante la navegación (ahorro de batería).
- Suavizado exponencial de la posición: nada de saltos ni vibración del marcador.
- Rumbo: `course` del GPS en movimiento, brújula cuando estás parado.
- Indicador de calidad de señal (4 barras) y aviso de señal perdida conservando la última posición.
- Gestión de permisos denegados, restringidos y servicios desactivados, con acceso directo a Ajustes.

## Temas
Los 6 temas están documentados con sus HEX exactos y reglas de renderizado en [`docs/05-especificacion-temas.md`](../docs/05-especificacion-temas.md).

**Límite conocido:** MapKit no permite recolorear calles ni agua del mapa base. Los temas actúan sobre el estilo base elegido, la ruta (tres capas), el HUD y un overlay decorativo dibujado con `Canvas`.

## Pendiente
CarPlay (requiere entitlement de Apple), voces originales con TTS licenciado, niebla dibujada sobre el mapa, límites de velocidad e incidencias con fuente licenciada, inglés en `Localizable.xcstrings`.
