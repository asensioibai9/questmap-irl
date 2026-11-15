# QuestMap IRL — Código del MVP

Código SwiftUI para iOS 17+. **Pendiente de compilar en Xcode**: se ha escrito sin acceso a un Mac, así que la primera compilación puede exigir ajustes menores.

## Montaje en Xcode (un solo comando)
El proyecto Xcode se genera automáticamente con XcodeGen a partir de `project.yml` (en la raíz del repositorio). Ya incluye Info.plist, permisos, Background Modes, entitlements, target de tests y el archivo StoreKit de pruebas.

En un Mac, desde la carpeta raíz:
```bash
sh setup-mac.sh
```
Instala XcodeGen si falta, crea `QuestMapIRL.xcodeproj` y lo abre. Después: elegir un simulador de iPhone y ⌘R.

Sin Mac: sube la carpeta a un repositorio de GitHub; el workflow `.github/workflows/ios-build.yml` compila y ejecuta los tests en un Mac de GitHub y muestra los errores en la pestaña Actions.

Para ejecutar en un iPhone real, pon tu Team ID en `project.yml` (`DEVELOPMENT_TEAM`) y vuelve a ejecutar el script.

## Mapa de módulos
| Carpeta | Contenido |
|---|---|
| `App/` | Entrada, composición de servicios, `RootView` (onboarding → tabs) |
| `Core/Theme` | `MapThemeID`, `MapTheme`, los 6 temas en `ThemeCatalog` |
| `Core/Models` | SwiftData: `UserSettings`, `SavedPlace`, `TripRecord`, `VisitedCell` |
| `Domain/` | Lógica pura testeable: `NavigationEngine`, `FogGrid`, `Achievements` |
| `Services/` | Core Location, MKDirections, MKLocalSearch, voz, StoreKit 2, enlaces |
| `Data/` | `TripRepository` (guarda viajes y niebla) |
| `Features/` | Onboarding, Home, Search, ActiveNavigation, Settings, Profile, Paywall |
| `DesignSystem/` | `MapOverlayView` (capa decorativa del tema) |
| `Tests/` | Motor de navegación, niebla, gamificación y catálogo de temas |

## Flujo
Onboarding (permiso + aviso) → Home (mapa, búsqueda, Casa/Trabajo, pulsación larga) → tarjeta con alternativas de ruta → "Iniciar misión" → navegación a pantalla completa (voz, recálculo, ETA, velocidad) → al llegar o finalizar se guarda `TripRecord` y las celdas de niebla → Perfil muestra estadísticas, nivel y logros.

## Pendiente para versión 1.1
CarPlay (requiere entitlement de Apple), voces originales con TTS licenciado, iconografía propia de marcadores tipo quest/tienda/combustible, niebla avanzada dibujada sobre el mapa, límites de velocidad e incidencias con fuente licenciada, inglés completo en `Localizable.xcstrings`.

## Limitación conocida
MapKit no permite recolorear calles ni agua del mapa base; los temas actúan sobre la ruta, la interfaz y una capa decorativa.
