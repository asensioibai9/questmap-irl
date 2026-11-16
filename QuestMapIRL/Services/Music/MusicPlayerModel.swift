import UIKit
import Observation

/// Estado del minirreproductor. Refleja SIEMPRE lo que informa el servicio (no es optimista): si una orden no surte efecto,
/// la interfaz sigue mostrando el estado real y avisa con un mensaje discreto. No inicia música por sí mismo.
@MainActor
@Observable
final class MusicPlayerModel {
    enum Status: Equatable {
        case notConfigured       // sin conectar (o permiso aún sin pedir)
        case connecting
        case denied
        case restricted
        case unavailable
        case noPlaybackInfo      // conectado, pero el sistema no informa de ninguna reproducción
        case playing
        case paused
    }

    private(set) var status: Status = .notConfigured
    private(set) var track: MusicTrack?
    private(set) var artwork: UIImage?
    private(set) var message: String?
    private(set) var isEnabled = false
    private(set) var isConnected = false

    /// Se llama cuando cambia la conexión para guardarla (SwiftData).
    @ObservationIgnored var onConnectedChanged: ((Bool) -> Void)?

    @ObservationIgnored private let backend: MusicBackend
    @ObservationIgnored private let sleep: (TimeInterval) async -> Void
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var observing = false

    init(backend: MusicBackend, sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.backend = backend
        self.sleep = sleep
    }

    // MARK: - Estado derivado

    var canControl: Bool { status == .playing || status == .paused }
    var isPlaying: Bool { status == .playing }
    var isVisible: Bool { isEnabled }

    var serviceName: String { "Apple Música" }

    var statusText: String {
        switch status {
        case .notConfigured: return "Sin configurar"
        case .connecting: return "Conectando…"
        case .denied: return "Permiso denegado"
        case .restricted: return "Acceso restringido en este iPhone"
        case .unavailable: return "Servicio no disponible"
        case .noPlaybackInfo: return "Conectado · sin información de reproducción"
        case .playing: return "Reproduciendo"
        case .paused: return "Pausado"
        }
    }

    // MARK: - Configuración

    /// Aplica las preferencias guardadas. No pide permisos ni toca el reproductor si no hace falta.
    func configure(enabled: Bool, connected: Bool) {
        isEnabled = enabled
        isConnected = connected
        if enabled { refresh() } else { deactivate() }
    }

    /// Pide el permiso (con el contexto del botón «Conectar»). No inicia ni cambia la reproducción.
    func connect() async {
        status = .connecting
        let result = await backend.requestAuthorization()
        switch result {
        case .authorized:
            isConnected = true
            onConnectedChanged?(true)
            refresh()
            activate()
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .notDetermined: status = .notConfigured
        }
    }

    func disconnect() {
        isConnected = false
        onConnectedChanged?(false)
        deactivate()
        track = nil
        artwork = nil
        refresh()
    }

    /// Empieza a observar el reproductor (solo en primer plano, con permiso y con la opción activada).
    func activate() {
        guard isEnabled, isConnected, backend.authorization == .authorized, !observing else { return }
        observing = true
        backend.startObserving { [weak self] in self?.refresh() }
    }

    func deactivate() {
        guard observing else { return }
        observing = false
        backend.stopObserving()
    }

    // MARK: - Lectura

    func refresh() {
        switch backend.authorization {
        case .denied: reset(.denied)
        case .restricted: reset(.restricted)
        case .notDetermined: reset(.notConfigured)
        case .authorized:
            guard isConnected else { reset(.notConfigured); return }
            let snapshot = backend.snapshot()
            track = snapshot.track
            artwork = snapshot.track == nil ? nil : backend.currentArtwork(side: 120)
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
    }

    // MARK: - Órdenes (se confirman leyendo el estado real)

    func togglePlayPause() {
        guard canControl else { return }
        let wantsPlaying = status == .paused
        if wantsPlaying { backend.play() } else { backend.pause() }
        Task {
            await sleep(0.8)
            refresh()
            if (wantsPlaying && status != .playing) || (!wantsPlaying && status == .playing) {
                show("Música no ha respondido. Comprueba la app Música.")
            }
        }
    }

    func next() { skip(forward: true) }
    func previous() { skip(forward: false) }

    private func skip(forward: Bool) {
        guard canControl else { return }
        let before = track?.id
        if forward { backend.skipToNext() } else { backend.skipToPrevious() }
        Task {
            await sleep(1.0)
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
