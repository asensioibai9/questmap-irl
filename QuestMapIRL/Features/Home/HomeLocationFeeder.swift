import CoreLocation
import Observation
import SwiftUI

/// Lleva las lecturas de ubicación al mapa SIN pasar por el `body` de la pantalla principal.
///
/// Antes, `HomeView` observaba directamente cada lectura GPS y cada cambio de brújula (`onChange`, `near:` del buscador,
/// indicador GPS): la pantalla entera — panel inferior, botones y hoja de búsqueda — se volvía a calcular varias veces
/// por segundo mientras había GPS, también al arrastrar el panel o escribir. Ahora:
/// - El mapa recibe cada lectura por aquí (seguimiento de observación propio, fuera de SwiftUI).
/// - El buscador recibe un origen «grueso» que solo cambia cuando te has movido más de 100 m (para ordenar resultados por
///   cercanía no hace falta más), así que la pantalla no se redibuja con cada lectura.
@MainActor
@Observable
final class HomeLocationFeeder {
    /// Origen para búsquedas y avisos: cambia solo al moverse más de `originStep` metros (o al tener la primera lectura).
    private(set) var searchOrigin: CLLocationCoordinate2D?

    @ObservationIgnored let originStep: CLLocationDistance = 100
    @ObservationIgnored private var location: LocationServiceProtocol?
    @ObservationIgnored private var onMove: ((CLLocation, Double) -> Void)?
    @ObservationIgnored private var token = 0

    /// Idempotente: una segunda llamada solo actualiza el destino de las lecturas.
    func start(location: LocationServiceProtocol, onMove: @escaping (CLLocation, Double) -> Void) {
        self.onMove = onMove
        guard self.location == nil else { return }
        self.location = location
        token += 1
        track(token)
        deliver()
    }

    private func track(_ token: Int) {
        guard token == self.token, let location else { return }
        withObservationTracking {
            _ = location.smoothedLocation
            _ = location.displayHeading
            _ = location.currentLocation
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, token == self.token else { return }
                self.deliver()
                self.track(token)
            }
        }
    }

    private func deliver() {
        guard let location else { return }
        if let reading = location.smoothedLocation { onMove?(reading, location.displayHeading) }
        if let fix = location.currentLocation?.coordinate {
            if let origin = searchOrigin {
                let moved = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                    .distance(from: CLLocation(latitude: fix.latitude, longitude: fix.longitude))
                if moved >= originStep { searchOrigin = fix }
            } else {
                searchOrigin = fix
            }
        }
    }
}

/// Indicador GPS que observa la ubicación por sí mismo: con cada lectura solo se redibuja este pequeño indicador.
struct LiveGPSIndicator: View {
    let theme: MapTheme
    let location: LocationServiceProtocol

    var body: some View {
        GPSIndicator(theme: theme, status: location.status, accuracy: location.currentLocation?.horizontalAccuracy)
    }
}
