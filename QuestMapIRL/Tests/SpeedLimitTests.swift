import XCTest
import CoreLocation
import SwiftData
@testable import QuestMapIRL

final class SpeedLimitTests: XCTestCase {
    // MARK: Interpretación de la respuesta

    func testParserKeepsOnlyPlausibleNumericLimitsAndNeverTurnsMissingIntoUnlimited() throws {
        let json = """
        {"units":"kilometers","edges":[
          {"speed_limit":50,"length":0.5},
          {"length":0.3},
          {"speed_limit":255,"length":0.2},
          {"speed_limit":"walk","length":0.1},
          {"speed_limit":0,"length":0.1},
          {"speed_limit":120.0,"length":1.0}]}
        """
        let edges = try SpeedLimitParser.edges(from: Data(json.utf8))
        XCTAssertEqual(edges.map(\.limitKmh), [50, nil, nil, nil, nil, 120])
        XCTAssertEqual(edges.first?.lengthMeters ?? 0, 500, accuracy: 0.001)
    }

    func testParserRejectsUnexpectedUnitsAndGarbage() {
        XCTAssertThrowsError(try SpeedLimitParser.edges(from: Data(#"{"units":"miles","edges":[]}"#.utf8)))
        XCTAssertThrowsError(try SpeedLimitParser.edges(from: Data("no es json".utf8)))
        XCTAssertThrowsError(try SpeedLimitParser.edges(from: Data(#"{"foo":1}"#.utf8)))
    }

    // MARK: Perfil a lo largo de la ruta

    func testProfileFollowsEdgesAndMergesEqualNeighbours() {
        let edges = [SpeedLimitEdge(lengthMeters: 500, limitKmh: 50), SpeedLimitEdge(lengthMeters: 500, limitKmh: 50),
                     SpeedLimitEdge(lengthMeters: 1000, limitKmh: 30)]
        let profile = SpeedLimitProfileBuilder.build(chunks: [(0, 2000, edges)], routeMeters: 2000)
        XCTAssertEqual(profile.segments.count, 2)
        XCTAssertEqual(profile.limit(atMeters: 10), 50)
        XCTAssertEqual(profile.limit(atMeters: 999), 50)
        XCTAssertEqual(profile.limit(atMeters: 1500), 30)
        XCTAssertNil(profile.limit(atMeters: 2500), "fuera de la ruta no hay límite")
        XCTAssertNil(profile.limit(atMeters: -5))
    }

    func testMissingDataStaysMissingAndIsNotFilled() {
        let edges = [SpeedLimitEdge(lengthMeters: 1000, limitKmh: 50), SpeedLimitEdge(lengthMeters: 1000, limitKmh: nil)]
        let profile = SpeedLimitProfileBuilder.build(chunks: [(0, 2000, edges)], routeMeters: 2000)
        XCTAssertEqual(profile.limit(atMeters: 500), 50)
        XCTAssertNil(profile.limit(atMeters: 1500), "sin dato no es «sin límite» ni se arrastra el anterior")
        XCTAssertEqual(profile.coverage, 0.5, accuracy: 0.001)
    }

    func testChunkThatDoesNotMatchTheRouteLengthIsLeftWithoutData() {
        // El servicio ajustó el trazado a otra vía mucho más corta: no se fía.
        let edges = [SpeedLimitEdge(lengthMeters: 900, limitKmh: 90)]
        let profile = SpeedLimitProfileBuilder.build(chunks: [(0, 2000, edges)], routeMeters: 2000)
        XCTAssertNil(profile.limit(atMeters: 500))
    }

    func testFailedChunkOnlyAffectsItsOwnPart() {
        let ok = [SpeedLimitEdge(lengthMeters: 1000, limitKmh: 100)]
        let profile = SpeedLimitProfileBuilder.build(chunks: [(0, 1000, ok), (1000, 1000, nil)], routeMeters: 2000)
        XCTAssertEqual(profile.limit(atMeters: 500), 100)
        XCTAssertNil(profile.limit(atMeters: 1500))
    }

    // MARK: Qué se muestra

    private let profile = SpeedLimitProfile(segments: [
        SpeedLimitSegment(startMeters: 0, endMeters: 1000, limitKmh: 90),
        SpeedLimitSegment(startMeters: 1000, endMeters: 2000, limitKmh: 50),
        SpeedLimitSegment(startMeters: 2000, endMeters: 3000, limitKmh: nil),
    ], routeMeters: 3000)

    private func step(_ tracker: inout SpeedLimitTracker, _ meters: Double, off: Bool = false, accuracy: Double = 8,
                      age: TimeInterval = 1, enabled: Bool = true, profile override: SpeedLimitProfile? = nil) -> SpeedLimitDisplay {
        tracker.update(enabled: enabled, profile: override ?? profile, progressMeters: meters, isOffRoute: off, accuracy: accuracy, age: age)
    }

    func testFirstReliableReadingShowsImmediatelyButChangesNeedConfirmation() {
        var tracker = SpeedLimitTracker()
        XCTAssertEqual(step(&tracker, 500), .limit(kmh: 90))
        XCTAssertEqual(step(&tracker, 1005), .limit(kmh: 90), "una sola lectura en el nuevo tramo no cambia la señal (anti-parpadeo)")
        XCTAssertEqual(step(&tracker, 1040), .limit(kmh: 50))
    }

    func testNoDataShowsUnavailableNeverTheLastLimit() {
        var tracker = SpeedLimitTracker()
        _ = step(&tracker, 1500)
        _ = step(&tracker, 2100)
        XCTAssertEqual(step(&tracker, 2150), .unavailable)
    }

    func testSignIsHiddenWhenPositionIsNotTrustworthy() {
        var tracker = SpeedLimitTracker()
        XCTAssertEqual(step(&tracker, 500), .limit(kmh: 90))
        XCTAssertEqual(step(&tracker, 500, off: true), .hidden, "fuera de ruta se abandona el tramo")
        XCTAssertEqual(step(&tracker, 500, accuracy: 150), .hidden, "precisión mala")
        XCTAssertEqual(step(&tracker, 500, accuracy: -1), .hidden, "lectura inválida")
        XCTAssertEqual(step(&tracker, 500, age: 30), .hidden, "ubicación antigua (pérdida de señal)")
    }

    func testDisabledOrWithoutProfileShowsNothing() {
        var tracker = SpeedLimitTracker()
        XCTAssertEqual(step(&tracker, 500, enabled: false), .hidden)
        var other = SpeedLimitTracker()
        XCTAssertEqual(other.update(enabled: true, profile: nil, progressMeters: 500, isOffRoute: false, accuracy: 5, age: 1), .hidden)
    }

    func testReturningToTheRouteStartsFreshInsteadOfKeepingTheOldLimit() {
        var tracker = SpeedLimitTracker()
        _ = step(&tracker, 500)
        _ = step(&tracker, 500, off: true)
        XCTAssertEqual(step(&tracker, 1500), .limit(kmh: 50), "tras reincorporarse se muestra el del tramo actual")
    }

    // MARK: Unidades y accesibilidad

    func testMphSignsAreRoundedToFive() {
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 50, metric: true), 50)
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 50, metric: false), 30)   // 31,07 → 30
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 120, metric: false), 75)  // 74,6 → 75
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 30, metric: false), 20)   // 18,6 → 20
    }

    func testAccessibilityLabelsAreExplicit() {
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.limit(kmh: 50), metric: true), "Límite de velocidad: 50 kilómetros por hora")
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.limit(kmh: 50), metric: false), "Límite de velocidad: 30 millas por hora")
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.unavailable, metric: true), "Límite de velocidad no disponible")
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.hidden, metric: true), "")
    }

    // MARK: Servicio (sin red real)

    func testRequestUsesPostWithoutAnyKeyAndAsksOnlyForLimitAndLength() throws {
        let request = ValhallaSpeedLimitService.request(
            endpoint: URL(string: "https://example.test/trace_attributes")!,
            shape: [CLLocationCoordinate2D(latitude: 1, longitude: 2), CLLocationCoordinate2D(latitude: 1.1, longitude: 2.1)])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["units"] as? String, "kilometers")
        let attributes = (body["filters"] as? [String: Any])?["attributes"] as? [String]
        XCTAssertEqual(Set(attributes ?? []), ["edge.speed_limit", "edge.length"])
    }

    func testRouteIsSplitInContiguousChunksAndThinned() {
        let points = (0...60).map { CLLocationCoordinate2D(latitude: 40 + Double($0) * 0.001, longitude: -3) } // ~6,7 km
        let chunks = ValhallaSpeedLimitService.chunks(points, chunkMeters: 2000, maxChunks: 20)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(a.startMeters + a.lengthMeters, b.startMeters, accuracy: 0.5)
            XCTAssertEqual(a.points.last?.latitude, b.points.first?.latitude)
        }
        let dense = (0..<500).map { CLLocationCoordinate2D(latitude: 40 + Double($0) * 0.000002, longitude: -3) }
        XCTAssertLessThan(ValhallaSpeedLimitService.thinned(dense, minSpacing: 20).count, 100)
        XCTAssertEqual(ValhallaSpeedLimitService.thinned(dense, minSpacing: 20).last?.latitude, dense.last?.latitude)
    }

    func testServiceBuildsAProfileFromTheServerAnswerAndCachesIt() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let route = [CLLocationCoordinate2D(latitude: 40.40, longitude: -3.7), CLLocationCoordinate2D(latitude: 40.41, longitude: -3.7),
                     CLLocationCoordinate2D(latitude: 40.42, longitude: -3.7)]
        StubURLProtocol.responder = { _ in
            ok(Data(#"{"units":"kilometers","edges":[{"speed_limit":50,"length":1.1},{"speed_limit":30,"length":1.1}]}"#.utf8))
        }
        let service = ValhallaSpeedLimitService(
            client: ServiceClient(service: "valhalla", session: StubURLProtocol.session(), retry: instantRetry(maxRetries: 0), diagnostics: DiagnosticsLog()))
        let profile = try await service.profile(for: route)
        XCTAssertEqual(profile.limit(atMeters: 300), 50)
        XCTAssertEqual(profile.limit(atMeters: 1900), 30)
        let calls = StubURLProtocol.requests.count
        _ = try await service.profile(for: route)
        XCTAssertEqual(StubURLProtocol.requests.count, calls, "la misma ruta no se vuelve a consultar")
    }

    func testServiceFailureThrowsInsteadOfInventingLimits() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.responder = { _ in http(503) }
        let service = ValhallaSpeedLimitService(
            client: ServiceClient(service: "valhalla", session: StubURLProtocol.session(), retry: instantRetry(maxRetries: 0), diagnostics: DiagnosticsLog()))
        do {
            _ = try await service.profile(for: [CLLocationCoordinate2D(latitude: 1, longitude: 1), CLLocationCoordinate2D(latitude: 1.01, longitude: 1)])
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SpeedLimitError, .noData)
        }
    }

    // MARK: Ajuste persistente

    @MainActor
    func testSettingDefaultsToOnAndSurvivesReopeningTheStore() throws {
        XCTAssertTrue(UserSettings().showSpeedLimit)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("s.store")
        var keep: [ModelContainer] = []
        func open() throws -> ModelContainer {
            let c = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
            keep.append(c); return c
        }
        do {
            let context = ModelContext(try open())
            let settings = UserSettings()
            settings.showSpeedLimit = false
            context.insert(settings)
            try PersistenceCommit.save(context)
        }
        let stored = try ModelContext(try open()).fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(stored.first?.showSpeedLimit, false)
    }
}
