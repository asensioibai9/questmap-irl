import XCTest
@testable import QuestMapIRL

/// El adaptador experimental (API privada) no debe romper nada aunque iOS no lo permita.
@MainActor
final class SystemNowPlayingTests: XCTestCase {
    func testLoadsOrReportsUnavailableWithoutCrashing() async {
        let backend = SystemNowPlayingBackend()
        XCTAssertTrue([MusicAuthorization.authorized, .unavailable].contains(backend.authorization))
        let result = await backend.requestAuthorization()
        XCTAssertEqual(result, backend.authorization)
    }

    func testWithoutDataItDoesNotInventASong() {
        let snapshot = SystemNowPlayingBackend().snapshot()
        XCTAssertNil(snapshot.track, "sin datos no hay canción inventada")
    }

    func testIsOfferedAsAThirdServiceAndSwitchingKeepsOneSourceOfState() {
        let model = MusicPlayerModel(backends: [AppleMusicBackend(), SystemNowPlayingBackend()], service: .appleMusic, sleep: { _ in })
        XCTAssertEqual(model.availableServices, [.appleMusic, .systemExperimental])
        model.configure(enabled: true, service: .systemExperimental, connected: false)
        XCTAssertEqual(model.service, .systemExperimental)
        XCTAssertNil(model.track)
    }
}
