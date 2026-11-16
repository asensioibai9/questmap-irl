import XCTest
import SwiftData
import UIKit
@testable import QuestMapIRL

@MainActor
final class FakeMusicBackend: MusicBackend {
    var authorization: MusicAuthorization = .authorized
    var nextAuthorization: MusicAuthorization = .authorized
    var current = MusicSnapshot(track: nil, state: .stopped)
    /// Si es false, las órdenes no cambian el estado (simula un servicio que ignora el comando).
    var obeysCommands = true
    private(set) var calls: [String] = []
    private(set) var observing = false
    private var onChange: (@MainActor () -> Void)?

    func requestAuthorization() async -> MusicAuthorization {
        calls.append("request")
        authorization = nextAuthorization
        return nextAuthorization
    }
    func snapshot() -> MusicSnapshot { current }
    func currentArtwork(side: CGFloat) -> UIImage? { nil }
    func play() { calls.append("play"); if obeysCommands { current.state = .playing } }
    func pause() { calls.append("pause"); if obeysCommands { current.state = .paused } }
    func skipToNext() { calls.append("next"); if obeysCommands { current.track = MusicTrack(id: "2", title: "Otra", artist: "B") } }
    func skipToPrevious() { calls.append("previous") }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { calls.append("observe"); observing = true; self.onChange = onChange; onChange() }
    func stopObserving() { calls.append("stopObserving"); observing = false; onChange = nil }
    func serviceChanged() { onChange?() }
}

@MainActor
final class MusicPlayerTests: XCTestCase {
    private var backend: FakeMusicBackend!
    private var model: MusicPlayerModel!
    private let song = MusicTrack(id: "1", title: "Canción real", artist: "Artista real")

    override func setUp() {
        super.setUp()
        backend = FakeMusicBackend()
        // La espera de verificación es instantánea; la de borrado del mensaje (4 s) no, para poder comprobarlo.
        model = MusicPlayerModel(backend: backend, sleep: { seconds in if seconds >= 4 { try? await Task.sleep(for: .seconds(60)) } })
    }

    private func settle() async { for _ in 0..<5 { await Task.yield() } }

    // MARK: Nada automático

    func testConfiguringAndShowingNeverStartsOrChangesPlayback() {
        backend.current = MusicSnapshot(track: song, state: .paused)
        model.configure(enabled: true, connected: true)
        model.activate()
        model.refresh()
        XCTAssertFalse(backend.calls.contains { ["play", "pause", "next", "previous"].contains($0) },
                       "mostrar el reproductor no inicia música ni toca la cola")
        XCTAssertEqual(model.status, .paused)
    }

    func testConnectOnlyAsksForPermission() async {
        model.configure(enabled: true, connected: false)
        var saved: [Bool] = []
        model.onConnectedChanged = { _, connected in saved.append(connected) }
        await model.connect()
        XCTAssertEqual(backend.calls.first, "request")
        XCTAssertFalse(backend.calls.contains("play"))
        XCTAssertEqual(saved, [true])
        XCTAssertTrue(model.isConnected)
    }

    // MARK: Estados reales

    func testStatesFollowTheServiceNotAssumptions() {
        model.configure(enabled: true, connected: true)
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.refresh()
        XCTAssertEqual(model.status, .playing)
        XCTAssertEqual(model.track, song)
        backend.current = MusicSnapshot(track: song, state: .paused)
        model.refresh()
        XCTAssertEqual(model.status, .paused)
    }

    func testNoMetadataIsNotTreatedAsNoAudio() {
        model.configure(enabled: true, connected: true)
        backend.current = MusicSnapshot(track: nil, state: .playing)   // suena algo pero sin datos de la canción
        model.refresh()
        XCTAssertEqual(model.status, .playing)
        XCTAssertNil(model.track)
        backend.current = MusicSnapshot(track: nil, state: .stopped)
        model.refresh()
        XCTAssertEqual(model.status, .noPlaybackInfo)
        XCTAssertFalse(model.canControl, "sin reproducción informada no hay controles activos")
    }

    func testPermissionStates() async {
        model.configure(enabled: true, connected: false)
        backend.nextAuthorization = .denied
        await model.connect()
        XCTAssertEqual(model.status, .denied)
        XCTAssertFalse(model.isConnected)
        backend.nextAuthorization = .restricted
        await model.connect()
        XCTAssertEqual(model.status, .restricted)
        XCTAssertNil(model.track, "sin permiso no hay datos")
    }

    func testPermissionRevokedInSystemSettingsIsDetectedOnRefresh() {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: true)
        XCTAssertEqual(model.status, .playing)
        backend.authorization = .denied
        model.refresh()
        XCTAssertEqual(model.status, .denied)
        XCTAssertNil(model.track)
    }

    func testDisconnectedShowsNotConfiguredEvenIfPermissionExists() {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: false)
        XCTAssertEqual(model.status, .notConfigured)
        XCTAssertNil(model.track)
    }

    // MARK: Órdenes confirmadas por el servicio

    func testPauseAndResumeAreConfirmedByReadingTheState() async {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: true)
        model.togglePlayPause()
        await settle()
        XCTAssertEqual(model.status, .paused)
        XCTAssertNil(model.message)
        model.togglePlayPause()
        await settle()
        XCTAssertEqual(model.status, .playing)
    }

    func testFailedCommandKeepsRealStateAndShowsAMessage() async {
        backend.current = MusicSnapshot(track: song, state: .playing)
        backend.obeysCommands = false
        model.configure(enabled: true, connected: true)
        model.togglePlayPause()
        await settle()
        XCTAssertEqual(model.status, .playing, "la interfaz no finge que se pausó")
        XCTAssertNotNil(model.message)
    }

    func testNextChangesTheTrackAndWhenNothingChangesItSaysSo() async {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: true)
        model.next()
        await settle()
        XCTAssertEqual(model.track?.id, "2")
        XCTAssertNil(model.message)
        backend.obeysCommands = false
        model.next()
        await settle()
        XCTAssertNotNil(model.message)
    }

    func testCommandsAreIgnoredWhenNotAvailable() {
        model.configure(enabled: true, connected: true)         // sin reproducción
        model.togglePlayPause(); model.next(); model.previous()
        XCTAssertTrue(backend.calls.filter { ["play", "pause", "next", "previous"].contains($0) }.isEmpty)
    }

    // MARK: Cambios hechos fuera de la app y ciclo de vida

    func testChangesMadeInTheServiceAreReflected() {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: true)
        model.activate()
        backend.current = MusicSnapshot(track: MusicTrack(id: "9", title: "Nueva", artist: "C"), state: .playing)
        backend.serviceChanged()
        XCTAssertEqual(model.track?.title, "Nueva")
    }

    func testObservationOnlyRunsWhenEnabledConnectedAndAuthorizedAndStopsOnDeactivate() {
        model.configure(enabled: false, connected: true)
        model.activate()
        XCTAssertFalse(backend.observing)
        model.configure(enabled: true, connected: true)
        model.activate()
        XCTAssertTrue(backend.observing)
        model.deactivate()
        XCTAssertFalse(backend.observing)
        backend.authorization = .denied
        model.activate()
        XCTAssertFalse(backend.observing)
    }

    func testDisconnectStopsObservingAndClearsData() {
        backend.current = MusicSnapshot(track: song, state: .playing)
        model.configure(enabled: true, connected: true)
        model.activate()
        model.disconnect()
        XCTAssertFalse(backend.observing)
        XCTAssertNil(model.track)
        XCTAssertEqual(model.status, .notConfigured)
    }

    func testHiddenWhenSettingIsOff() {
        model.configure(enabled: false, connected: true)
        XCTAssertFalse(model.isVisible)
    }

    // MARK: Ajustes persistentes

    func testSettingsDefaultToHiddenAndSurviveReopeningTheStore() throws {
        let defaults = UserSettings()
        XCTAssertFalse(defaults.showMiniPlayer)
        XCTAssertFalse(defaults.musicConnected)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("m.store")
        var keep: [ModelContainer] = []
        func open() throws -> ModelContainer {
            let c = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
            keep.append(c); return c
        }
        do {
            let context = ModelContext(try open())
            let settings = UserSettings()
            settings.showMiniPlayer = true
            settings.musicConnected = true
            context.insert(settings)
            try PersistenceCommit.save(context)
        }
        let stored = try XCTUnwrap(ModelContext(try open()).fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertTrue(stored.showMiniPlayer)
        XCTAssertTrue(stored.musicConnected)
        XCTAssertEqual(stored.musicServiceRaw, "appleMusic")
    }

    func testInfoPlistExplainsWhyMusicIsAccessed() throws {
        let text = try XCTUnwrap(Bundle(for: AppEnvironment.self).object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") as? String)
        XCTAssertFalse(text.isEmpty)
    }
}
