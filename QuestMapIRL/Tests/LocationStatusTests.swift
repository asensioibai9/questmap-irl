import XCTest
import CoreLocation
@testable import QuestMapIRL

// MARK: - Dobles de prueba

final class FakeLocationManager: LocationManaging {
    weak var delegate: CLLocationManagerDelegate?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var desiredAccuracy: CLLocationAccuracy = 0
    var distanceFilter: CLLocationDistance = 0
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var headingFilter: CLLocationDegrees = 0
    var headingOrientation: CLDeviceOrientation = .portrait

    var permissionRequests = 0
    var startCount = 0
    var stopCount = 0
    var oneShotCount = 0
    var fullAccuracyRequests: [String] = []

    func requestWhenInUseAuthorization() { permissionRequests += 1 }
    func startUpdatingLocation() { startCount += 1 }
    func stopUpdatingLocation() { stopCount += 1 }
    func startUpdatingHeading() {}
    func stopUpdatingHeading() {}
    func requestLocation() { oneShotCount += 1 }
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String, completion: ((Error?) -> Void)?) {
        fullAccuracyRequests.append(purposeKey)
        completion?(nil)
    }
}

final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

// MARK: - Lógica pura del estado

final class LocationStatusEvaluatorTests: XCTestCase {
    private func snapshot(_ configure: (inout LocationSnapshot) -> Void) -> LocationStatus {
        var s = LocationSnapshot(auth: .authorizedWhenInUse)
        configure(&s)
        return LocationStatusEvaluator.evaluate(s)
    }

    func testPermissionStatesAreDistinct() {
        XCTAssertEqual(LocationStatusEvaluator.evaluate(LocationSnapshot(auth: .notDetermined)), .requestingPermission)
        XCTAssertEqual(LocationStatusEvaluator.evaluate(LocationSnapshot(auth: .denied)), .denied)
        XCTAssertEqual(LocationStatusEvaluator.evaluate(LocationSnapshot(auth: .restricted)), .restricted)
        XCTAssertEqual(LocationStatusEvaluator.evaluate(LocationSnapshot(auth: .servicesDisabled)), .servicesDisabled)
    }

    func testWaitingForTheFirstFixIsNeverLost() {
        for seconds in [0.0, 2, 10, 60, 600] {
            XCTAssertEqual(snapshot { $0.sinceStart = seconds }, .acquiring, "a los \(seconds) s")
        }
    }

    func testTemporaryErrorOnlyAfterAGraceAndWithoutAnyFix() {
        XCTAssertEqual(snapshot { $0.sinceStart = 5; $0.recentTemporaryError = true }, .acquiring)
        XCTAssertEqual(snapshot { $0.sinceStart = 30; $0.recentTemporaryError = true }, .temporaryError)
    }

    func testStationaryUserWithAnOldFixIsNotLostUntilTheLongLimit() {
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 10; $0.fixAge = 40; $0.moving = false; $0.freshSinceStart = true; $0.sinceStart = 100 }, .available)
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 10; $0.fixAge = 90; $0.moving = false; $0.freshSinceStart = true; $0.sinceStart = 200 }, .lastKnown(ageSeconds: 90))
    }

    func testMovingUserNeedsFrequentReadings() {
        XCTAssertEqual(snapshot { $0.mode = .navigating; $0.hasFix = true; $0.fixAccuracy = 5; $0.fixAge = 8; $0.moving = true; $0.freshSinceStart = true; $0.sinceStart = 60 }, .available)
        XCTAssertEqual(snapshot { $0.mode = .navigating; $0.hasFix = true; $0.fixAccuracy = 5; $0.fixAge = 12; $0.moving = true; $0.freshSinceStart = true; $0.sinceStart = 60 }, .lastKnown(ageSeconds: 12))
    }

    func testOldCachedFixRightAfterStartingMeansUpdatingNotLost() {
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 20; $0.fixAge = 7200; $0.freshSinceStart = false; $0.sinceStart = 3 }, .acquiring)
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 20; $0.fixAge = 7200; $0.freshSinceStart = false; $0.sinceStart = 20 }, .lastKnown(ageSeconds: 7200))
    }

    func testAccuracyDecidesBetweenAvailableLowAndReduced() {
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 15; $0.freshSinceStart = true }, .available)
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 250; $0.freshSinceStart = true }, .lowAccuracy(meters: 250))
        XCTAssertEqual(snapshot { $0.hasFix = true; $0.fixAccuracy = 3000; $0.accuracyMode = .reduced; $0.freshSinceStart = true }, .reducedAccuracy)
    }

    func testDiscardRulesOnlyRejectInvalidReadings() {
        let now = Date()
        XCTAssertNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: 4000, latitude: 40, longitude: -3, timestamp: now, newestAccepted: nil))
        XCTAssertNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: 20, latitude: 40, longitude: -3, timestamp: now.addingTimeInterval(-7200), newestAccepted: nil))
        XCTAssertNotNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: -1, latitude: 40, longitude: -3, timestamp: now, newestAccepted: nil))
        XCTAssertNotNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: 5, latitude: 95, longitude: -3, timestamp: now, newestAccepted: nil))
        XCTAssertNotNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: 5, latitude: 0, longitude: 0, timestamp: now, newestAccepted: nil))
        XCTAssertNotNil(LocationStatusEvaluator.discardReason(horizontalAccuracy: 5, latitude: 40, longitude: -3, timestamp: now.addingTimeInterval(-5), newestAccepted: now))
    }

    func testStatusTextsNeverSayGPSLost() {
        let all: [LocationStatus] = [.requestingPermission, .acquiring, .available, .reducedAccuracy, .lowAccuracy(meters: 300),
                                     .lastKnown(ageSeconds: 50), .temporaryError, .denied, .restricted, .servicesDisabled]
        for status in all {
            XCTAssertFalse(status.title.lowercased().contains("perdid"), status.logName)
            XCTAssertFalse((status.explanation ?? "").lowercased().contains("perdid"), status.logName)
        }
        XCTAssertNil(LocationStatus.available.explanation)
    }
}

// MARK: - Servicio con gestor falso

@MainActor
final class LocationServiceTests: XCTestCase {
    private var manager: FakeLocationManager!
    private var clock: TestClock!
    private var diagnostics: DiagnosticsLog!
    private var service: LocationService!

    override func setUp() {
        super.setUp()
        manager = FakeLocationManager()
        clock = TestClock()
        diagnostics = DiagnosticsLog()
        service = LocationService(manager: manager, diagnostics: diagnostics, clock: { [clock] in clock!.now },
                                  servicesEnabledProvider: { true }, startTimer: false)
    }

    private func authorize(accuracy: CLAccuracyAuthorization = .fullAccuracy) {
        service.resolveAuth(status: .authorizedWhenInUse, accuracy: accuracy, servicesEnabled: true)
    }

    private func fix(accuracy: Double = 10, age: TimeInterval = 0, speed: Double = 0,
                     lat: Double = 40.41680, lon: Double = -3.70380) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed,
                   timestamp: clock.now.addingTimeInterval(-age))
    }

    private func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        service.tick()
    }

    // MARK: Apertura

    func testOpeningDoesNotShowLostWhileTheFirstFixIsPending() {
        authorize()
        service.start(mode: .idle)
        for _ in 0..<10 { advance(2) }                       // 20 s sin ninguna lectura, sin error
        XCTAssertEqual(service.status, .acquiring)
        XCTAssertFalse(service.isSignalLost)
    }

    func testTemporaryErrorBeforeTheFirstFixIsTemporaryNotLost() {
        authorize()
        service.start(mode: .idle)
        advance(14)
        service.didFail(CLError(.locationUnknown))
        advance(1)
        XCTAssertEqual(service.status, .temporaryError)
        XCTAssertFalse(service.isSignalLost)
        service.ingest(fix())                                // llega una posición válida: se limpia el error
        XCTAssertEqual(service.status, .available)
    }

    func testUpdatesStartOnTheirOwnWhenPermissionArrivesLater() {
        service.start(mode: .idle)                           // aún sin permiso
        XCTAssertEqual(manager.startCount, 0)
        XCTAssertEqual(service.status, .requestingPermission)
        authorize()
        XCTAssertEqual(manager.startCount, 1)                // arranca sin depender de la interfaz
        XCTAssertGreaterThanOrEqual(manager.oneShotCount, 1)
    }

    func testStartIsIdempotentAndStopStopsUpdates() {
        authorize()
        service.start(mode: .idle)
        service.start(mode: .idle)
        service.setMode(.navigating)
        service.start(mode: .navigating)
        XCTAssertEqual(manager.startCount, 1)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        service.stop()
        XCTAssertEqual(manager.stopCount, 1)
        service.start(mode: .idle)
        XCTAssertEqual(manager.startCount, 2)
    }

    // MARK: Usuario quieto y en movimiento

    func testStationaryUserIsNotLostAndGetsAFreshReadingRequested() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix(accuracy: 12))
        let before = manager.oneShotCount
        advance(40)                                          // quieto: iOS no entrega lecturas nuevas
        XCTAssertEqual(service.status, .available)
        XCTAssertFalse(service.isSignalLost)
        XCTAssertGreaterThan(manager.oneShotCount, before)   // se pide una lectura puntual para confirmar

        advance(60)                                          // 100 s sin ninguna confirmación
        XCTAssertTrue(service.isSignalLost)
        if case .lastKnown = service.status {} else { XCTFail("Debía ser «última ubicación conocida»: \(service.status)") }

        service.ingest(fix(accuracy: 12))                    // llega la lectura puntual
        XCTAssertEqual(service.status, .available)
        XCTAssertFalse(service.isSignalLost)
    }

    func testMovingNavigationFlagsStaleReadingsAndRecovers() {
        authorize()
        service.start(mode: .navigating)
        service.ingest(fix(accuracy: 5, speed: 12))
        advance(6)
        XCTAssertEqual(service.status, .available)
        advance(6)                                           // 12 s sin lecturas yendo a 43 km/h
        XCTAssertTrue(service.isSignalLost)
        service.ingest(fix(accuracy: 5, speed: 12))
        XCTAssertFalse(service.isSignalLost)
        XCTAssertEqual(service.status, .available)
    }

    // MARK: Precisión

    func testApproximatePermissionIsAcceptedNotTreatedAsDeniedOrDiscarded() {
        authorize(accuracy: .reducedAccuracy)
        service.start(mode: .idle)
        service.ingest(fix(accuracy: 4000))                  // ubicación aproximada: miles de metros
        XCTAssertNotNil(service.currentLocation)
        XCTAssertEqual(service.accuracyMode, .reduced)
        XCTAssertEqual(service.status, .reducedAccuracy)
        XCTAssertTrue(service.authState.isAuthorized)
    }

    func testLowAccuracyReadingIsKeptAndLabelled() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix(accuracy: 700))
        XCTAssertNotNil(service.currentLocation)
        XCTAssertEqual(service.status, .lowAccuracy(meters: 700))
        XCTAssertEqual(service.quality, .poor)
    }

    func testInvalidReadingsAreDiscardedWithALoggedReason() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix(accuracy: -1))
        XCTAssertNil(service.currentLocation)
        XCTAssertTrue(diagnostics.events.contains { $0.service == "location" && $0.errorKind == "discarded" })
        XCTAssertEqual(service.status, .acquiring)
    }

    func testOldCachedFixAtStartIsNotLostAndIsReplacedByAFreshOne() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix(age: 7200))                       // lectura en caché de hace 2 horas
        XCTAssertNotNil(service.currentLocation)
        XCTAssertEqual(service.status, .acquiring)           // se está actualizando, no está perdida
        advance(10)
        if case .lastKnown = service.status {} else { XCTFail("Tras el margen debía ser «sin confirmar»: \(service.status)") }
        service.ingest(fix())
        XCTAssertEqual(service.status, .available)
    }

    func testTemporaryErrorDoesNotDropTheLastKnownPosition() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix())
        service.didFail(CLError(.locationUnknown))
        XCTAssertNotNil(service.currentLocation)
        XCTAssertEqual(service.status, .available)
        XCTAssertFalse(service.isSignalLost)
    }

    // MARK: Permisos

    func testPermissionStatesMapToTheirOwnStatus() {
        XCTAssertEqual(service.status, .requestingPermission)
        service.resolveAuth(status: .denied, accuracy: .fullAccuracy, servicesEnabled: true)
        XCTAssertEqual(service.status, .denied)
        service.resolveAuth(status: .restricted, accuracy: .fullAccuracy, servicesEnabled: true)
        XCTAssertEqual(service.status, .restricted)
        service.resolveAuth(status: .authorizedWhenInUse, accuracy: .fullAccuracy, servicesEnabled: false)
        XCTAssertEqual(service.status, .servicesDisabled)
        authorize()
        XCTAssertEqual(service.status, .acquiring)
    }

    func testRevokingPermissionStopsUpdates() {
        authorize()
        service.start(mode: .idle)
        service.resolveAuth(status: .denied, accuracy: .fullAccuracy, servicesEnabled: true)
        XCTAssertEqual(manager.stopCount, 1)
        XCTAssertEqual(service.status, .denied)
    }

    func testRefreshNowAsksForPermissionOrRequestsAReading() {
        service.refreshNow()
        XCTAssertEqual(manager.permissionRequests, 1)
        authorize()
        let before = manager.oneShotCount
        service.refreshNow()
        XCTAssertGreaterThan(manager.oneShotCount, before)
        XCTAssertEqual(manager.startCount, 1)                // reanuda las actualizaciones si estaban paradas
    }

    func testFullAccuracyRequestUsesTheDeclaredPurposeKey() {
        service.requestTemporaryFullAccuracy()
        XCTAssertEqual(manager.fullAccuracyRequests, ["Navigation"])
    }

    // MARK: Diagnóstico

    func testDiagnosticsLogTransitionsAndNeverPreciseCoordinates() {
        authorize()
        service.start(mode: .idle)
        service.ingest(fix(accuracy: 8, lat: 40.41680, lon: -3.70380))
        advance(120)
        let text = diagnostics.report(header: [service.diagnosticSummary])
        XCTAssertTrue(diagnostics.events.contains { $0.operation == "status" })
        XCTAssertTrue(diagnostics.events.contains { $0.operation == "auth" })
        XCTAssertTrue(diagnostics.events.contains { $0.operation == "start" })
        XCTAssertTrue(diagnostics.events.contains { $0.operation == "reading" })
        for fragment in ["40.41", "40,41", "-3.70", "-3,70"] {
            XCTAssertFalse(text.contains(fragment), "El informe no debe contener coordenadas (\(fragment))")
        }
        XCTAssertTrue(service.diagnosticSummary.contains("estado="))
    }
}
