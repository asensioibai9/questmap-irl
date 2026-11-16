import UIKit

/// Adaptador de Spotify para el minirreproductor (Spotify iOS SDK · App Remote). Controla la app de Spotify instalada:
/// lee canción, artista, carátula, estado y restricciones, y envía reanudar/pausar/siguiente/anterior.
///
/// Conexión:
/// 1. Con un token guardado en el Llavero se intenta conectar en silencio (no abre nada ni cambia la reproducción). Solo
///    funciona si la app de Spotify está activa.
/// 2. Si no hay token o no basta, el botón «Conectar» abre Spotify para autorizar. Spotify indica que esa llamada con URI vacía
///    puede reanudar la última canción o elegir una: por eso SOLO ocurre tras una acción explícita del usuario y la interfaz lo
///    avisa antes.
@MainActor
final class SpotifyMusicBackend: MusicBackend, SpotifyRemoteClientDelegate {
    let serviceID: MusicServiceID = .spotify

    private let config: SpotifyConfig
    private let client: SpotifyRemoteClient?
    private let tokens: SecretStoring
    private let sleep: (TimeInterval) async -> Void

    private var state: SpotifyPlayerState?
    private var failure: MusicAuthorization?
    private var awaitingCallback = false
    private var reconnecting = false
    private var onChange: (@MainActor () -> Void)?
    private var connectWaiter: ((Bool) -> Void)?

    init(config: SpotifyConfig = .load(), client: SpotifyRemoteClient?, tokens: SecretStoring = KeychainSecretStore(),
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.config = config
        self.client = client
        self.tokens = tokens
        self.sleep = sleep
        client?.delegate = self
    }

    /// true si el SDK oficial de Spotify está enlazado en esta compilación.
    static var isSDKLinked: Bool {
        #if canImport(SpotifyiOS)
        return true
        #else
        return false
        #endif
    }

    /// Crea el adaptador con el SDK real si está enlazado y hay Client ID.
    static func makeDefault() -> SpotifyMusicBackend {
        let config = SpotifyConfig.load()
        #if canImport(SpotifyiOS)
        let client: SpotifyRemoteClient? = config.isConfigured ? SDKSpotifyRemoteClient(config: config) : nil
        #else
        let client: SpotifyRemoteClient? = nil
        #endif
        return SpotifyMusicBackend(config: config, client: client)
    }

    // MARK: - Estado

    var authorization: MusicAuthorization {
        guard config.isConfigured else { return .missingConfiguration }
        guard let client else { return .unavailable }
        guard client.isSpotifyInstalled else { return .serviceNotInstalled }
        if client.isConnected { return .authorized }
        if awaitingCallback || reconnecting { return .connecting }
        if let failure { return failure }
        return .notDetermined
    }

    var canReconnectSilently: Bool { config.isConfigured && client != nil && tokens.load() != nil }

    func snapshot() -> MusicSnapshot {
        guard let state, client?.isConnected == true else { return MusicSnapshot(track: nil, state: .stopped, capabilities: .none) }
        let track = state.title.isEmpty ? nil : MusicTrack(id: state.trackURI ?? state.title, title: state.title, artist: state.artist)
        return MusicSnapshot(track: track, state: state.isPaused ? .paused : .playing,
                             capabilities: MusicCapabilities(canPlayPause: true, canNext: state.canSkipNext,
                                                             canPrevious: state.canSkipPrevious))
    }

    func currentArtwork(side: CGFloat) -> UIImage? { client?.currentArtwork }

    // MARK: - Conexión

    func requestAuthorization() async -> MusicAuthorization {
        guard config.isConfigured else { return .missingConfiguration }
        guard let client else { return .unavailable }
        guard client.isSpotifyInstalled else { return .serviceNotInstalled }
        failure = nil
        if client.isConnected { return .authorized }
        if let token = tokens.load() {
            client.setAccessToken(token)
            if await connectAndWait(timeout: 6) { return .authorized }
        }
        // Hace falta autorizar en la app de Spotify (acción explícita del usuario).
        awaitingCallback = true
        let installed = await withCheckedContinuation { continuation in
            client.authorize { continuation.resume(returning: $0) }
        }
        guard installed else {
            awaitingCallback = false
            return .serviceNotInstalled
        }
        return .connecting
    }

    /// Respuesta de Spotify con el token (o el error) al volver a la app.
    func handleOpenURL(_ url: URL) -> Bool {
        guard SpotifyConfig.isCallback(url), let client else { return false }
        awaitingCallback = false
        switch client.authorizationResult(from: url) {
        case .token(let token):
            tokens.save(token)
            client.setAccessToken(token)
            reconnecting = true
            client.connect()
        case .failure(let description):
            failure = Self.classify(description, rejected: true)
        case nil:
            failure = .connectionError
        }
        onChange?()
        return true
    }

    func disconnectService() {
        client?.unsubscribe()
        client?.disconnect()
        client?.setAccessToken(nil)
        tokens.clear()
        state = nil
        failure = nil
        awaitingCallback = false
        reconnecting = false
    }

    private func connectAndWait(timeout: TimeInterval) async -> Bool {
        guard let client else { return false }
        reconnecting = true
        let gate = Gate()
        let result: Bool = await withCheckedContinuation { continuation in
            connectWaiter = { value in
                guard gate.open() else { return }
                continuation.resume(returning: value)
            }
            client.connect()
            Task { @MainActor [weak self] in
                await self?.sleep(timeout)
                guard gate.open() else { return }
                self?.connectWaiter = nil
                continuation.resume(returning: false)
            }
        }
        reconnecting = false
        return result
    }

    /// Clasifica un error: si habla de token/autorización, la sesión caducó o se rechazó; si no, es un fallo de conexión.
    static func classify(_ message: String?, rejected: Bool = false) -> MusicAuthorization {
        let text = (message ?? "").lowercased()
        if text.contains("access_denied") || text.contains("denied") { return .denied }
        if rejected || text.contains("token") || text.contains("auth") || text.contains("expired") { return .expired }
        return .connectionError
    }

    // MARK: - Observación

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard let client else { return }
        if client.isConnected {
            client.subscribe()
        } else if let token = tokens.load(), !awaitingCallback {
            // Reconexión silenciosa al volver a la app: no abre Spotify ni cambia su reproducción.
            client.setAccessToken(token)
            reconnecting = true
            client.connect()
        }
        onChange()
    }

    /// Spotify recomienda desconectar App Remote al salir de primer plano. No pausa la música.
    func stopObserving() {
        onChange = nil
        client?.unsubscribe()
        client?.disconnect()
        state = nil
    }

    // MARK: - Órdenes (el resultado real llega con el siguiente estado del reproductor)

    func play() { client?.resume { [weak self] ok in self?.commandFinished(ok) } }
    func pause() { client?.pause { [weak self] ok in self?.commandFinished(ok) } }
    func skipToNext() { client?.skipToNext { [weak self] ok in self?.commandFinished(ok) } }
    func skipToPrevious() { client?.skipToPrevious { [weak self] ok in self?.commandFinished(ok) } }

    private func commandFinished(_ ok: Bool) {
        if !ok { onChange?() }   // el modelo vuelve a leer el estado real y avisa si no cambió
    }

    // MARK: - SpotifyRemoteClientDelegate

    func spotifyDidConnect() {
        reconnecting = false
        failure = nil
        connectWaiter?(true)
        connectWaiter = nil
        if onChange != nil { client?.subscribe() }
        onChange?()
    }

    func spotifyDidFailToConnect(_ message: String?) {
        reconnecting = false
        failure = Self.classify(message)
        connectWaiter?(false)
        connectWaiter = nil
        onChange?()
    }

    func spotifyDidDisconnect(_ message: String?) {
        state = nil
        if message != nil { failure = Self.classify(message) }
        onChange?()
    }

    func spotifyPlayerStateChanged(_ state: SpotifyPlayerState) {
        self.state = state
        onChange?()
    }

    func spotifyArtworkChanged() { onChange?() }
}

/// Permite reanudar una continuación una sola vez.
private final class Gate {
    private var used = false
    func open() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
