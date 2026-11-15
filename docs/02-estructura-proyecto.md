# Estructura del proyecto Xcode — QuestMap IRL

Crear en Xcode un proyecto **iOS App** (SwiftUI, Swift, Storage: SwiftData, Testing: XCTest) con nombre `QuestMapIRL`, iOS 17.0 como mínimo. Después, copiar la carpeta `QuestMapIRL/` de este repositorio dentro del grupo principal del proyecto.

```
QuestMapIRL/
├── App/
│   ├── QuestMapIRLApp.swift          # Punto de entrada, contenedor SwiftData, inyección de servicios
│   └── AppEnvironment.swift          # Composición de dependencias (servicios reales o mock)
├── Core/
│   ├── Theme/
│   │   ├── MapTheme.swift            # Enum MapThemeID + struct MapTheme (tokens)
│   │   ├── ThemeCatalog.swift        # Los 6 temas definidos (colores, iconos, efectos)
│   │   └── AppColors.swift           # Colores de UI semánticos (día/noche)
│   ├── Extensions/
│   │   └── CLLocationCoordinate2D+Ext.swift
│   └── Logging/
│       └── Log.swift
├── Services/
│   ├── Location/
│   │   ├── LocationServiceProtocol.swift
│   │   └── LocationService.swift     # CLLocationManager, permisos, seguimiento
│   ├── Routing/
│   │   ├── RouteServiceProtocol.swift
│   │   └── RouteService.swift        # MKDirections, alternativas, recálculo
│   ├── Search/
│   │   └── PlaceSearchService.swift  # MKLocalSearch
│   ├── Speech/
│   │   └── SpeechService.swift       # AVSpeechSynthesizer, silencio
│   ├── Store/
│   │   └── StoreService.swift        # StoreKit 2 (fase 1.1 completa)
│   └── Sharing/
│       └── ShareLinkBuilder.swift    # Enlaces maps.apple.com
├── Domain/
│   ├── Navigation/
│   │   ├── NavigationEngine.swift    # Progreso sobre la ruta, próxima maniobra, desvío
│   │   ├── NavigationState.swift
│   │   └── ManeuverFormatter.swift   # Texto/icono de maniobra en español
│   ├── FogOfWar/
│   │   └── FogGrid.swift             # Celdas visitadas (geohash simplificado)
│   └── Gamification/
│       ├── Achievement.swift
│       └── ExperienceCalculator.swift
├── Data/
│   ├── Models/
│   │   ├── UserSettings.swift        # @Model
│   │   ├── SavedPlace.swift          # @Model
│   │   ├── VisitedCell.swift         # @Model
│   │   └── TripRecord.swift          # @Model
│   └── Repositories/
│       └── PlacesRepository.swift
├── Features/
│   ├── Onboarding/
│   │   ├── OnboardingView.swift
│   │   └── OnboardingViewModel.swift
│   ├── Home/
│   │   ├── HomeView.swift            # Mapa + búsqueda + accesos rápidos
│   │   ├── HomeViewModel.swift
│   │   └── Components/
│   │       ├── RecenterButton.swift
│   │       └── QuickAccessBar.swift
│   ├── Search/
│   │   ├── SearchView.swift
│   │   └── SearchViewModel.swift
│   ├── RoutePreview/
│   │   ├── RoutePreviewView.swift
│   │   └── RoutePreviewViewModel.swift
│   ├── ActiveNavigation/
│   │   ├── ActiveNavigationView.swift
│   │   ├── ActiveNavigationViewModel.swift
│   │   └── Components/
│   │       ├── ManeuverCard.swift
│   │       └── NavControlsBar.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsViewModel.swift
│   ├── Profile/
│   │   └── ProfileView.swift         # Estadísticas, logros, niebla
│   ├── Paywall/
│   │   ├── PaywallView.swift
│   │   └── PaywallViewModel.swift
│   └── CarPlay/                      # Versión 1.1
│       └── CarPlaySceneDelegate.swift
├── DesignSystem/
│   ├── Components/
│   │   ├── QuestPanel.swift          # Panel estilo HUD reutilizable
│   │   ├── PixelIcon.swift           # Iconos propios (SF Symbols solo como base)
│   │   └── GlowModifier.swift
│   └── Effects/
│       └── MapOverlayView.swift      # Textura/ruido/viñeta sobre el mapa
├── Resources/
│   ├── Assets.xcassets               # Iconos propios, colores de acento
│   ├── Localizable.xcstrings         # Español (base) e inglés
│   └── Info.plist                    # Permisos y UIBackgroundModes
└── Tests/
    ├── NavigationEngineTests.swift
    ├── FogGridTests.swift
    └── ThemeCatalogTests.swift
```

## Reglas de organización
- Un tipo por archivo, salvo enums pequeños ligados a su modelo.
- `Features/` solo contiene vistas y view models; la lógica va a `Services/` o `Domain/`.
- `Domain/` no importa SwiftUI ni MapKit para que sea testeable.
- Los recursos de tema (texturas, iconos) viven en `Assets.xcassets` con prefijo `theme.<id>.`.

## Permisos y capabilities (Info.plist / Signing)
- `NSLocationWhenInUseUsageDescription`: "QuestMap IRL usa tu ubicación para mostrarte el mapa y guiarte por la ruta."
- `UIBackgroundModes`: `location`, `audio`.
- Capabilities: Background Modes (Location updates, Audio), In-App Purchase.
- CarPlay (1.1): entitlement de navegación aprobado por Apple.
