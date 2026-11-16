import UIKit
import Observation

/// Estado del minirreproductor: ÚNICA fuente de estado, conectada a UN solo servicio a la vez. Refleja SIEMPRE lo que informa
/// el servicio (no es optimista): si una orden no surte efecto, la interfaz sigue mostrando el estado real y avisa con un
/// mensaje discreto. No inicia música por sí mismo.
@MainActor
@Observable
final class MusicPlayerModel {
    enum Status: Equatable {
        case notConfigured       // sin conectar (o permiso aún sin pedir)
        case connecting
        case denied
        case restricted
        case unavailable
        case missingConfiguration  // falta configuración de la app (p. ej. Client ID de Spotify)
        case notInstalled          // la app del servicio no está instalada
        case expired               // autorización caducada: hay que reconectar
        case connectionError       // no se pudo conectar (la app del servicio no está activa…)
        case noPlaybackInfo        // conectado, pero el servicio no informa de ninguna reproducción
        case playing
        case paused
    }

    private(set) var status: Status = .notConfigured
    private(set) var track: MusicTrack?
    private(set) var artwork: UIImage?
    private(set) var capabilities: MusicCapabilities = .all
    private(set) var message: String?
    private(set) var isEnabled = false
    private(set) var isConnected = false
    private(set) var service: MusicServiceID

    /// Se llama cuando cambia la conexión de un servicio para guardarla (SwiftData).
    @ObservationIgnored var onConnectedChanged: ((MusicServiceID, Bool) -> Void)?

    @ObservationIgnored private let backends: [MusicServiceID: MusicBackend]
    @ObservationIgnored private let sleep: (TimeInterval) async -> Void
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var awaitingConnection = false

    init(backends: [MusicBackend], service: MusicServiceID = .appleMusic,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        var map: [MusicServiceID: MusicBackend] = [:]
        for backend in backends { map[backend.serviceID] = backend }
        self.backends = map
        self.service = map[service] != nil ? service : (backends.first?.serviceID ?? .appleMusic)
        self.sleep = sleep
    }

    convenience init(backend: MusicBackend, sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.init(backends: [backend], service: backend.serviceID, sleep: sleep)
    }

    private var current: MusicBackend { backends[service]! }

    /// Servicios con integración real disponibles en esta compilación.
    var availableServices: [MusicServiceID] { MusicServiceID.allCases.filter { backends[$0] != nil } }

    // MARK: - Estado derivado

    var canControl: Bool { status == .playing || status == .paused }
    var isPlaying: Bool { status == .playing }
    var isVisible: Bool { isEnabled }
    var canPlayPause: Bool { canControl && capabilities.canPlayPause }
    var canNext: Bool { canControl && capabilities.canNext }
    var canPrevious: Bool { canControl && capabilities.canPrevious }

    var serviceName: String { service.title }

    var statusText: String {
        switch status {
        case .notConfigured: return "Sin configurar"
        case .connecting: return "Conectando…"
        case .denied: return "Permiso denegado"
        case .restricted: return "Acceso restringido en este iPhone"
        case .unavailable: return "Servicio no disponible"
        case .missingConfiguration: return "Falta configurar \(serviceName)"
        case .notInstalled: return "\(serviceName) no está instalado"
        case .expired: return "Sesión caducada"
        case .connectionError: return "No se pudo conectar"
        case .noPlaybackInfo: return "Conectado · sin información de reproducción"
        case .playing: return "Reproduciendo"
        case .paused: return "Pausado"
        }
    }

    // MARK: - Configuración y cambio de servicio

    /// Aplica las preferencias guardadas. No pide permisos ni toca el reproductor si no hace falta. Si cambia el servicio se
    /// detiene la observación del anterior y se limpian sus metadatos (sin pausar su música).
    func configure(enabled: Bool, service newService: MusicServiceID? = nil, connected: Bool) {
        if let newService, newService != service, backends[newService] != nil { switchService(to: newService) }
        isEnabled = enabled
        isConnected = connected
        if enabled { refresh(); if connected { activate() } } else { deactivate() }
    }

    private func switchService(to newService: MusicServiceID) {
        deactivate()
        awaitingConnection = false
        messageTask?.cancel()
        message = nil
        track = nil
        artwork = nil
        capabilities = .all
        status = .notConfigured
        service = newService
    }

    /// Pide la conexión (con el contexto del botón «Conectar»). No inicia ni cambia la reproducción por sí mismo; algunos
    /// servicios (Spotify) pueden abrir su app y reanudar su música como consecuencia de esta acción explícita.
    func connect() async {
        status = .connecting
        let result = await current.requestAuthorization()
        switch result {
        case .authorized:
            markConnected()
            refresh()
            activate()
        case .connecting:
            // Falta que el usuario vuelva de la app del servicio: se observa hasta que llegue la conexión.
            awaitingConnection = true
            status = .connecting
            observeUntilConnected()
        default:
            awaitingConnection = false
            refresh()
        }
    }

    func disconnect() {
        awaitingConnection = false
        isConnected = false
        onConnectedChanged?(service, false)
        deactivate()
        current.disconnectService()
        track = nil
        artwork = nil
        refresh()
    }

    /// Respuesta de autorización de un servicio (p. ej. al volver de Spotify). Devuelve true si la URL era para la música.
    func handleOpenURL(_ url: URL) -> Bool {
        for backend in backends.values where backend.handleOpenURL(url) { refresh(); return true }
        return false
    }

    private func markConnected() {
        isConnected = true
        awaitingConnection = false
        onConnectedChanged?(service, true)
    }

    private func observeUntilConnected() {
        guard !observing else { return }
        observing = true
        current.startObserving { [weak self] in self?.refresh() }
    }

    /// Empieza a observar el servicio (solo en primer plano, con la opción activada y el servicio conectado).
    func activate() {
        guard isEnabled, isConnected, !observing else { return }
        guard current.authorization == .authorized || current.canReconnectSilently else { return }
        observing = true
        current.startObserving { [weak self] in self?.refresh() }
    }

    func deactivate() {
        guard observing else { return }
        observing = false
        current.stopObserving()
    }

    // MARK: - Lectura

    func refresh() {
        switch current.authorization {
        case .denied: reset(.denied)
        case .restricted: reset(.restricted)
        case .notDetermined: reset(awaitingConnection ? .connecting : .notConfigured)
        case .connecting: reset(.connecting)
        case .missingConfiguration: reset(.missingConfiguration)
        case .serviceNotInstalled: reset(.notInstalled)
        case .expired: reset(.expired)
        case .connectionError: reset(.connectionError)
        case .unavailable: reset(.unavailable)
        case .authorized:
            if awaitingConnection && !isConnected { markConnected() }
            guard isConnected else { reset(.notConfigured); return }
            let snapshot = current.snapshot()
            track = snapshot.track
            capabilities = snapshot.capabilities
            artwork = snapshot.track == nil ? nil : current.currentArtwork(side: 120)
            switch snapshot.state {
            case .playing: status = .playing
            case .paused: status = .paused
            case .stopped: status = snapshot.track == nil ? .noPlaybackInfo : .paused
            }
        }
    }

    private func reset(_ newStatus: Status) {
        status = newStatus
        track = nil
        artwork = nil
        capabilities = .all
    }

    // MARK: - Órdenes (se confirman leyendo el estado real)

    func togglePlayPause() {
        guard canPlayPause else { return }
        let wantsPlaying = status == .paused
        if wantsPlaying { current.play() } else { current.pause() }
        let origin = service
        Task {
            await sleep(0.8)
            guard origin == service else { return }          // el usuario cambió de servicio entretanto
            refresh()
            if (wantsPlaying && status != .playing) || (!wantsPlaying && status == .playing) {
                show("\(serviceName) no ha respondido. Comprueba la app.")
            }
        }
    }

    func next() { skip(forward: true) }
    func previous() { skip(forward: false) }

    private func skip(forward: Bool) {
        guard forward ? canNext : canPrevious else { return }
        let before = track?.id
        if forward { current.skipToNext() } else { current.skipToPrevious() }
        let origin = service
        Task {
            await sleep(1.0)
            guard origin == service else { return }
            refresh()
            if forward, before != nil, track?.id == before, status != .noPlaybackInfo {
                show("No hay otra canción en la cola.")
            }
        }
    }

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            await self?.sleep(4)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
