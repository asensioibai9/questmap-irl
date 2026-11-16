import CoreLocation

enum RoutingError: LocalizedError, Equatable {
    case noRoute
    case offline
    case rateLimited
    case timedOut
    case server

    var errorDescription: String? {
        switch self {
        case .noRoute: return "No hemos encontrado ninguna ruta hasta ahí."
        case .offline: return "Sin conexión. Las rutas necesitan internet."
        case .rateLimited: return "Demasiadas peticiones al servicio de rutas. Espera unos segundos."
        case .timedOut: return "El servicio de rutas tarda demasiado en responder. Inténtalo de nuevo."
        case .server: return "El servicio de rutas no responde. Inténtalo de nuevo."
        }
    }
}

extension RoutingError {
    /// Traduce el error de red clasificado al error de rutas con su propio mensaje.
    init(_ error: SearchError) {
        switch error {
        case .offline, .connectionLost: self = .offline
        case .rateLimited: self = .rateLimited
        case .timedOut: self = .timedOut
        default: self = .server
        }
    }
}

/// Un servicio de rutas NO es un renderizador de mapas: solo calcula geometría, pasos,
/// distancia y duración. Cambiar de proveedor no afecta al mapa.
protocol RouteServiceProtocol {
    func routes(from origin: CLLocationCoordinate2D,
                to destination: CLLocationCoordinate2D,
                mode: RouteMode) async throws -> [Route]
}
