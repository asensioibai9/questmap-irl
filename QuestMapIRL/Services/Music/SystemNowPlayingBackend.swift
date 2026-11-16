import Foundation
import UIKit

/// EXPERIMENTAL · API PRIVADA. Intenta leer y controlar lo que suena en CUALQUIER app usando el framework privado de Apple
/// `MediaRemote` (el mismo que usa el Centro de control). Se carga en tiempo de ejecución con `dlopen`/`dlsym`, así que si iOS
/// no lo permite la app NO se rompe: el servicio aparece como «no disponible» o «sin información».
///
/// Avisos (el usuario lo pidió sabiendo esto):
/// - App Store rechaza apps que usan APIs privadas: esto es solo para uso personal, no para publicar.
/// - Apple restringe este acceso a procesos con permisos internos en versiones recientes. Es muy posible que en iOS 17+ las
///   consultas vuelvan vacías o que las órdenes se ignoren. No hay forma de saberlo sin probarlo en el iPhone.
/// - Puede dejar de funcionar con cualquier actualización de iOS.
@MainActor
final class SystemNowPlayingBackend: MusicBackend {
    let serviceID: MusicServiceID = .systemExperimental

    // Firmas de las funciones privadas (no documentadas).
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterFn = @convention(c) () -> Void

    /// Órdenes de MediaRemote.
    private enum Command: UInt32 {
        case play = 0, pause = 1, nextTrack = 4, previousTrack = 5
    }

    private static let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let handle: UnsafeMutableRawPointer? = dlopen(path, RTLD_NOW)

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetIsPlayingFn?
    private let sendCommand: SendCommandFn?
    private let register: RegisterFn?
    private let unregister: UnregisterFn?

    private var title: String?
    private var artist: String?
    private var artwork: UIImage?
    private var isPlaying = false
    private var onChange: (@MainActor () -> Void)?
    private var tokens: [NSObjectProtocol] = []
    /// Para el diagnóstico: si alguna consulta llegó a devolver datos en esta sesión.
    private(set) var hasReceivedAnyInfo = false

    init() {
        getInfo = Self.load("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getIsPlaying = Self.load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
        sendCommand = Self.load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        register = Self.load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        unregister = Self.load("MRMediaRemoteUnregisterForNowPlayingNotifications", as: UnregisterFn.self)
    }

    /// true si las funciones privadas existen en este iOS (no garantiza que iOS deje usarlas).
    var isLoaded: Bool { getInfo != nil && sendCommand != nil }

    var authorization: MusicAuthorization { isLoaded ? .authorized : .unavailable }

    func requestAuthorization() async -> MusicAuthorization {
        guard isLoaded else { return .unavailable }
        fetch()
        return .authorized
    }

    func disconnectService() {
        stopObserving()
        title = nil
        artist = nil
        artwork = nil
        isPlaying = false
    }

    func snapshot() -> MusicSnapshot {
        guard let title, !title.isEmpty else {
            // Puede sonar algo sin que iOS nos lo cuente: no se interpreta como «no hay audio».
            return MusicSnapshot(track: nil, state: isPlaying ? .playing : .stopped,
                                 capabilities: isLoaded ? .all : .none)
        }
        let track = MusicTrack(id: "\(title)|\(artist ?? "")", title: title, artist: artist ?? "")
        return MusicSnapshot(track: track, state: isPlaying ? .playing : .paused, capabilities: .all)
    }

    func currentArtwork(side: CGFloat) -> UIImage? { artwork }

    func play() { send(.play) }
    func pause() { send(.pause) }
    func skipToNext() { send(.nextTrack) }
    func skipToPrevious() { send(.previousTrack) }

    private func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
        // Se vuelve a leer el estado real (el modelo comprueba si la orden surtió efecto).
        fetch()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.fetch()
        }
    }

    // MARK: - Lectura y observación (por notificaciones del sistema, sin sondeo)

    private func fetch() {
        getInfo?(DispatchQueue.main) { [weak self] info in
            let dictionary = info as? [String: Any]
            Task { @MainActor in self?.apply(dictionary) }
        }
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            Task { @MainActor in
                self?.isPlaying = playing
                self?.onChange?()
            }
        }
    }

    private func apply(_ info: [String: Any]?) {
        let newTitle = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let newArtist = info?["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        if let newTitle, !newTitle.isEmpty { hasReceivedAnyInfo = true }
        if newTitle != title || newArtist != artist {
            artwork = (info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap(UIImage.init(data:))
        } else if artwork == nil, let data = info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = UIImage(data: data)
        }
        title = newTitle
        artist = newArtist
        if let rate = info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double { isPlaying = rate > 0 }
        onChange?()
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        self.onChange = onChange
        guard isLoaded else { onChange(); return }
        register?(DispatchQueue.main)
        let center = NotificationCenter.default
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            tokens.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fetch() }
            })
        }
        fetch()
        onChange()
    }

    func stopObserving() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        if onChange != nil { unregister?() }
        onChange = nil
    }
}
