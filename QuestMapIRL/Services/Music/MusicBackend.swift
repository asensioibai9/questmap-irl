import UIKit

/// Permiso de acceso a la música del sistema (biblioteca multimedia).
enum MusicAuthorization: Equatable {
    case notDetermined, denied, restricted, authorized
}

enum MusicPlaybackState: Equatable {
    case playing, paused, stopped
}

struct MusicTrack: Equatable {
    var id: String
    var title: String
    var artist: String
}

struct MusicSnapshot: Equatable {
    var track: MusicTrack?
    var state: MusicPlaybackState
}

/// Lo mínimo que necesita el minirreproductor de un servicio de música. Solo lee el estado y envía órdenes de reproducción:
/// NO existe ninguna operación para sustituir la cola ni para empezar una canción concreta.
@MainActor
protocol MusicBackend: AnyObject {
    var authorization: MusicAuthorization { get }
    func requestAuthorization() async -> MusicAuthorization
    func snapshot() -> MusicSnapshot
    func currentArtwork(side: CGFloat) -> UIImage?
    func play()
    func pause()
    func skipToNext()
    func skipToPrevious()
    /// Avisa de cambios de canción o de estado. Se llama una vez al volver a primer plano.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}
