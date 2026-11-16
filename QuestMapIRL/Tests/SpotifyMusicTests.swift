import XCTest
import SwiftData
import UIKit
@testable import QuestMapIRL

/// Cliente de Spotify falso: simula App Remote sin el SDK ni la app de Spotify.
@MainActor
final class FakeSpotifyClient: SpotifyRemoteClient {
    weak var delegate: SpotifyRemoteClientDelegate?
    var isConnected = false
    var isSpotifyInstalled = true
    var currentArtwork: UIImage?
    var token: String?
    var calls: [String] = []
    /// Qué pasa al llamar a connect(): conecta, falla o no responde.
    enum ConnectBehaviour { case succeed, fail(String), silent }
    var connectBehaviour: ConnectBehaviour = .succeed
    var commandsSucceed = true
    var nextAuthResult: SpotifyAuthResult?

    func setAccessToken(_ token: String?) { self.token = token }
    func connect() {
        calls.append("connect")
        switch connectBehaviour {
        case .succeed:
            isConnected = true
            delegate?.spotifyDidConnect()
        case .fail(let message):
            delegate?.spotifyDidFailToConnect(message)
        case .silent:
            break
        }
    }
    func disconnect() { calls.append("disconnect"); isConnected = false }
    func authorize(completion: @escaping (Bool) -> Void) { calls.append("authorize"); completion(isSpotifyInstalled) }
    func authorizationResult(from url: URL) -> SpotifyAuthResult? { nextAuthResult }
    func subscribe() { calls.append("subscribe") }
    func unsubscribe() { calls.append("unsubscribe") }
    func resume(completion: @escaping (Bool) -> Void) { calls.append("resume"); completion(commandsSucceed) }
    func pause(completion: @escaping (Bool) -> Void) { calls.append("pause"); completion(commandsSucceed) }
    func skipToNext(completion: @escaping (Bool) -> Void) { calls.append("next"); completion(commandsSucceed) }
    func skipToPrevious(completion: @escaping (Bool) -> Void) { calls.append("previous"); completion(commandsSucceed) }

    func push(_ state: SpotifyPlayerState) { delegate?.spotifyPlayerStateChanged(state) }
}

@MainActor
final class SpotifyMusicTests: XCTestCase {
    private let configured = SpotifyConfig(clientID: "abc123def456")
    private let song = SpotifyPlayerState(trackURI: "spotify:track:1", title: "Canción", artist: "Artista", isPaused: false,
                                          canSkipNext: true, canSkipPrevious: false)
    private let callback = URL(string: "questmap-irl://spotify-login-callback?access_token=x")!

    private func backend(_ client: FakeSpotifyClient?, tokens: SecretStoring = InMemorySecretStore(),
                         config: SpotifyConfig? = nil) -> SpotifyMusicBackend {
        SpotifyMusicBackend(config: config ?? configured, client: client, tokens: tokens, sleep: { _ in })
    }

    /// Verificaciones instantáneas; el borrado del mensaje (4 s) no, para poder comprobarlo.
    private static let wait: (TimeInterval) async -> Void = { seconds in if seconds >= 4 { try? await Task.sleep(for: .seconds(60)) } }

    private func settle() async { for _ in 0..<6 { await Task.yield() } }

    // MARK: Configuración

    func testMissingOrUnresolvedClientIDIsNotConfiguredAndNeverConnected() async {
        for id in ["", "   ", "$(SPOTIFY_CLIENT_ID)", "con espacios"] {
            XCTAssertFalse(SpotifyConfig(clientID: id).isConfigured, id)
        }
        XCTAssertTrue(configured.isConfigured)
        let client = FakeSpotifyClient()
        let spotify = backend(client, config: SpotifyConfig(clientID: ""))
        XCTAssertEqual(spotify.authorization, .missingConfiguration)
        let result = await spotify.requestAuthorization()
        XCTAssertEqual(result, .missingConfiguration)
        XCTAssertTrue(client.calls.isEmpty, "sin configuración no se abre Spotify ni se conecta")
    }

    func testCallbackURLIsRecognisedOnlyForTheRegisteredRedirect() {
        XCTAssertTrue(SpotifyConfig.isCallback(callback))
        XCTAssertFalse(SpotifyConfig.isCallback(URL(string: "questmap-irl://otra-cosa")!))
        XCTAssertFalse(SpotifyConfig.isCallback(URL(string: "https://spotify-login-callback")!))
        XCTAssertEqual(SpotifyConfig.redirectURL.absoluteString, "questmap-irl://spotify-login-callback")
    }

    func testInfoPlistDeclaresSchemeQueryAndClientIDKeyWithoutSecrets() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let types = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        XCTAssertTrue(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("questmap-irl") == true })
        let queries = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String])
        XCTAssertEqual(queries, ["spotify"])
        XCTAssertNotNil(bundle.object(forInfoDictionaryKey: "QMSpotifyClientID"))
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "SpotifyClientSecret"))
    }

    // MARK: Conexión

    func testNotInstalledIsReportedWithoutPretendingToConnect() async {
        let client = FakeSpotifyClient()
        client.isSpotifyInstalled = false
        let spotify = backend(client)
        XCTAssertEqual(spotify.authorization, .serviceNotInstalled)
        let result = await spotify.requestAuthorization()
        XCTAssertEqual(result, .serviceNotInstalled)
        XCTAssertFalse(client.calls.contains("authorize"))
    }

    func testStoredTokenConnectsSilentlyWithoutOpeningSpotify() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client, tokens: InMemorySecretStore("guardado"))
        let result = await spotify.requestAuthorization()
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(client.token, "guardado")
        XCTAssertFalse(client.calls.contains("authorize"), "no se abre Spotify si el token sirve")
    }

    func testWithoutTokenTheUserIsSentToSpotifyAndTheCallbackCompletesTheConnection() async {
        let client = FakeSpotifyClient()
        let tokens = InMemorySecretStore()
        let spotify = backend(client, tokens: tokens)
        let result = await spotify.requestAuthorization()
        XCTAssertEqual(result, .connecting)
        XCTAssertEqual(client.calls, ["authorize"])
        XCTAssertEqual(spotify.authorization, .connecting)

        client.nextAuthResult = .token("nuevo")
        XCTAssertTrue(spotify.handleOpenURL(callback))
        XCTAssertEqual(tokens.load(), "nuevo", "el token se guarda en el almacén seguro")
        XCTAssertEqual(spotify.authorization, .authorized)
    }

    func testRejectedAuthorizationIsShownAsDeniedOrExpired() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client)
        _ = await spotify.requestAuthorization()
        client.nextAuthResult = .failure("access_denied")
        _ = spotify.handleOpenURL(callback)
        XCTAssertEqual(spotify.authorization, .denied)
        XCTAssertEqual(SpotifyMusicBackend.classify("Invalid token"), .expired)
        XCTAssertEqual(SpotifyMusicBackend.classify("Connection refused"), .connectionError)
    }

    func testOtherAppsURLsAreIgnored() {
        let spotify = backend(FakeSpotifyClient())
        XCTAssertFalse(spotify.handleOpenURL(URL(string: "https://example.com")!))
    }

    func testDisconnectForgetsTheTokenWithoutPausing() async {
        let client = FakeSpotifyClient()
        let tokens = InMemorySecretStore("t")
        let spotify = backend(client, tokens: tokens)
        _ = await spotify.requestAuthorization()
        spotify.disconnectService()
        XCTAssertNil(tokens.load())
        XCTAssertFalse(client.calls.contains("pause"), "desconectar no pausa la música")
        XCTAssertFalse(spotify.canReconnectSilently)
    }

    // MARK: Estado real y capacidades

    func testSnapshotReflectsSpotifyAndItsRestrictions() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client, tokens: InMemorySecretStore("t"))
        _ = await spotify.requestAuthorization()
        client.push(song)
        let snapshot = spotify.snapshot()
        XCTAssertEqual(snapshot.track?.title, "Canción")
        XCTAssertEqual(snapshot.track?.artist, "Artista")
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertTrue(snapshot.capabilities.canNext)
        XCTAssertFalse(snapshot.capabilities.canPrevious, "si Spotify no permite volver atrás, el botón se desactiva")
    }

    func testDisconnectedSnapshotHasNoControls() {
        let snapshot = backend(FakeSpotifyClient()).snapshot()
        XCTAssertNil(snapshot.track)
        XCTAssertEqual(snapshot.capabilities, .none)
    }

    // MARK: Con el minirreproductor (una sola fuente de estado)

    func testModelShowsSpotifyStateAndOnlyEnabledControls() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client, tokens: InMemorySecretStore("t"))
        let model = MusicPlayerModel(backends: [FakeMusicBackend(), spotify], service: .spotify, sleep: Self.wait)
        model.configure(enabled: true, service: .spotify, connected: true)
        await settle()
        client.push(song)
        XCTAssertEqual(model.status, .playing)
        XCTAssertEqual(model.track?.title, "Canción")
        XCTAssertTrue(model.canNext)
        XCTAssertFalse(model.canPrevious)
        model.previous()
        XCTAssertFalse(client.calls.contains("previous"), "una acción no permitida no se envía")
    }

    func testSwitchingServiceStopsTheOldOneClearsMetadataAndDoesNotPause() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client, tokens: InMemorySecretStore("t"))
        let apple = FakeMusicBackend()
        apple.current = MusicSnapshot(track: MusicTrack(id: "a", title: "De Apple", artist: "X"), state: .playing)
        let model = MusicPlayerModel(backends: [apple, spotify], service: .spotify, sleep: Self.wait)
        model.configure(enabled: true, service: .spotify, connected: true)
        await settle()
        client.push(song)
        XCTAssertEqual(model.track?.title, "Canción")

        model.configure(enabled: true, service: .appleMusic, connected: false)
        XCTAssertEqual(model.service, .appleMusic)
        XCTAssertNil(model.track, "no quedan metadatos de Spotify")
        XCTAssertTrue(client.calls.contains("unsubscribe"))
        XCTAssertFalse(client.calls.contains("pause"), "cambiar de servicio no pausa la música")

        client.push(SpotifyPlayerState(trackURI: "z", title: "Tardía", artist: "Y", isPaused: false, canSkipNext: true, canSkipPrevious: true))
        XCTAssertNotEqual(model.track?.title, "Tardía", "Spotify no sobrescribe el estado con Apple Música seleccionada")
    }

    func testConnectingFromTheModelPersistsTheRightService() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client)
        let model = MusicPlayerModel(backends: [FakeMusicBackend(), spotify], service: .spotify, sleep: Self.wait)
        var saved: [(MusicServiceID, Bool)] = []
        model.onConnectedChanged = { saved.append(($0, $1)) }
        model.configure(enabled: true, service: .spotify, connected: false)
        await model.connect()
        XCTAssertEqual(model.status, .connecting)
        client.nextAuthResult = .token("t")
        _ = model.handleOpenURL(callback)
        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(saved.last?.0, .spotify)
        XCTAssertEqual(saved.last?.1, true)
    }

    func testFailedSpotifyCommandKeepsRealState() async {
        let client = FakeSpotifyClient()
        client.commandsSucceed = false
        let spotify = backend(client, tokens: InMemorySecretStore("t"))
        let model = MusicPlayerModel(backends: [spotify], service: .spotify, sleep: Self.wait)
        model.configure(enabled: true, service: .spotify, connected: true)
        await settle()
        client.push(song)
        model.togglePlayPause()
        await settle()
        XCTAssertEqual(model.status, .playing, "no finge que se pausó")
        XCTAssertNotNil(model.message)
    }

    func testReturningFromBackgroundReconnectsSilentlyAndExpiredTokenAsksToReconnect() async {
        let client = FakeSpotifyClient()
        let spotify = backend(client, tokens: InMemorySecretStore("t"))
        let model = MusicPlayerModel(backends: [spotify], service: .spotify, sleep: Self.wait)
        model.configure(enabled: true, service: .spotify, connected: true)
        await settle()
        model.deactivate()                         // segundo plano
        XCTAssertTrue(client.calls.contains("disconnect"))
        client.connectBehaviour = .fail("Token expired")
        model.activate()                           // vuelta a la app
        await settle()
        XCTAssertFalse(client.calls.contains("authorize"), "volver a la app no abre Spotify")
        XCTAssertEqual(model.status, .expired)
    }

    // MARK: Preferencias

    func testServiceAndConnectionsPersistAndOldPreferenceMigrates() throws {
        let legacy = UserSettings()
        legacy.musicConnected = true
        XCTAssertEqual(legacy.connectedMusicServices, [.appleMusic], "la preferencia antigua se respeta")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-sp-\(UUID().uuidString)")
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
            settings.musicService = .spotify
            settings.connectedMusicServices = [.spotify]
            context.insert(settings)
            try PersistenceCommit.save(context)
        }
        let stored = try XCTUnwrap(ModelContext(try open()).fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(stored.musicService, .spotify)
        XCTAssertEqual(stored.connectedMusicServices, [.spotify])
    }

    func testOfficialSDKIsLinkedInTheApp() {
        XCTAssertTrue(SpotifyMusicBackend.isSDKLinked, "la integración usa el SDK real, no un sustituto")
    }

    func testOnlyRealIntegrationsAreOffered() {
        XCTAssertEqual(MusicServiceID.allCases, [.appleMusic, .spotify])
    }
}
