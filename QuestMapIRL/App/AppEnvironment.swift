import Foundation

/// Composición de dependencias. Las vistas reciben servicios por protocolo
/// o por tipo concreto observable; en previews y tests se sustituyen por mocks.
@MainActor
final class AppEnvironment {
    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let speech: SpeechService

    /// Servicios reales de producción.
    init() {
        self.locationService = LocationService()
        self.routeService = RouteService()
        self.speech = SpeechService()
    }

    /// Inyección explícita para previews y tests.
    init(locationService: LocationServiceProtocol,
         routeService: RouteServiceProtocol,
         speech: SpeechService) {
        self.locationService = locationService
        self.routeService = routeService
        self.speech = speech
    }
}
