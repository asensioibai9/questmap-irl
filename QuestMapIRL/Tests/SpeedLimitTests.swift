import XCTest
import CoreLocation
import SwiftData
@testable import QuestMapIRL

// MARK: - Ayudas

private func point(_ edge: Int?, _ fraction: Double?, offset: Double? = 2, kind: SpeedLimitMatchedPoint.Kind = .matched) -> SpeedLimitMatchedPoint {
    SpeedLimitMatchedPoint(kind: kind, edgeIndex: edge, distanceAlongEdge: fraction, distanceFromTrace: offset)
}

private func edge(_ meters: Double, _ limit: Int?) -> SpeedLimitEdge { SpeedLimitEdge(lengthMeters: meters, limitKmh: limit) }

final class SpeedLimitTests: XCTestCase {
    // MARK: Interpretación de la respuesta

    func testParserKeepsOnlyPlausibleNumericLimitsAndNeverTurnsMissingIntoUnlimited() throws {
        let json = """
        {"units":"kilometers","admins":[{"country_code":"ES"}],"edges":[
          {"speed_limit":50,"length":0.5},
          {"length":0.3},
          {"speed_limit":255,"length":0.2},
          {"speed_limit":"walk","length":0.1},
          {"speed_limit":0,"length":0.1},
          {"speed_limit":50.5,"length":0.1},
          {"speed_limit":120.0,"length":1.0}],
         "matched_points":[{"type":"matched","edge_index":0,"distance_along_edge":0.25,"distance_from_trace_point":3.5},
                           {"type":"unmatched"},
                           {"type":"interpolated","edge_index":6,"distance_along_edge":1}]}
        """
        let match = try SpeedLimitParser.match(from: Data(json.utf8))
        XCTAssertEqual(match.edges.map(\.limitKmh), [50, nil, nil, nil, nil, nil, 120], "sin dato, 255, texto, 0 y decimales raros: sin cifra")
        XCTAssertEqual(match.edges.first?.lengthMeters ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(match.points, [point(0, 0.25, offset: 3.5), point(nil, nil, offset: nil, kind: .unmatched),
                                      point(6, 1, offset: nil, kind: .interpolated)])
        XCTAssertEqual(match.countryCode, "ES")
    }

    func testParserRejectsUnexpectedUnitsGarbageAndEdgesWithoutLength() {
        XCTAssertThrowsError(try SpeedLimitParser.match(from: Data(#"{"units":"miles","edges":[]}"#.utf8)))
        XCTAssertThrowsError(try SpeedLimitParser.match(from: Data("no es json".utf8)))
        XCTAssertThrowsError(try SpeedLimitParser.match(from: Data(#"{"foo":1}"#.utf8)))
        XCTAssertThrowsError(try SpeedLimitParser.match(from: Data(#"{"edges":[{"speed_limit":50}]}"#.utf8)))
    }

    func testCountryIsOnlyKnownWhenThereIsExactlyOne() throws {
        let two = try SpeedLimitParser.match(from: Data(#"{"admins":[{"country_code":"ES"},{"country_code":"FR"}],"edges":[]}"#.utf8))
        XCTAssertNil(two.countryCode)
        let none = try SpeedLimitParser.match(from: Data(#"{"edges":[]}"#.utf8))
        XCTAssertNil(none.countryCode)
    }

    // MARK: Perfil de la ruta (asociación punto a punto)

    private func profile(_ edges: [SpeedLimitEdge], _ points: [SpeedLimitMatchedPoint], meters: [Double],
                         country: String? = "ES") -> SpeedLimitProfile {
        SpeedLimitProfileBuilder.build(pieces: [.init(pointMeters: meters,
                                                      match: SpeedLimitMatch(edges: edges, points: points, countryCode: country))],
                                       routeMeters: meters.last ?? 0)
    }

    func testExplicitLimitAndChangeOnTheSameRoadArePlacedWhereTheEdgeChanges() {
        // Dos aristas de 100 m (50 y luego 30). Puntos a 0, 50, 150 y 200 m de la ruta.
        let p = profile([edge(100, 50), edge(100, 30)],
                        [point(0, 0), point(0, 0.5), point(1, 0.5), point(1, 1)], meters: [0, 50, 150, 200])
        XCTAssertEqual(p.limit(atMeters: 25), 50)
        XCTAssertEqual(p.limit(atMeters: 99), 50)
        XCTAssertEqual(p.limit(atMeters: 101), 30, "el cambio cae donde cambia la arista, no estirado")
        XCTAssertEqual(p.limit(atMeters: 190), 30)
        XCTAssertNil(p.limit(atMeters: 250), "fuera de la ruta no hay límite")
        XCTAssertEqual(p.countryCode, "ES")
        XCTAssertTrue(p.isComplete)
    }

    func testSegmentWithoutDataStaysWithoutDataAndIsNotFilledWithTheNeighbour() {
        let p = profile([edge(100, 50), edge(100, nil)],
                        [point(0, 0), point(0, 1), point(1, 1)], meters: [0, 100, 200])
        XCTAssertEqual(p.limit(atMeters: 50), 50)
        XCTAssertNil(p.limit(atMeters: 150), "sin dato no es «sin límite» ni se arrastra el anterior")
        XCTAssertEqual(p.coverage, 0.5, accuracy: 0.001)
    }

    func testPointSnappedFarFromTheRouteIsTreatedAsAParallelRoadAndGivesNoData() {
        // El proveedor puso el tercer punto a 28 m: probablemente la vía de servicio paralela (caso real observado).
        let p = profile([edge(100, 50), edge(100, 50), edge(100, 30)],
                        [point(0, 0), point(0, 1), point(2, 0.5, offset: 28), point(2, 1)], meters: [0, 100, 250, 300])
        XCTAssertEqual(p.limit(atMeters: 50), 50)
        XCTAssertNil(p.limit(atMeters: 200), "no se muestra el 30 de la vía paralela")
        XCTAssertNil(p.limit(atMeters: 280))
    }

    func testUnmatchedPointsAndDetoursGiveNoData() {
        let unmatched = profile([edge(100, 50)], [point(0, 0), point(nil, nil, kind: .unmatched)], meters: [0, 100])
        XCTAssertNil(unmatched.limit(atMeters: 50))
        // El proveedor recorre 500 m para unir dos puntos que en la ruta distan 100 m (otra calle / salida).
        let detour = profile([edge(100, 50), edge(300, 80), edge(100, 50)], [point(0, 0), point(2, 1)], meters: [0, 100])
        XCTAssertNil(detour.limit(atMeters: 50))
        // Retroceso (índices al revés): tampoco.
        let backwards = profile([edge(100, 50), edge(100, 50)], [point(1, 0.5), point(0, 0.5)], meters: [0, 100])
        XCTAssertNil(backwards.limit(atMeters: 50))
    }

    func testExitRampWithItsOwnLimitIsFollowedWhenTheRouteTakesIt() {
        // Autopista 120, salida 60: la ruta toma la salida; el proveedor asocia los puntos a la salida.
        let p = profile([edge(400, 120), edge(300, 60)],
                        [point(0, 0), point(0, 0.5), point(0, 1), point(1, 0.5), point(1, 1)], meters: [0, 200, 400, 550, 700])
        XCTAssertEqual(p.limit(atMeters: 300), 120)
        XCTAssertEqual(p.limit(atMeters: 500), 60)
    }

    func testFailedPieceOnlyAffectsItsOwnPartAndMarksTheProfileIncomplete() {
        let ok = SpeedLimitMatch(edges: [edge(100, 100)], points: [point(0, 0), point(0, 1)], countryCode: "ES")
        let p = SpeedLimitProfileBuilder.build(pieces: [.init(pointMeters: [0, 100], match: ok),
                                                        .init(pointMeters: [100, 200], match: nil)], routeMeters: 200)
        XCTAssertEqual(p.limit(atMeters: 50), 100)
        XCTAssertNil(p.limit(atMeters: 150))
        XCTAssertFalse(p.isComplete)
    }

    func testCrossingABorderLeavesTheCountryUnknown() {
        let es = SpeedLimitMatch(edges: [edge(100, 90)], points: [point(0, 0), point(0, 1)], countryCode: "ES")
        let fr = SpeedLimitMatch(edges: [edge(100, 80)], points: [point(0, 0), point(0, 1)], countryCode: "FR")
        let p = SpeedLimitProfileBuilder.build(pieces: [.init(pointMeters: [0, 100], match: es),
                                                        .init(pointMeters: [100, 200], match: fr)], routeMeters: 200)
        XCTAssertNil(p.countryCode)
    }

    // MARK: Qué se muestra

    private let fixed = SpeedLimitProfile(segments: [
        SpeedLimitSegment(startMeters: 0, endMeters: 1000, limitKmh: 90),
        SpeedLimitSegment(startMeters: 1000, endMeters: 2000, limitKmh: 50),
        SpeedLimitSegment(startMeters: 2000, endMeters: 3000, limitKmh: nil),
    ], routeMeters: 3000)

    private func step(_ tracker: inout SpeedLimitTracker, _ meters: Double, off: Bool = false, distance: Double = 3,
                      accuracy: Double = 8, age: TimeInterval = 1, enabled: Bool = true,
                      profile: SpeedLimitProfile?? = .some(nil)) -> SpeedLimitDisplay {
        let chosen: SpeedLimitProfile? = { if case .some(.some(let p)) = profile { return p }; return fixed }()
        return tracker.update(enabled: enabled, profile: chosen, progressMeters: meters, isOffRoute: off,
                              distanceFromRoute: distance, accuracy: accuracy, age: age)
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

    func testUntrustworthyPositionSaysInsufficientLocationNotALimit() {
        var tracker = SpeedLimitTracker()
        XCTAssertEqual(step(&tracker, 500), .limit(kmh: 90))
        XCTAssertEqual(step(&tracker, 500, off: true), .uncertainRoad, "fuera de ruta: la vía de la ruta ya no vale")
        XCTAssertEqual(step(&tracker, 500, accuracy: 60), .insufficientLocation, "precisión que no distingue una paralela")
        XCTAssertEqual(step(&tracker, 500, accuracy: -1), .insufficientLocation, "lectura inválida")
        XCTAssertEqual(step(&tracker, 500, age: 30), .insufficientLocation, "ubicación antigua")
        XCTAssertEqual(step(&tracker, 500, distance: 40), .uncertainRoad, "a 40 m de la ruta: quizá la vía paralela")
        XCTAssertEqual(step(&tracker, 500, distance: 15), .uncertainRoad, "sin comprobar el recorrido, 15 m ya es dudoso")
    }

    func testRecoveryAfterLosingTheLocationShowsTheCurrentSegmentAtOnce() {
        var tracker = SpeedLimitTracker()
        _ = step(&tracker, 500)
        XCTAssertEqual(tracker.locationLost(enabled: true), .insufficientLocation)
        XCTAssertEqual(step(&tracker, 1500), .limit(kmh: 50), "tras recuperar se muestra el del tramo actual")
    }

    func testDisabledShowsNothingAndWithoutProfileSaysUnavailable() {
        var tracker = SpeedLimitTracker()
        XCTAssertEqual(step(&tracker, 500, enabled: false), .hidden)
        var other = SpeedLimitTracker()
        XCTAssertEqual(other.update(enabled: true, profile: nil, progressMeters: 500, isOffRoute: false, accuracy: 5, age: 1),
                       .unavailable, "cargando o sin servicio: nunca una cifra supuesta")
    }

    // MARK: Unidades y accesibilidad

    func testMphIsAnHonestConversionWithItsUnitShown() {
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 50, metric: true), 50)
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 50, metric: false), 31, "conversión, sin inventar un 30")
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 89, metric: false), 55, "dato de EE. UU. (55 mph guardado como 89 km/h)")
        XCTAssertEqual(SpeedLimitFormatter.signNumber(kmh: 40, metric: false), 25)
        XCTAssertEqual(SpeedLimitFormatter.unitCaption(metric: true), "km/h")
        XCTAssertEqual(SpeedLimitFormatter.unitCaption(metric: false), "≈ mph")
    }

    func testAccessibilityLabelsAreExplicit() {
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.limit(kmh: 50), metric: true), "Límite de velocidad: 50 kilómetros por hora")
        XCTAssertTrue(SpeedLimitFormatter.spokenLabel(.limit(kmh: 50), metric: false).contains("convertido desde 50 kilómetros por hora"))
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.unavailable, metric: true), "Límite de velocidad no disponible")
        XCTAssertTrue(SpeedLimitFormatter.spokenLabel(.insufficientLocation, metric: true).contains("ubicación insuficiente"))
        XCTAssertEqual(SpeedLimitFormatter.spokenLabel(.hidden, metric: true), "")
    }

    func testCurrentSpeedIsNilWhenTheReadingDoesNotHaveAValidOne() {
        let invalid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -3), altitude: 0, horizontalAccuracy: 5,
                                 verticalAccuracy: 5, course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1, timestamp: Date())
        XCTAssertNil(SpeedLimitFormatter.currentSpeedKmh(invalid))
        let valid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -3), altitude: 0, horizontalAccuracy: 5,
                               verticalAccuracy: 5, course: 0, courseAccuracy: 5, speed: 10, speedAccuracy: 1, timestamp: Date())
        XCTAssertEqual(SpeedLimitFormatter.currentSpeedKmh(valid) ?? 0, 36, accuracy: 0.01)
        XCTAssertNil(SpeedLimitFormatter.currentSpeedKmh(nil))
    }

    // MARK: Servicio (sin red real)

    func testRequestUsesPostWithoutAnyKeyAndAsksForMatchingAttributes() throws {
        let request = ValhallaSpeedLimitService.request(
            endpoint: URL(string: "https://example.test/trace_attributes")!,
            shape: [CLLocationCoordinate2D(latitude: 1, longitude: 2), CLLocationCoordinate2D(latitude: 1.1, longitude: 2.1)])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["units"] as? String, "kilometers")
        XCTAssertEqual(body["shape_match"] as? String, "map_snap")
        let attributes = Set((body["filters"] as? [String: Any])?["attributes"] as? [String] ?? [])
        XCTAssertTrue(attributes.isSuperset(of: ["edge.speed_limit", "edge.length", "matched.edge_index",
                                                 "matched.distance_along_edge", "matched.distance_from_trace_point", "admin.country_code"]))
        XCTAssertNil(body["trace_options"])
    }

    func testRouteIsThinnedWithItsRealMetersAndSplitInContiguousChunks() {
        let points = (0...600).map { CLLocationCoordinate2D(latitude: 40 + Double($0) * 0.0001, longitude: -3) } // ~6,7 km
        let total = ValhallaSpeedLimitService.length(points)
        let (kept, meters) = ValhallaSpeedLimitService.thinnedWithMeters(points, minSpacing: 20)
        XCTAssertEqual(kept.count, meters.count)
        XCTAssertEqual(meters.first, 0)
        XCTAssertEqual(meters.last ?? 0, total, accuracy: 0.5)
        XCTAssertEqual(zip(meters, meters.dropFirst()).allSatisfy { $0 < $1 }, true)
        let ranges = ValhallaSpeedLimitService.chunkRanges(meters: meters, chunkMeters: 2000, maxChunks: 20)
        XCTAssertGreaterThanOrEqual(ranges.count, 3)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, meters.count - 1)
        for (a, b) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound, "sin huecos") }
    }

    private static let serverAnswer = """
    {"units":"kilometers","admins":[{"country_code":"ES"}],
     "edges":[{"speed_limit":50,"length":1.1},{"speed_limit":30,"length":1.1}],
     "matched_points":[{"type":"matched","edge_index":0,"distance_along_edge":0,"distance_from_trace_point":1},
                       {"type":"matched","edge_index":0,"distance_along_edge":1,"distance_from_trace_point":1},
                       {"type":"matched","edge_index":1,"distance_along_edge":1,"distance_from_trace_point":1}]}
    """

    private let route = [CLLocationCoordinate2D(latitude: 40.40, longitude: -3.7), CLLocationCoordinate2D(latitude: 40.41, longitude: -3.7),
                         CLLocationCoordinate2D(latitude: 40.42, longitude: -3.7)]

    private func service() -> ValhallaSpeedLimitService {
        ValhallaSpeedLimitService(
            client: ServiceClient(service: "valhalla", session: StubURLProtocol.session(), retry: instantRetry(maxRetries: 0), diagnostics: DiagnosticsLog()))
    }

    func testServiceBuildsAProfileFromTheServerAnswerAndCachesIt() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.responder = { _ in ok(Data(Self.serverAnswer.utf8)) }
        let service = service()
        let profile = try await service.profile(for: route)
        XCTAssertEqual(profile.limit(atMeters: 300), 50)
        XCTAssertEqual(profile.limit(atMeters: 1900), 30)
        XCTAssertEqual(profile.countryCode, "ES")
        let calls = StubURLProtocol.requests.count
        _ = try await service.profile(for: route)
        XCTAssertEqual(StubURLProtocol.requests.count, calls, "la misma ruta no se vuelve a consultar")
    }

    func testAnswerWithoutOneResultPerPointIsNotTrusted() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.responder = { _ in ok(Data(#"{"units":"kilometers","edges":[{"speed_limit":50,"length":2.2}]}"#.utf8)) }
        do {
            _ = try await service().profile(for: route)
            XCTFail("Sin asociación por punto no se puede ubicar el límite")
        } catch {
            XCTAssertEqual(error as? SpeedLimitError, .noData)
        }
    }

    func testServiceFailureThrowsInsteadOfInventingLimits() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.responder = { _ in http(503) }
        do {
            _ = try await service().profile(for: route)
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SpeedLimitError, .noData)
        }
    }

    func testCacheExpires() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = SpeedLimitCache(lifetime: 60, clock: { now })
        let profile = SpeedLimitProfile(segments: [], routeMeters: 1)
        cache.store(profile, for: "a")
        XCTAssertNotNil(cache.value(for: "a"))
        now = now.addingTimeInterval(61)
        XCTAssertNil(cache.value(for: "a"))
    }

    // MARK: Diseño

    func testAutomaticDesignUsesTheProviderCountryAndADocumentedDefault() {
        XCTAssertEqual(SpeedSignStyle.automatic.resolved(countryCode: "US"), .unitedStates)
        XCTAssertEqual(SpeedSignStyle.automatic.resolved(countryCode: "pr"), .unitedStates)
        XCTAssertEqual(SpeedSignStyle.automatic.resolved(countryCode: "ES"), .european)
        XCTAssertEqual(SpeedSignStyle.automatic.resolved(countryCode: nil), .european, "sin país: circular (por defecto)")
        XCTAssertEqual(SpeedSignStyle.minimal.resolved(countryCode: "US"), .minimal, "una elección explícita no se cambia")
    }

    func testNoDataPreferenceDecidesWhetherSomethingIsDrawn() {
        var appearance = SpeedSignAppearance.defaults
        XCTAssertFalse(SpeedLimitSign.isEmpty(.unavailable, appearance: appearance), "por defecto: «—»")
        appearance.noData = .hide
        XCTAssertTrue(SpeedLimitSign.isEmpty(.unavailable, appearance: appearance))
        XCTAssertTrue(SpeedLimitSign.isEmpty(.insufficientLocation, appearance: appearance))
        XCTAssertFalse(SpeedLimitSign.isEmpty(.limit(kmh: 50), appearance: appearance))
        XCTAssertTrue(SpeedLimitSign.isEmpty(.hidden, appearance: .defaults))
    }

    // MARK: Ajustes persistentes

    @MainActor
    func testSettingsSurviveReopeningTheStoreAndResetOnlyTouchesThisSection() throws {
        XCTAssertTrue(UserSettings().showSpeedLimit)
        XCTAssertEqual(UserSettings().speedSignAppearance, .defaults)
        XCTAssertFalse(UserSettings().speedLimitWithoutRoute)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("s.store")
        var keep: [ModelContainer] = []
        func open() throws -> ModelContainer {
            let c = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
            keep.append(c); return c
        }
        let custom = SpeedSignAppearance(style: .unitedStates, size: .large, position: .topTrailing, noData: .hide, showsCurrentSpeed: true)
        do {
            let context = ModelContext(try open())
            let settings = UserSettings()
            settings.showSpeedLimit = false
            settings.useMetricUnits = false
            settings.speedLimitWithoutRoute = true
            settings.speedSignAppearance = custom
            context.insert(settings)
            context.insert(SavedPlace(name: "Casa", kind: .home, latitude: 40.4, longitude: -3.7))
            try PersistenceCommit.save(context)
        }
        do {
            let context = ModelContext(try open())
            let stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
            XCTAssertEqual(stored.showSpeedLimit, false)
            XCTAssertEqual(stored.speedLimitWithoutRoute, true)
            XCTAssertEqual(stored.speedSignAppearance, custom)
            stored.resetSpeedSignSettings()
            try PersistenceCommit.save(context)
        }
        let context = ModelContext(try open())
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(stored.speedSignAppearance, .defaults)
        XCTAssertTrue(stored.showSpeedLimit)
        XCTAssertFalse(stored.speedLimitWithoutRoute)
        XCTAssertFalse(stored.useMetricUnits, "restablecer no toca otros ajustes")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedPlace>()).count, 1, "ni Casa")
    }
}

// MARK: - Navegación: respuestas fuera de orden, reintentos y pérdida de señal

private struct NoRoutes: RouteServiceProtocol {
    func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] { [] }
}

private final class ScriptedProfiles: SpeedLimitProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<SpeedLimitProfile, Error>]
    private(set) var calls = 0
    init(_ answers: [Result<SpeedLimitProfile, Error>]) { self.answers = answers }

    func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile {
        lock.lock()
        calls += 1
        let answer = answers.isEmpty ? .failure(SpeedLimitError.noData) : answers.removeFirst()
        lock.unlock()
        return try answer.get()
    }
}

@MainActor
final class SpeedLimitNavigationTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let points = [CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000),
                          CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.7000),
                          CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000)]
    private let profile50 = SpeedLimitProfile(segments: [SpeedLimitSegment(startMeters: 0, endMeters: 1200, limitKmh: 50)],
                                              routeMeters: 1200, countryCode: "ES")

    private func makeNavigation(_ service: SpeedLimitProviding) -> ActiveNavigationViewModel {
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "speed-\(UUID().uuidString)")!, synthesizer: FakeSynthesizer(),
                                    session: FakeSession(), voices: { [] }, observeSystemEvents: false)
        let route = Route(name: "Prueba", coordinates: points, distanceMeters: 1110, durationSeconds: 120, steps: [
            RouteStep(instruction: "Sal", distanceMeters: 1110, symbol: "arrow.up", streetName: ""),
            RouteStep(instruction: "Has llegado", distanceMeters: 0, symbol: "flag", streetName: ""),
        ])
        return ActiveNavigationViewModel(route: route, destinationName: "Destino", destination: points[2], mode: .driving,
                                         routeService: NoRoutes(), speech: voice, useMetric: true,
                                         speedLimitService: service, showsSpeedLimit: true, clock: { [unowned self] in self.now })
    }

    private func reading(_ coordinate: CLLocationCoordinate2D, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: 0, courseAccuracy: 5, speed: 12, speedAccuracy: 1, timestamp: now)
    }

    /// Deja terminar las tareas pendientes (consultas simuladas, que vuelven al hilo principal).
    private func settle() async {
        for _ in 0..<6 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(3))
        }
    }

    func testLimitAppearsWhenTheProfileArrivesAndAnOldRouteAnswerIsIgnored() async {
        let navigation = makeNavigation(ScriptedProfiles([.success(profile50)]))
        navigation.start()
        navigation.update(with: reading(points[0]))
        XCTAssertEqual(navigation.speedLimit, .unavailable, "mientras llega la respuesta: sin cifra")
        await settle()
        navigation.update(with: reading(CLLocationCoordinate2D(latitude: 40.4010, longitude: -3.7)))
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50))
        XCTAssertEqual(navigation.speedLimitCountry, "ES")
        // Respuesta de otra ruta (anterior a un recálculo) que llega tarde: no cambia nada.
        let stale = SpeedLimitProfile(segments: [SpeedLimitSegment(startMeters: 0, endMeters: 1200, limitKmh: 120)], routeMeters: 1200)
        navigation.applySpeedProfile(.success(stale), routeID: UUID())
        navigation.update(with: reading(CLLocationCoordinate2D(latitude: 40.4015, longitude: -3.7)))
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50))
    }

    func testNetworkFailureRetriesLaterAndNeverShowsAFigureMeanwhile() async {
        let service = ScriptedProfiles([.failure(URLError(.notConnectedToInternet)), .success(profile50)])
        let navigation = makeNavigation(service)
        navigation.start()
        await settle()
        navigation.update(with: reading(points[0]))
        XCTAssertEqual(navigation.speedLimit, .providerError, "E: falló el proveedor; sin cifra")
        XCTAssertEqual(service.calls, 1)
        now = now.addingTimeInterval(5)
        navigation.update(with: reading(points[0]))
        await settle()
        XCTAssertEqual(service.calls, 1, "no se reintenta en cada lectura")
        now = now.addingTimeInterval(11)
        navigation.update(with: reading(points[0]))
        await settle()
        XCTAssertEqual(service.calls, 2, "reintento tras la espera")
        navigation.update(with: reading(points[0]))
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50))
    }

    func testSignalLossDropsTheFigureAndDisablingHidesIt() async {
        let navigation = makeNavigation(ScriptedProfiles([.success(profile50)]))
        navigation.start()
        await settle()
        navigation.update(with: reading(points[0]))
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50))
        now = now.addingTimeInterval(10)                      // sin lecturas nuevas
        navigation.checkLocationFreshness()
        XCTAssertEqual(navigation.speedLimit, .insufficientLocation, "no se mantiene la cifra")
        XCTAssertNil(navigation.currentSpeedKmh)
        navigation.update(with: reading(points[0]))
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50), "al recuperar la señal vuelve al momento")
        navigation.update(with: reading(points[0], accuracy: 120))
        XCTAssertEqual(navigation.speedLimit, .insufficientLocation, "ubicación demasiado imprecisa")
        navigation.setShowsSpeedLimit(false)
        XCTAssertEqual(navigation.speedLimit, .hidden)
    }

    func testRetryDelaysGrowAndAreCapped() {
        XCTAssertEqual(ActiveNavigationViewModel.retryDelay(attempt: 1), 15)
        XCTAssertEqual(ActiveNavigationViewModel.retryDelay(attempt: 2), 30)
        XCTAssertEqual(ActiveNavigationViewModel.retryDelay(attempt: 3), 60)
        XCTAssertEqual(ActiveNavigationViewModel.retryDelay(attempt: 9), 120)
    }
}

// MARK: - Sin ruta (map matching del recorrido reciente)

private final class FakeMatcher: SpeedLimitTraceMatching, @unchecked Sendable {
    private let lock = NSLock()
    var answer: Result<SpeedLimitMatch, Error>
    private(set) var traces: [[SpeedLimitTracePoint]] = []
    init(_ answer: Result<SpeedLimitMatch, Error>) { self.answer = answer }

    func match(trace: [SpeedLimitTracePoint]) async throws -> SpeedLimitMatch {
        lock.lock()
        traces.append(trace)
        let answer = self.answer
        lock.unlock()
        return try answer.get()
    }
}

@MainActor
final class FreeDriveSpeedLimitTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let start = CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000)
    private let onRoad50 = SpeedLimitMatch(edges: [edge(300, 50), edge(400, 50)],
                                           points: [point(0, 0), point(1, 0.5)], countryCode: "ES")

    private func reading(metersNorth: Double, speed: Double = 14, accuracy: Double = 5) -> CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: start.latitude + metersNorth / 111_320, longitude: start.longitude)
        return CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                          course: 0, courseAccuracy: 5, speed: speed, speedAccuracy: 1, timestamp: now)
    }

    /// Deja terminar las tareas pendientes (consultas simuladas, que vuelven al hilo principal).
    private func settle() async {
        for _ in 0..<6 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(3))
        }
    }

    /// Recorre `meters` hacia el norte a 14 m/s con una lectura por segundo.
    private func drive(_ limiter: FreeDriveSpeedLimit, from: Double = 0, meters: Double, speed: Double = 14) async {
        var along = from
        while along <= from + meters {
            limiter.ingest(reading(metersNorth: along, speed: speed))
            await settle()
            along += speed
            now = now.addingTimeInterval(1)
        }
    }

    private func make(_ matcher: FakeMatcher) -> FreeDriveSpeedLimit {
        let limiter = FreeDriveSpeedLimit(matcher: matcher, clock: { [unowned self] in self.now })
        limiter.setEnabled(true)
        return limiter
    }

    func testIdentifiesTheRoadFromTheRecentTraceAndShowsItsExplicitLimit() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        XCTAssertEqual(limiter.display, .insufficientLocation)
        await drive(limiter, meters: 160)
        XCTAssertEqual(matcher.traces.count, 1, "una consulta, no una por lectura")
        XCTAssertGreaterThanOrEqual(matcher.traces[0].count, 4, "se envía el recorrido, no un punto suelto")
        XCTAssertEqual(limiter.display, .limit(kmh: 50))
        XCTAssertEqual(limiter.countryCode, "ES")
    }

    func testRoadWithoutDataAndUncertainMatchDoNotShowAFigure() async {
        let noData = FakeMatcher(.success(SpeedLimitMatch(edges: [edge(500, nil)], points: [point(0, 0), point(0, 0.5)], countryCode: nil)))
        let a = make(noData)
        await drive(a, meters: 160)
        XCTAssertEqual(a.display, .unavailable)
        let far = FakeMatcher(.success(SpeedLimitMatch(edges: [edge(500, 30)], points: [point(0, 0), point(0, 0.5, offset: 26)], countryCode: nil)))
        let b = make(far)
        await drive(b, meters: 160)
        XCTAssertEqual(b.display, .uncertainRoad, "vía elegida a 26 m: tramo incierto, no se muestra el 30")
    }

    func testLateAnswerFromAnOlderRequestIsDiscarded() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        await drive(limiter, meters: 160)
        XCTAssertEqual(limiter.display, .limit(kmh: 50))
        let old = SpeedLimitMatch(edges: [edge(500, 120)], points: [point(0, 0), point(0, 0.5)], countryCode: "ES")
        limiter.apply(.success(old), order: 0, anchor: reading(metersNorth: 160))
        XCTAssertEqual(limiter.display, .limit(kmh: 50))
    }

    func testTheLimitExpiresAfterLeavingTheIdentifiedRoadWithoutANewAnswer() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        await drive(limiter, meters: 160)
        XCTAssertEqual(limiter.display, .limit(kmh: 50))
        matcher.answer = .failure(URLError(.notConnectedToInternet))     // sin red a partir de aquí
        await drive(limiter, from: 174, meters: 700)
        XCTAssertEqual(limiter.display, .uncertainRoad, "no se arrastra el 50 indefinidamente")
    }

    func testNothingIsSentNearHomeOrWorkOrWhenThePlacesCannotBeRead() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        limiter.excludedAreas = { [self] in [self.start] }
        await drive(limiter, meters: 250)
        XCTAssertTrue(matcher.traces.isEmpty)
        XCTAssertEqual(limiter.display, .uncertainRoad)

        let other = FakeMatcher(.success(onRoad50))
        let blind = make(other)
        blind.excludedAreas = { nil }
        await drive(blind, meters: 250)
        XCTAssertTrue(other.traces.isEmpty, "si no se pueden leer Casa/Trabajo, no se envía nada")
    }

    func testStandingStillOrWalkingDoesNotQueryAndDisablingStopsEverything() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        await drive(limiter, meters: 40, speed: 1.2)
        XCTAssertTrue(matcher.traces.isEmpty)
        limiter.setEnabled(false)
        XCTAssertEqual(limiter.display, .hidden)
        await drive(limiter, meters: 200)
        XCTAssertTrue(matcher.traces.isEmpty)
    }

    func testSignalLossDropsTheFigure() async {
        let matcher = FakeMatcher(.success(onRoad50))
        let limiter = make(matcher)
        await drive(limiter, meters: 160)
        XCTAssertEqual(limiter.display, .limit(kmh: 50))
        now = now.addingTimeInterval(10)
        limiter.checkFreshness()
        XCTAssertEqual(limiter.display, .insufficientLocation)
    }
}
