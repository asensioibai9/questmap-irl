import Foundation

/// Composición de dependencias. Cada servicio es independiente del renderizador del mapa y se
/// puede sustituir (proveedor de rutas, de búsqueda, de ubicación) sin tocar la interfaz.
@MainActor
final class AppEnvironment {
    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let placeSearch: PlaceSearchProviding
    let nearby: NearbySearchProviding
    let speech: SpeechService
    let network: NetworkMonitor
    let speedLimits: SpeedLimitProviding
    let music: MusicPlayerModel

    /// Servicios reales de producción.
    init() {
        self.locationService = LocationService()
        self.routeService = OSRMRouteService()
        self.placeSearch = PhotonSearchService()
        self.nearby = TilePOISearchService()
        self.speech = SpeechService()
        self.network = NetworkMonitor()
        self.speedLimits = ValhallaSpeedLimitService()
        self.music = MusicPlayerModel(backend: AppleMusicBackend())
    }

    /// Inyección explícita para previews y tests.
    init(locationService: LocationServiceProtocol,
         routeService: RouteServiceProtocol,
         placeSearch: PlaceSearchProviding,
         nearby: NearbySearchProviding,
         speech: SpeechService,
         network: NetworkMonitor,
         speedLimits: SpeedLimitProviding = ValhallaSpeedLimitService(),
         music: MusicPlayerModel? = nil) {
        self.locationService = locationService
        self.routeService = routeService
        self.placeSearch = placeSearch
        self.nearby = nearby
        self.speech = speech
        self.network = network
        self.speedLimits = speedLimits
        self.music = music ?? MusicPlayerModel(backend: AppleMusicBackend())
    }
}
