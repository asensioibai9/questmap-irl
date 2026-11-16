import UIKit
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

/// Estado del reproductor de Spotify ya traducido (independiente del SDK para poder probar la lógica).
struct SpotifyPlayerState: Equatable {
    var trackURI: String?
    var title: String
    var artist: String
    var isPaused: Bool
    var canSkipNext: Bool
    var canSkipPrevious: Bool
}

enum SpotifyAuthResult: Equatable {
    case token(String)
    case failure(String)
}

@MainActor
protocol SpotifyRemoteClientDelegate: AnyObject {
    func spotifyDidConnect()
    func spotifyDidFailToConnect(_ message: String?)
    func spotifyDidDisconnect(_ message: String?)
    func spotifyPlayerStateChanged(_ state: SpotifyPlayerState)
    func spotifyArtworkChanged()
}

/// Capa fina sobre `SPTAppRemote` (Spotify iOS SDK, App Remote). Controla la app de Spotify instalada; la reproducción la hace
/// Spotify, no esta app.
@MainActor
protocol SpotifyRemoteClient: AnyObject {
    var delegate: SpotifyRemoteClientDelegate? { get set }
    var isConnected: Bool { get }
    var isSpotifyInstalled: Bool { get }
    var currentArtwork: UIImage? { get }
    func setAccessToken(_ token: String?)
    func connect()
    func disconnect()
    /// Abre la app de Spotify para autorizar. SEGÚN SPOTIFY, con URI vacía puede reanudar la última canción o elegir una:
    /// solo se llama tras una acción explícita del usuario y avisándole antes. Completa con `false` si Spotify no está instalado.
    func authorize(completion: @escaping (Bool) -> Void)
    func authorizationResult(from url: URL) -> SpotifyAuthResult?
    func subscribe()
    func unsubscribe()
    func resume(completion: @escaping (Bool) -> Void)
    func pause(completion: @escaping (Bool) -> Void)
    func skipToNext(completion: @escaping (Bool) -> Void)
    func skipToPrevious(completion: @escaping (Bool) -> Void)
}

#if canImport(SpotifyiOS)
/// Implementación real con el SDK oficial (v5.0.1 por Swift Package Manager).
@MainActor
final class SDKSpotifyRemoteClient: NSObject, SpotifyRemoteClient {
    weak var delegate: SpotifyRemoteClientDelegate?
    private let appRemote: SPTAppRemote
    private(set) var currentArtwork: UIImage?
    private var artworkTrackURI: String?

    init(config: SpotifyConfig) {
        let configuration = SPTConfiguration(clientID: config.clientID, redirectURL: SpotifyConfig.redirectURL)
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .none)
        super.init()
        appRemote.delegate = self
    }

    var isConnected: Bool { appRemote.isConnected }

    var isSpotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func setAccessToken(_ token: String?) { appRemote.connectionParameters.accessToken = token }
    func connect() { appRemote.connect() }
    func disconnect() { if appRemote.isConnected { appRemote.disconnect() } }

    func authorize(completion: @escaping (Bool) -> Void) {
        appRemote.authorizeAndPlayURI("") { installed in
            Task { @MainActor in completion(installed) }
        }
    }

    func authorizationResult(from url: URL) -> SpotifyAuthResult? {
        guard let parameters = appRemote.authorizationParameters(from: url) else { return nil }
        if let token = parameters[SPTAppRemoteAccessTokenKey] { return .token(token) }
        if let error = parameters[SPTAppRemoteErrorDescriptionKey] { return .failure(error) }
        return nil
    }

    func subscribe() {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, _ in })
        appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
            guard let state = result as? SPTAppRemotePlayerState else { return }
            Task { @MainActor in self?.deliver(state) }
        }
    }

    func unsubscribe() {
        guard appRemote.isConnected else { return }
        appRemote.playerAPI?.unsubscribe(toPlayerState: { _, _ in })
    }

    func resume(completion: @escaping (Bool) -> Void) { appRemote.playerAPI?.resume(callback(completion)) ?? completion(false) }
    func pause(completion: @escaping (Bool) -> Void) { appRemote.playerAPI?.pause(callback(completion)) ?? completion(false) }
    func skipToNext(completion: @escaping (Bool) -> Void) { appRemote.playerAPI?.skip(toNext: callback(completion)) ?? completion(false) }
    func skipToPrevious(completion: @escaping (Bool) -> Void) { appRemote.playerAPI?.skip(toPrevious: callback(completion)) ?? completion(false) }

    private func callback(_ completion: @escaping (Bool) -> Void) -> SPTAppRemoteCallback {
        { _, error in Task { @MainActor in completion(error == nil) } }
    }

    private func deliver(_ state: SPTAppRemotePlayerState) {
        let track = state.track
        let translated = SpotifyPlayerState(
            trackURI: track.uri, title: track.name, artist: track.artist.name, isPaused: state.isPaused,
            canSkipNext: state.playbackRestrictions.canSkipNext, canSkipPrevious: state.playbackRestrictions.canSkipPrevious)
        delegate?.spotifyPlayerStateChanged(translated)
        guard track.uri != artworkTrackURI else { return }
        artworkTrackURI = track.uri
        currentArtwork = nil
        appRemote.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 120, height: 120)) { [weak self] image, _ in
            Task { @MainActor in
                guard let self, self.artworkTrackURI == track.uri else { return }
                self.currentArtwork = image as? UIImage
                self.delegate?.spotifyArtworkChanged()
            }
        }
    }
}

extension SDKSpotifyRemoteClient: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in self.delegate?.spotifyDidConnect() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in self.delegate?.spotifyDidFailToConnect(message) }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in self.delegate?.spotifyDidDisconnect(message) }
    }
}

extension SDKSpotifyRemoteClient: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in self.deliver(playerState) }
    }
}
#endif
