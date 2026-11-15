import MapKit

enum RouteMode: String, CaseIterable, Identifiable {
    case driving
    case walking

    var id: String { rawValue }

    var mkTransport: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        }
    }

    var title: String {
        switch self {
        case .driving: return "Coche"
        case .walking: return "A pie"
        }
    }
}

struct RouteOption: Identifiable {
    let id = UUID()
    let route: MKRoute
    var distanceKm: Double { route.distance / 1000 }
    var etaMinutes: Int { Int((route.expectedTravelTime / 60).rounded()) }
    var name: String { route.name.isEmpty ? "Ruta" : route.name }
}

protocol RouteServiceProtocol {
    func routes(from origin: CLLocationCoordinate2D,
                to destination: CLLocationCoordinate2D,
                mode: RouteMode) async throws -> [RouteOption]
}

/// Rutas reales con Apple Maps Directions (MKDirections).
struct RouteService: RouteServiceProtocol {
    enum RouteError: LocalizedError {
        case noRoutes
        var errorDescription: String? { "No hemos encontrado ninguna ruta para ese destino." }
    }

    func routes(from origin: CLLocationCoordinate2D,
                to destination: CLLocationCoordinate2D,
                mode: RouteMode) async throws -> [RouteOption] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = mode.mkTransport
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        let options = response.routes.map { RouteOption(route: $0) }
        guard !options.isEmpty else { throw RouteError.noRoutes }
        return options.sorted { $0.etaMinutes < $1.etaMinutes }
    }
}
