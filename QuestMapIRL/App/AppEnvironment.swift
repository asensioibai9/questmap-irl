import Foundation

/// Composición de dependencias. Cada servicio es independiente del renderizador del mapa y se
/// puede sustituir (proveedor de rutas, de búsqueda, de ubicación) sin tocar la interfaz.
@MainActor
final class AppEnvironment {
    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let placeSearch: PlaceSearchProviding
    let speech: SpeechService
    let network: NetworkMonitor

    /// Servicios reales de producción.
    init() {
        self.locationService = LocationService()
        self.routeService = OSRMRouteService()
        self.placeSearch = PhotonSearchService()
        self.speech = SpeechService()
        self.network = NetworkMonitor()
    }

    /// Inyección explícita para previews y tests.
    init(locationService: LocationServiceProtocol,
         routeService: RouteServiceProtocol,
         placeSearch: PlaceSearchProviding,
         speech: SpeechService,
         network: NetworkMonitor) {
        self.locationService = locationService
        self.routeService = routeService
        self.placeSearch = placeSearch
        self.speech = speech
        self.network = network
    }
}
