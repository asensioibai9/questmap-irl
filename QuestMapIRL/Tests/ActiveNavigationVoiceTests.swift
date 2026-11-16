import XCTest
import CoreLocation
@testable import QuestMapIRL

private struct NoRouteService: RouteServiceProtocol {
    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                mode: RouteMode) async throws -> [Route] { [] }
}

/// Comprueba cómo la navegación usa la voz: orden de las primeras frases, inicio doble y parada.
@MainActor
final class ActiveNavigationVoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let synthesizer = FakeSynthesizer()
    private let session = FakeSession()

    override func setUp() {
        super.setUp()
        suiteName = "ActiveNavigationVoiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let points = [
        CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000),
    ]

    private func makeNavigation() -> ActiveNavigationViewModel {
        let voice = NavigationVoice(defaults: defaults, synthesizer: synthesizer, session: session, voices: { [] },
                                   observeSystemEvents: false)
        let route = Route(
            name: "Prueba", coordinates: points, distanceMeters: 1110, durationSeconds: 120,
            steps: [
                RouteStep(instruction: "Sal hacia el norte", distanceMeters: 555, symbol: "arrow.up", streetName: ""),
                RouteStep(instruction: "Gira a la derecha", distanceMeters: 555, symbol: "arrow.turn.up.right", streetName: ""),
                RouteStep(instruction: "Has llegado", distanceMeters: 0, symbol: "flag", streetName: ""),
            ])
        return ActiveNavigationViewModel(route: route, destinationName: "Casa", destination: points[2], mode: .driving,
                                         routeService: NoRouteService(), speech: voice, useMetric: true)
    }

    private func reading(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    func testOpeningAndFirstInstructionAreSpokenInOrderWithoutCuttingEachOther() {
        let navigation = makeNavigation()
        navigation.start()
        navigation.update(with: reading(points[0]))

        let spoken = synthesizer.spoken.map(\.speechString)
        XCTAssertEqual(spoken.count, 2)
        XCTAssertTrue(spoken[0].hasPrefix("Empezamos la ruta hacia Casa"))
        XCTAssertTrue(spoken[1].lowercased().contains("gira a la derecha"))
        // Solo la frase de apertura corta lo anterior; la primera indicación se encola detrás.
        XCTAssertEqual(synthesizer.stopCount, 1)
    }

    func testStartingTwiceSpeaksTheOpeningOnlyOnce() {
        let navigation = makeNavigation()
        navigation.start()
        navigation.start()
        XCTAssertEqual(synthesizer.spoken.map(\.speechString).filter { $0.hasPrefix("Empezamos") }.count, 1)
    }

    func testCancellingNavigationStopsPendingSpeech() {
        let navigation = makeNavigation()
        navigation.start()
        navigation.update(with: reading(points[0]))
        let stops = synthesizer.stopCount
        navigation.stop()
        XCTAssertEqual(synthesizer.stopCount, stops + 1)
        XCTAssertTrue(navigation.finished)
        XCTAssertGreaterThanOrEqual(session.deactivateCount, 1)
    }

    func testArrivalIsAnnouncedAndFinishes() {
        let navigation = makeNavigation()
        navigation.start()
        navigation.update(with: reading(points[2]))
        XCTAssertTrue(navigation.finished)
        XCTAssertTrue(synthesizer.spoken.map(\.speechString).contains("Has llegado a tu destino."))
    }
}
