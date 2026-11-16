import Foundation
import SwiftData

/// Composición de dependencias. Cada servicio es independiente del renderizador del mapa y se
/// puede sustituir (proveedor de rutas, de búsqueda, de ubicación) sin tocar la interfaz.
@MainActor
final class AppEnvironment {
    /// Instancia de producción compartida entre la escena del iPhone y la de CarPlay.
    static let shared = AppEnvironment()

    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let placeSearch: PlaceSearchProviding
    let nearby: NearbySearchProviding
    let speech: SpeechService
    let network: NetworkMonitor
    let speedLimits: SpeedLimitProviding
    let music: MusicPlayerModel
    /// Navegación activa compartida por el iPhone y CarPlay.
    let hub: NavigationHub

    /// Servicios reales de producción.
    init() {
        let location = LocationService()
        let routes = OSRMRouteService()
        let speech = SpeechService()
        let limits = ValhallaSpeedLimitService()
        self.locationService = location
        self.routeService = routes
        self.placeSearch = PhotonSearchService()
        self.nearby = TilePOISearchService()
        self.speech = speech
        self.network = NetworkMonitor()
        self.speedLimits = limits
        self.music = MusicPlayerModel(backends: [AppleMusicBackend(), SpotifyMusicBackend.makeDefault(), SystemNowPlayingBackend()])
        self.hub = NavigationHub(
            location: location, routeService: routes, speech: speech, speedLimits: limits,
            settings: {
                let stored = try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<UserSettings>()).first
                return (stored?.useMetricUnits ?? true, stored?.showSpeedLimit ?? true)
            },
            tripStore: { summary in
                try? TripRepository(context: ContainerFactory.shared.mainContext).save(summary)
            })
    }

    /// Inyección explícita para previews y tests.
    init(locationService: LocationServiceProtocol,
         routeService: RouteServiceProtocol,
         placeSearch: PlaceSearchProviding,
         nearby: NearbySearchProviding,
         speech: SpeechService,
         network: NetworkMonitor,
         speedLimits: SpeedLimitProviding = ValhallaSpeedLimitService(),
         music: MusicPlayerModel? = nil,
         hub: NavigationHub? = nil) {
        self.locationService = locationService
        self.routeService = routeService
        self.placeSearch = placeSearch
        self.nearby = nearby
        self.speech = speech
        self.network = network
        self.speedLimits = speedLimits
        self.music = music ?? MusicPlayerModel(backend: AppleMusicBackend())
        self.hub = hub ?? NavigationHub(location: locationService, routeService: routeService, speech: speech,
                                        speedLimits: speedLimits)
    }
}
