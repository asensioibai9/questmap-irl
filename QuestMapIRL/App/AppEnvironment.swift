import Foundation

/// Composición de dependencias. Las vistas reciben servicios por protocolo
/// o por tipo concreto observable; en previews y tests se sustituyen por mocks.
@MainActor
final class AppEnvironment {
    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let speech: SpeechService
    let store: StoreService

    init(
        locationService: LocationServiceProtocol = LocationService(),
        routeService: RouteServiceProtocol = RouteService(),
        speech: SpeechService = SpeechService(),
        store: StoreService = StoreService()
    ) {
        self.locationService = locationService
        self.routeService = routeService
        self.speech = speech
        self.store = store
    }
}
