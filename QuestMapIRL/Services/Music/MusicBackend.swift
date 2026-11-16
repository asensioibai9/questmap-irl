import UIKit

/// Servicios de música REALMENTE integrados. No se listan servicios sin una integración pública implementada y comprobada.
enum MusicServiceID: String, CaseIterable, Identifiable {
    case appleMusic
    case spotify
    /// EXPERIMENTAL: cualquier app vía API privada de Apple (solo uso personal; puede no funcionar).
    case systemExperimental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: return "Apple Música"
        case .spotify: return "Spotify"
        case .systemExperimental: return "Cualquier app (experimental)"
        }
    }

    var symbol: String {
        switch self {
        case .appleMusic: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .systemExperimental: return "waveform"
        }
    }
}

/// Estado de la conexión/permiso con un servicio. Cada servicio rellena solo los casos que le corresponden.
enum MusicAuthorization: Equatable {
    case notDetermined, denied, restricted, authorized
    /// Conexión en curso (p. ej. esperando que el usuario vuelva de la app del servicio).
    case connecting
    /// Falta una configuración de la app (p. ej. el Client ID de Spotify).
    case missingConfiguration
    /// La app del servicio es imprescindible y no está instalada.
    case serviceNotInstalled
    /// La autorización caducó o fue rechazada por el servicio: hay que volver a conectar.
    case expired
    /// No se pudo establecer la conexión (la app del servicio no está activa, sin respuesta…).
    case connectionError
    case unavailable
}

enum MusicPlaybackState: Equatable {
    case playing, paused, stopped
}

struct MusicTrack: Equatable {
    var id: String
    var title: String
    var artist: String
}

/// Acciones que el servicio permite AHORA (p. ej. Spotify gratuito no deja saltar canciones). Los controles se desactivan según esto.
struct MusicCapabilities: Equatable {
    var canPlayPause = true
    var canNext = true
    var canPrevious = true

    static let all = MusicCapabilities()
    static let none = MusicCapabilities(canPlayPause: false, canNext: false, canPrevious: false)
}

struct MusicSnapshot: Equatable {
    var track: MusicTrack?
    var state: MusicPlaybackState
    var capabilities: MusicCapabilities = .all
}

/// Lo que necesita el minirreproductor de un servicio de música. Solo lee el estado y envía órdenes de reproducción:
/// NO existe ninguna operación para sustituir la cola ni para empezar una canción concreta. Cada servicio es un adaptador
/// independiente y declara sus capacidades; el minirreproductor solo habla con UNO a la vez.
@MainActor
protocol MusicBackend: AnyObject {
    var serviceID: MusicServiceID { get }
    var authorization: MusicAuthorization { get }
    /// true si, estando conectado, el servicio puede restablecer la conexión sin pedir nada al usuario (token guardado).
    var canReconnectSilently: Bool { get }
    func requestAuthorization() async -> MusicAuthorization
    /// Olvida la conexión de ESTE servicio (credenciales incluidas). No pausa ni cambia la reproducción.
    func disconnectService()
    func snapshot() -> MusicSnapshot
    func currentArtwork(side: CGFloat) -> UIImage?
    func play()
    func pause()
    func skipToNext()
    func skipToPrevious()
    /// Avisa de cambios de canción o de estado. Se llama una vez al volver a primer plano.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
    /// Devuelve true si la URL era una respuesta de autorización de este servicio.
    func handleOpenURL(_ url: URL) -> Bool
}

extension MusicBackend {
    var serviceID: MusicServiceID { .appleMusic }
    var canReconnectSilently: Bool { false }
    func disconnectService() {}
    func handleOpenURL(_ url: URL) -> Bool { false }
}
