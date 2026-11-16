import XCTest
import CoreLocation
@testable import QuestMapIRL

/// Servicio de lugares cercanos cuyas respuestas se liberan a mano, para probar el orden de llegada.
private final class ControlledNearby: NearbySearchProviding, @unchecked Sendable {
    struct Pending { let category: PlaceCategory; let radius: Int; let continuation: CheckedContinuation<[Place], Error> }
    private let lock = NSLock()
    private(set) var pending: [Pending] = []
    private(set) var calls: [(PlaceCategory, Int)] = []

    func nearby(_ category: PlaceCategory, around: CLLocationCoordinate2D, radiusMeters: Int) async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            calls.append((category, radiusMeters))
            pending.append(Pending(category: category, radius: radiusMeters, continuation: continuation))
            lock.unlock()
        }
    }

    func waitForPending(_ count: Int) async {
        for _ in 0..<400 {
            lock.lock(); let n = pending.count; lock.unlock()
            if n >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func resume(_ index: Int, with result: Result<[Place], Error>) {
        lock.lock(); let item = pending[index]; lock.unlock()
        item.continuation.resume(with: result)
    }
}

private final class ControlledSearch: PlaceSearchProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pending: [(String, CheckedContinuation<[Place], Error>)] = []

    func search(_ query: String, near: CLLocationCoordinate2D?, category: PlaceCategory?) async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); pending.append((query, continuation)); lock.unlock()
        }
    }

    func waitForPending(_ count: Int) async {
        for _ in 0..<400 {
            lock.lock(); let n = pending.count; lock.unlock()
            if n >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func resume(_ index: Int, with result: Result<[Place], Error>) {
        lock.lock(); let item = pending[index]; lock.unlock()
        item.1.resume(with: result)
    }
}

private func place(_ name: String) -> Place {
    Place(id: name, name: name, subtitle: "", latitude: 40.4168, longitude: -3.7038)
}

@MainActor
final class SearchPanelModelTests: XCTestCase {
    private let here = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)

    private func makeModel(_ nearby: ControlledNearby = ControlledNearby(), _ search: ControlledSearch = ControlledSearch())
        -> (SearchPanelModel, ControlledNearby, ControlledSearch) {
        let model = SearchPanelModel(search: search, nearby: nearby)
        model.typingDelay = .zero
        return (model, nearby, search)
    }

    private func settle() async { for _ in 0..<10 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(30)) }

    // MARK: Categorías

    func testSuccessfulCategoryShowsResultsAndMarkers() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        XCTAssertEqual(model.categoryPhase, .loading)
        await nearby.waitForPending(1)
        nearby.resume(0, with: .success([place("A"), place("B"), place("C")]))
        await settle()
        XCTAssertEqual(model.categoryPhase, .results)
        XCTAssertEqual(model.categoryResults.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(model.markers.count, 3)
        XCTAssertEqual(nearby.calls.count, 1)                       // suficientes resultados: no se amplía el radio
    }

    func testEmptyResultsWidenTheRadiusOnceAndThenShowEmptyNotError() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.cafe, near: here)
        await nearby.waitForPending(1)
        nearby.resume(0, with: .success([]))
        await nearby.waitForPending(2)
        XCTAssertEqual(nearby.calls.map(\.1), SearchPanelModel.radii)
        nearby.resume(1, with: .success([]))
        await settle()
        XCTAssertEqual(model.categoryPhase, .empty)
    }

    func testSwitchingCategoryIsNotAnErrorAndStaleAnswerIsIgnored() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        await nearby.waitForPending(1)
        model.openCategory(.pharmacy, near: here)               // el usuario cambia de categoría
        await nearby.waitForPending(2)
        XCTAssertEqual(model.categoryPhase, .loading)

        // La respuesta de la categoría antigua llega DESPUÉS de empezar la nueva, y también como cancelación.
        nearby.resume(0, with: .failure(CancellationError()))
        await settle()
        XCTAssertEqual(model.categoryPhase, .loading)           // sin falso aviso de conexión

        nearby.resume(1, with: .success([place("Farmacia 1"), place("Farmacia 2"), place("Farmacia 3")]))
        await settle()
        XCTAssertEqual(model.categoryPhase, .results)
        XCTAssertEqual(model.categoryResults.first?.name, "Farmacia 1")
    }

    func testOutOfOrderResponsesNeverOverwriteTheNewestSearch() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        await nearby.waitForPending(1)
        model.openCategory(.hotel, near: here)
        await nearby.waitForPending(2)
        // Responde primero la nueva y después, tarde, la antigua con datos distintos.
        nearby.resume(1, with: .success([place("Hotel 1"), place("Hotel 2"), place("Hotel 3")]))
        await settle()
        nearby.resume(0, with: .success([place("Gasolinera vieja"), place("Otra"), place("Otra 2")]))
        await settle()
        XCTAssertEqual(model.activeCategory, .hotel)
        XCTAssertEqual(model.categoryResults.map(\.name), ["Hotel 1", "Hotel 2", "Hotel 3"])
        XCTAssertEqual(model.markers.map(\.name), ["Hotel 1", "Hotel 2", "Hotel 3"])
    }

    func testRetryAfterFailureLaunchesANewSearchAndLeavesTheErrorState() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        await nearby.waitForPending(1)
        nearby.resume(0, with: .failure(SearchError.serviceUnavailable))
        await settle()
        XCTAssertEqual(model.categoryPhase, .failed(.serviceUnavailable))

        model.reloadCategory(near: here)                        // botón "Reintentar"
        XCTAssertEqual(model.categoryPhase, .loading)
        await nearby.waitForPending(2)
        nearby.resume(1, with: .success([place("Repsol"), place("Cepsa"), place("BP")]))
        await settle()
        XCTAssertEqual(model.categoryPhase, .results)
        XCTAssertEqual(nearby.calls.count, 2)
    }

    func testEachFailureKeepsItsOwnCause() async {
        for error in [SearchError.offline, .timedOut, .serviceUnavailable, .rateLimited, .configuration, .decoding] {
            let (model, nearby, _) = makeModel()
            model.openCategory(.fuel, near: here)
            await nearby.waitForPending(1)
            nearby.resume(0, with: .failure(error))
            await settle()
            XCTAssertEqual(model.categoryPhase, .failed(error), error.kind)
        }
        // Un error que no es de red tampoco se disfraza de "sin conexión".
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        await nearby.waitForPending(1)
        nearby.resume(0, with: .failure(NSError(domain: "x", code: 1)))
        await settle()
        XCTAssertEqual(model.categoryPhase, .failed(.unexpected))
    }

    func testNoLocationAsksForAnAreaInsteadOfFailing() {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: nil)
        XCTAssertEqual(model.categoryPhase, .needsLocation)
        XCTAssertTrue(nearby.calls.isEmpty)
        model.openCategory(.fuel, near: CLLocationCoordinate2D(latitude: 500, longitude: 500))   // coordenada inválida
        XCTAssertEqual(model.categoryPhase, .needsLocation)
    }

    func testChosenAreaReplacesMissingLocation() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: nil)
        model.setArea(place("Madrid"), near: nil)
        await nearby.waitForPending(1)
        XCTAssertEqual(model.categoryPhase, .loading)
    }

    func testViewUpdatesDoNotRelaunchTheSearch() async {
        let (model, nearby, _) = makeModel()
        model.openCategory(.fuel, near: here)
        await nearby.waitForPending(1)
        // Releer el estado (lo que hace SwiftUI al redibujar) no lanza nada.
        _ = model.categoryPhase; _ = model.categoryResults; _ = model.markers
        await settle()
        XCTAssertEqual(nearby.calls.count, 1)
    }

    // MARK: Buscador de texto

    func testTextSearchIgnoresAnOlderResponseArrivingLast() async {
        let (model, _, search) = makeModel()
        model.query = "mad"
        model.queryChanged(near: here)
        await search.waitForPending(1)
        model.query = "madrid"
        model.queryChanged(near: here)
        await search.waitForPending(2)
        search.resume(1, with: .success([place("Madrid")]))
        await settle()
        search.resume(0, with: .success([place("Madera")]))
        await settle()
        XCTAssertEqual(model.results.map(\.name), ["Madrid"])
        XCTAssertEqual(model.phase, .results)
    }

    func testTextSearchEmptyIsNotAnErrorAndRetryRecovers() async {
        let (model, _, search) = makeModel()
        model.query = "zzzz"
        model.queryChanged(near: here)
        await search.waitForPending(1)
        search.resume(0, with: .success([]))
        await settle()
        XCTAssertEqual(model.phase, .empty)

        model.query = "madrid"
        model.queryChanged(near: here)
        await search.waitForPending(2)
        search.resume(1, with: .failure(SearchError.timedOut))
        await settle()
        XCTAssertEqual(model.phase, .failed(.timedOut))

        model.queryChanged(near: here)                          // "Reintentar"
        XCTAssertEqual(model.phase, .loading)
        await search.waitForPending(3)
        search.resume(2, with: .success([place("Madrid")]))
        await settle()
        XCTAssertEqual(model.phase, .results)
    }

    func testClearingTheQueryCancelsAndResets() async {
        let (model, _, search) = makeModel()
        model.query = "madrid"
        model.queryChanged(near: here)
        await search.waitForPending(1)
        model.clearQuery()
        search.resume(0, with: .success([place("Madrid")]))
        await settle()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.results.isEmpty)
    }
}

@MainActor
final class NetworkMonitorTests: XCTestCase {
    private func makeMonitor() -> NetworkMonitor {
        let monitor = NetworkMonitor(startMonitoring: false, diagnostics: DiagnosticsLog())
        monitor.graceSeconds = 0.08
        return monitor
    }

    private let offline = NetworkMonitor.PathState(isAvailable: false, reason: .other, description: "estado=unsatisfied")
    private let online = NetworkMonitor.PathState(isAvailable: true, reason: .none, description: "estado=satisfied")

    func testBriefDropDoesNotShowTheNotice() async throws {
        let monitor = makeMonitor()
        monitor.apply(offline)
        XCTAssertFalse(monitor.isOnline)
        XCTAssertFalse(monitor.showsOfflineNotice)                // todavía dentro del margen de gracia
        monitor.apply(online)                                      // la red vuelve (p. ej. wifi → 5G)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(monitor.showsOfflineNotice)
        XCTAssertTrue(monitor.isOnline)
    }

    func testPersistentLossShowsTheNoticeAndRecoveryHidesIt() async throws {
        let monitor = makeMonitor()
        monitor.apply(offline)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(monitor.showsOfflineNotice)
        monitor.apply(online)
        XCTAssertFalse(monitor.showsOfflineNotice)
    }

    func testCellularDeniedExplainsTheRealCause() {
        let monitor = makeMonitor()
        monitor.apply(NetworkMonitor.PathState(isAvailable: false, reason: .cellularDenied, description: "motivo=cellularDenied"))
        XCTAssertTrue(monitor.noticeText.contains("datos móviles"))
        monitor.apply(online)
        XCTAssertTrue(monitor.noticeText.contains("Sin conexión"))   // texto genérico sin causa específica
    }

    func testPathChangesAreLoggedWithoutPersonalData() {
        let log = DiagnosticsLog()
        let monitor = NetworkMonitor(startMonitoring: false, diagnostics: log)
        monitor.apply(offline)
        XCTAssertEqual(log.events.last?.service, "network")
        XCTAssertEqual(log.events.last?.errorKind, "offline")
        XCTAssertEqual(monitor.pathDescription, "estado=unsatisfied")
    }
}
