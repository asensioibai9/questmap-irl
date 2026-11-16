import MediaPlayer
import UIKit

/// App Música del sistema vía `MPMusicPlayerController.systemMusicPlayer` (framework MediaPlayer, API pública).
/// Controla y observa el reproductor de la app Música; NO ve ni controla Spotify ni ninguna otra app. Requiere el permiso
/// de biblioteca multimedia (`NSAppleMusicUsageDescription`); no necesita entitlement ni cuenta de desarrollador de pago.
///
/// Límite conocido y sin verificar en dispositivo: con canciones en streaming que no están en la biblioteca, el sistema puede
/// no devolver `nowPlayingItem`; en ese caso la app lo indica como «sin información de reproducción».
@MainActor
final class AppleMusicBackend: MusicBackend {
    private var tokens: [NSObjectProtocol] = []
    private var generating = false

    private var player: MPMusicPlayerController { .systemMusicPlayer }

    var authorization: MusicAuthorization {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> MusicAuthorization {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                let mapped: MusicAuthorization
                switch status {
                case .authorized: mapped = .authorized
                case .restricted: mapped = .restricted
                case .notDetermined: mapped = .notDetermined
                default: mapped = .denied
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    func snapshot() -> MusicSnapshot {
        // El reproductor solo se toca con permiso concedido.
        guard authorization == .authorized else { return MusicSnapshot(track: nil, state: .stopped) }
        let state: MusicPlaybackState
        switch player.playbackState {
        case .playing, .seekingForward, .seekingBackward: state = .playing
        case .paused, .interrupted: state = .paused
        default: state = .stopped
        }
        var track: MusicTrack?
        if let item = player.nowPlayingItem, let title = item.title, !title.isEmpty {
            track = MusicTrack(id: String(item.persistentID), title: title, artist: item.artist ?? item.albumArtist ?? "")
        }
        return MusicSnapshot(track: track, state: state)
    }

    func currentArtwork(side: CGFloat) -> UIImage? {
        guard authorization == .authorized else { return nil }
        return player.nowPlayingItem?.artwork?.image(at: CGSize(width: side, height: side))
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func skipToNext() { player.skipToNextItem() }
    func skipToPrevious() { player.skipToPreviousItem() }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        guard authorization == .authorized else { return }
        player.beginGeneratingPlaybackNotifications()
        generating = true
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange] {
            tokens.append(center.addObserver(forName: name, object: player, queue: .main) { _ in
                Task { @MainActor in onChange() }
            })
        }
        onChange()
    }

    func stopObserving() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        if generating {
            player.endGeneratingPlaybackNotifications()
            generating = false
        }
    }
}
