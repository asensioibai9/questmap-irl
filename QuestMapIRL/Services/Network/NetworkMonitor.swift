import Network
import Observation

/// Estado de conectividad del sistema (`NWPathMonitor`). Solo informa de lo que iOS dice sobre la
/// red: un servicio lento o saturado NO es "sin conexión" (eso lo clasifica `SearchError`).
///
/// El aviso en pantalla (`showsOfflineNotice`) no aparece por un parpadeo: la red debe seguir sin
/// estar disponible tras un breve margen de gracia (cambios de wifi a 5G, túneles, ascensores…).
@MainActor
@Observable
final class NetworkMonitor {
    enum Reason: Equatable { case none, cellularDenied, wifiDenied, other }

    /// Lectura de la ruta de red, independiente de `NWPath` para poder probarla.
    struct PathState: Equatable {
        var isAvailable: Bool
        var reason: Reason
        /// Descripción sin datos personales: estado, interfaces y restricciones.
        var description: String
    }

    /// Estado instantáneo.
    private(set) var isOnline = true
    /// Verdadero solo cuando la falta de red se ha mantenido más que `graceSeconds`.
    private(set) var showsOfflineNotice = false
    private(set) var reason: Reason = .none
    private(set) var pathDescription = "sin lectura todavía"

    var graceSeconds: Double = 3

    @ObservationIgnored private let monitor: NWPathMonitor?
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var graceTask: Task<Void, Never>?

    init(startMonitoring: Bool = true, diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
        if startMonitoring {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                let state = Self.state(from: path)
                Task { @MainActor in self?.apply(state) }
            }
            monitor.start(queue: DispatchQueue(label: "questmap.network"))
        } else {
            monitor = nil
        }
    }

    deinit { monitor?.cancel() }

    /// Texto del aviso, con la causa real si iOS la indica.
    var noticeText: String {
        switch reason {
        case .cellularDenied:
            return "QuestMap IRL no tiene permiso para usar datos móviles. Actívalo en Ajustes › Datos móviles › QuestMap IRL."
        case .wifiDenied:
            return "La conexión wifi no está disponible para esta app."
        case .none, .other:
            return "Sin conexión a internet: el mapa, la búsqueda y las rutas la necesitan."
        }
    }

    func apply(_ state: PathState) {
        pathDescription = state.description
        isOnline = state.isAvailable
        diagnostics.record(DiagnosticEvent(
            date: Date(), service: "network", operation: "path", outcome: state.isAvailable ? "ok" : "error",
            errorKind: state.isAvailable ? nil : "offline", code: nil, httpStatus: nil, durationMs: 0, attempt: 1,
            note: state.description))

        if state.isAvailable {
            graceTask?.cancel()
            graceTask = nil
            reason = .none
            showsOfflineNotice = false
        } else {
            reason = state.reason
            guard !showsOfflineNotice, graceTask == nil else { return }
            graceTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(graceSeconds))
                guard !Task.isCancelled, !isOnline else { return }
                showsOfflineNotice = true
                graceTask = nil
            }
        }
    }

    nonisolated static func state(from path: NWPath) -> PathState {
        // `requiresConnection` (red que se activa al usarla) no es "sin red": se deja intentar.
        let available = path.status != .unsatisfied
        var reason = Reason.none
        if !available {
            switch path.unsatisfiedReason {
            case .cellularDenied: reason = .cellularDenied
            case .wifiDenied: reason = .wifiDenied
            default: reason = .other
            }
        }
        var interfaces: [String] = []
        if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
        if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("ethernet") }
        let status: String
        switch path.status {
        case .satisfied: status = "satisfied"
        case .unsatisfied: status = "unsatisfied"
        case .requiresConnection: status = "requiresConnection"
        @unknown default: status = "unknown"
        }
        let description = "estado=\(status) interfaces=\(interfaces.joined(separator: "+").isEmpty ? "ninguna" : interfaces.joined(separator: "+")) "
            + "caro=\(path.isExpensive) restringido=\(path.isConstrained)" + (available ? "" : " motivo=\(reason)")
        return PathState(isAvailable: available, reason: reason, description: description)
    }
}
