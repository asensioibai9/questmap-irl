import XCTest
import CoreLocation
import Observation
@testable import QuestMapIRL

@MainActor
@Observable
final class FakeLocation: LocationServiceProtocol {
    var authState: LocationAuthState = .authorizedWhenInUse
    var currentLocation: CLLocation?
    var smoothedLocation: CLLocation?
    var displayHeading: Double = 0
    var quality: GPSQuality = .good
    var status: LocationStatus = .available
    var accuracyMode: LocationAccuracyMode = .full
    var isSignalLost = false
    var diagnosticSummary = ""
    @ObservationIgnored var started: [LocationMode] = []
    @ObservationIgnored var modes: [LocationMode] = []

    func requestWhenInUseAuthorization() {}
    func start(mode: LocationMode) { started.append(mode) }
    func setMode(_ mode: LocationMode) { modes.append(mode) }
    func stop() {}
    func refreshNow() {}
    func requestTemporaryFullAccuracy() {}
}

private final class StubRoutes: RouteServiceProtocol, @unchecked Sendable {
    var calls: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
    var result: [Route] = []
    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] {
        calls.append((origin, destination))
        return result
    }
}

/// El centro de navegación funciona SIN ninguna vista: es lo que permite que CarPlay y el iPhone compartan una sola sesión.
@MainActor
final class NavigationHubTests: XCTestCase {
    private var synthesizer: FakeSynthesizer!
    private var location: FakeLocation!
    private var routes: StubRoutes!
    private var hub: NavigationHub!
    private var stored: [TripSummary] = []
    private var defaults: UserDefaults!

    private let points = [
        CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000),
    ]
    private let home = Place(id: "h", name: "Casa", subtitle: "Calle 1", latitude: 40.4100, longitude: -3.7000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "hub-\(UUID().uuidString)")
        synthesizer = FakeSynthesizer()
        location = FakeLocation()
        routes = StubRoutes()
        stored = []
        let voice = NavigationVoice(defaults: defaults, synthesizer: synthesizer, session: FakeSession(), voices: { [] },
                                    observeSystemEvents: false)
        hub = NavigationHub(location: location, routeService: routes, speech: voice, speedLimits: nil,
                            tripStore: { [unowned self] in self.stored.append($0) })
    }

    private func route() -> Route {
        Route(name: "Prueba", coordinates: points, distanceMeters: 1110, durationSeconds: 120, steps: [
            RouteStep(instruction: "Sal hacia el norte", distanceMeters: 555, symbol: "arrow.up", streetName: ""),
            RouteStep(instruction: "Gira a la derecha", distanceMeters: 555, symbol: "arrow.turn.up.right", streetName: ""),
            RouteStep(instruction: "Has llegado", distanceMeters: 0, symbol: "flag", streetName: ""),
        ])
    }

    private func reading(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    private func settle() async { for _ in 0..<8 { await Task.yield() } }

    // MARK: Una sola sesión

    func testStartCreatesOneSessionAndRequestsPreciseLocation() {
        hub.start(route: route(), destination: home, mode: .driving)
        XCTAssertNotNil(hub.session)
        XCTAssertEqual(hub.destination, home)
        XCTAssertEqual(hub.startToken, 1)
        XCTAssertEqual(location.started.last, .navigating)
    }

    func testStartingAgainReplacesTheSessionInsteadOfCreatingASecondOne() {
        hub.start(route: route(), destination: home, mode: .driving)
        let first = hub.session
        hub.start(route: route(), destination: home, mode: .driving)
        XCTAssertNotNil(hub.session)
        XCTAssertFalse(hub.session === first)
        XCTAssertEqual(hub.endToken, 1, "la anterior se cerró una sola vez")
        XCTAssertEqual(hub.startToken, 2)
    }

    func testOpeningPhraseIsSpokenOnlyOnceEvenWithManyReadings() async {
        hub.start(route: route(), destination: home, mode: .driving)
        location.currentLocation = reading(points[0])
        await settle()
        location.currentLocation = reading(CLLocationCoordinate2D(latitude: 40.4010, longitude: -3.7000))
        await settle()
        let openings = synthesizer.spoken.filter { $0.speechString.hasPrefix("Empezamos la ruta") }
        XCTAssertEqual(openings.count, 1, "sin indicaciones de voz dobles")
    }

    // MARK: Alimentación por GPS sin vistas

    func testRealLocationReadingsFeedTheSessionWithoutAnyView() async {
        hub.start(route: route(), destination: home, mode: .driving)
        let before = hub.session?.snapshot.remainingMeters ?? 0
        location.currentLocation = reading(CLLocationCoordinate2D(latitude: 40.4060, longitude: -3.7000))
        await settle()
        let after = hub.session?.snapshot.remainingMeters ?? 0
        XCTAssertGreaterThan(before, after, "la posición real avanza el progreso")
        XCTAssertLessThan(after, 700)
    }

    func testReadingsAreIgnoredOnceTheSessionEnded() async {
        hub.start(route: route(), destination: home, mode: .driving)
        hub.stop()
        location.currentLocation = reading(points[1])
        await settle()
        XCTAssertNil(hub.session)
    }

    // MARK: Fin, cancelación y viajes

    func testStopEndsOnceAndReleasesGPSAndVoice() {
        hub.start(route: route(), destination: home, mode: .driving)
        hub.stop()
        XCTAssertNil(hub.session)
        XCTAssertEqual(hub.endToken, 1)
        XCTAssertFalse(hub.lastEndWasArrival)
        XCTAssertEqual(location.modes.last, .idle)
        XCTAssertGreaterThan(synthesizer.stopCount, 0)
        hub.stop()
        XCTAssertEqual(hub.endToken, 1, "terminar dos veces no duplica nada")
    }

    func testArrivalEndsTheSessionAndSavesTheTripOnce() async {
        hub.start(route: route(), destination: home, mode: .driving)
        location.currentLocation = reading(points[0])
        await settle()
        location.currentLocation = reading(points[1])
        await settle()
        location.currentLocation = reading(points[2])
        await settle()
        XCTAssertNil(hub.session)
        XCTAssertTrue(hub.lastEndWasArrival)
        XCTAssertEqual(stored.count, 1)
    }

    func testTinyCancelledTripIsNotSaved() {
        hub.start(route: route(), destination: home, mode: .driving)
        hub.stop()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: Vista previa

    func testPreviewNeedsARealLocationAndNeverInventsAnOrigin() async {
        routes.result = [route()]
        do {
            _ = try await hub.previewRoutes(to: home)
            XCTFail("Sin ubicación no hay origen")
        } catch {
            XCTAssertTrue(routes.calls.isEmpty)
        }
        location.currentLocation = reading(points[0])
        let found = try? await hub.previewRoutes(to: home)
        XCTAssertEqual(found?.count, 1)
        XCTAssertEqual(routes.calls.first?.0.latitude ?? 0, 40.4, accuracy: 1e-9)
    }
}
