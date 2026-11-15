import MapKit
import SwiftUI
import Observation

@MainActor
@Observable
final class HomeViewModel {
    enum RouteState: Equatable {
        case idle, loading, ready, failed(String)
    }

    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var destination: CLLocationCoordinate2D?
    var destinationName = "Destino"
    var routes: [RouteOption] = []
    var selectedRouteID: UUID?
    var mode: RouteMode = .driving
    var routeState: RouteState = .idle
    var headingUp: Bool
    var isFollowing = true

    private let routeService: RouteServiceProtocol
    private let locationService: LocationServiceProtocol
    private var routeTask: Task<Void, Never>?

    init(locationService: LocationServiceProtocol, routeService: RouteServiceProtocol, headingUp: Bool) {
        self.locationService = locationService
        self.routeService = routeService
        self.headingUp = headingUp
    }

    var selectedRoute: RouteOption? {
        routes.first { $0.id == selectedRouteID } ?? routes.first
    }

    var origin: CLLocationCoordinate2D? { locationService.smoothedLocation?.coordinate }

    var errorMessage: String? {
        if case .failed(let message) = routeState { return message }
        return nil
    }

    /// Recentra la cámara en el usuario según la orientación elegida.
    func recenter() {
        isFollowing = true
        withAnimation(.smooth(duration: 0.6)) {
            cameraPosition = .userLocation(followsHeading: headingUp, fallback: .automatic)
        }
    }

    func toggleHeadingUp() {
        headingUp.toggle()
        recenter()
    }

    /// Fija destino (desde búsqueda o pulsación larga) y calcula rutas.
    func setDestination(_ coordinate: CLLocationCoordinate2D, name: String = "Destino") {
        destination = coordinate
        destinationName = name
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
        routeTask = Task {
            do {
                let found = try await routeService.routes(from: origin, to: destination, mode: mode)
                guard !Task.isCancelled else { return }
                routes = found
                selectedRouteID = found.first?.id
                routeState = .ready
                if let rect = found.first?.route.polyline.boundingMapRect {
                    isFollowing = false
                    withAnimation(.smooth) {
                        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35))
                    }
                }
            } catch is CancellationError {
            } catch {
                routes = []
                routeState = .failed(Self.describe(error))
            }
        }
    }

    func clearRoute() {
        routeTask?.cancel()
        destination = nil
        routes = []
        selectedRouteID = nil
        routeState = .idle
        recenter()
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "Sin conexión. Las rutas necesitan internet." }
        if let mk = error as? MKError {
            switch mk.code {
            case .directionsNotFound, .placemarkNotFound: return "No hemos encontrado ninguna ruta hasta ahí."
            case .loadingThrottled: return "Demasiadas peticiones. Espera unos segundos."
            case .serverFailure: return "El servicio de rutas no responde. Inténtalo de nuevo."
            default: break
            }
        }
        return error.localizedDescription
    }
}
