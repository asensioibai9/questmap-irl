import Network
import Observation

/// Estado de conectividad para avisar de "sin conexión" en mapa, búsqueda y rutas.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "questmap.network"))
    }

    deinit { monitor.cancel() }
}
