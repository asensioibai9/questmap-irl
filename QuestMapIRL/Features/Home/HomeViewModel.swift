import MapKit
import SwiftUI
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var destination: CLLocationCoordinate2D?
    var destinationName = "Destino"
    var routes: [RouteOption] = []
    var selectedRouteID: UUID?
    var mode: RouteMode = .driving
    var errorMessage: String?
    var isLoadingRoutes = false

    private let routeService: RouteServiceProtocol
    private let locationService: LocationServiceProtocol

    init(locationService: LocationServiceProtocol, routeService: RouteServiceProtocol) {
        self.locationService = locationService
        self.routeService = routeService
    }

    var selectedRoute: RouteOption? {
        routes.first { $0.id == selectedRouteID } ?? routes.first
    }

    var origin: CLLocationCoordinate2D? { locationService.currentLocation?.coordinate }

    /// Recentra la cámara en el usuario con una animación suave.
    func recenter() {
        withAnimation(.smooth(duration: 0.6)) {
            cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
        }
    }

    /// Fija destino (desde búsqueda o pulsación larga) y calcula rutas.
    func setDestination(_ coordinate: CLLocationCoordinate2D, name: String = "Destino") {
        destination = coordinate
        destinationName = name
        Task { await loadRoutes() }
    }

    func loadRoutes() async {
        guard let origin, let destination else {
            errorMessage = "Esperando tu ubicación GPS…"
            return
        }
        isLoadingRoutes = true
        defer { isLoadingRoutes = false }
        do {
            routes = try await routeService.routes(from: origin, to: destination, mode: mode)
            selectedRouteID = routes.first?.id
            errorMessage = nil
            if let rect = routes.first?.route.polyline.boundingMapRect {
                withAnimation(.smooth) {
                    cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.3, dy: -rect.height * 0.3))
                }
            }
        } catch {
            routes = []
            errorMessage = error.localizedDescription
        }
    }

    func clearRoute() {
        destination = nil
        routes = []
        selectedRouteID = nil
        recenter()
    }
}
