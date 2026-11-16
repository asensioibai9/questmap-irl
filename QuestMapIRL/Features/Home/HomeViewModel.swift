import CoreLocation
import Observation

/// Estado de la pantalla principal: destino, rutas candidatas y su carga. No conoce el
/// renderizador del mapa: la vista traslada este estado al `MapController`.
@MainActor
@Observable
final class HomeViewModel {
    enum RouteState: Equatable {
        case idle, loading, ready, failed(String)
    }

    var destination: Place?
    /// Lugar tocado en el mapa: se muestra su ficha, pero NO se calcula ninguna ruta hasta confirmar "Cómo llegar".
    var selection: Place?
    var routes: [Route] = []
    var selectedRouteID: UUID?
    var mode: RouteMode = .driving
    var routeState: RouteState = .idle
    var headingUp: Bool
    var isFollowing = true
    /// Se incrementa cada vez que llega un conjunto nuevo de rutas (la vista reencuadra el mapa).
    private(set) var routesVersion = 0

    private let routeService: RouteServiceProtocol
    private let locationService: LocationServiceProtocol
    private var routeTask: Task<Void, Never>?

    init(locationService: LocationServiceProtocol, routeService: RouteServiceProtocol, headingUp: Bool) {
        self.locationService = locationService
        self.routeService = routeService
        self.headingUp = headingUp
    }

    var selectedRoute: Route? {
        routes.first { $0.id == selectedRouteID } ?? routes.first
    }

    /// Origen de la ruta: la última lectura REAL del GPS (nunca una posición inventada).
    var origin: CLLocationCoordinate2D? { locationService.currentLocation?.coordinate }

    var errorMessage: String? {
        if case .failed(let message) = routeState { return message }
        return nil
    }

    /// Fija el destino EXACTO elegido por el usuario y calcula rutas.
    func setDestination(_ place: Place) {
        destination = place
        loadRoutes()
    }

    func loadRoutes() {
        routeTask?.cancel()
        guard let destination else { return }
        guard let origin else {
            routeState = .failed("Esperando tu ubicación GPS…")
            return
        }
        routeState = .loading
        let mode = mode
        routeTask = Task {
            do {
                let found = try await routeService.routes(from: origin, to: destination.coordinate, mode: mode)
                guard !Task.isCancelled else { return }
                routes = found
                selectedRouteID = found.first?.id
                routeState = .ready
                routesVersion += 1
            } catch is CancellationError {
                // Petición reemplazada por otra más reciente: se ignora.
            } catch {
                guard !Task.isCancelled else { return }
                routes = []
                selectedRouteID = nil
                routeState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Solo hay una selección activa; la nueva sustituye a la anterior. No toca el destino ni la ruta existentes.
    func select(_ place: Place) {
        selection = place
    }

    func clearSelection() {
        selection = nil
    }

    /// "Cómo llegar": ahora sí se fija el destino (sustituyendo al anterior) y se calculan las rutas.
    func confirmSelection() {
        guard let place = selection else { return }
        selection = nil
        setDestination(place)
    }

    func clearRoute() {
        routeTask?.cancel()
        destination = nil
        routes = []
        selectedRouteID = nil
        routeState = .idle
    }
}
