import CoreLocation
import XCTest
@testable import QuestMapIRL

/// Recorridos controlados del criterio de fiabilidad del límite (sin red ni GPS reales). Vehículo: turismo.
final class SpeedLimitResolverTests: XCTestCase {
    private let good = LocationEvidence(accuracy: 6, age: 1)

    private func route(_ limit: Int?, way: Int64?, distance: Double = 3, offRoute: Bool = false,
                       state: RouteSpeedEvidence.ProfileState = .loaded) -> RouteSpeedEvidence {
        RouteSpeedEvidence(segment: SpeedLimitSegment(startMeters: 0, endMeters: 500, limitKmh: limit, wayID: way,
                                                      roadName: "Vía \(way ?? 0)", raw: limit.map(String.init) ?? "sin dato"),
                           profileState: state, distanceFromRoute: distance, isOffRoute: offRoute)
    }

    private func live(_ limit: Int?, way: Int64?, confident: Bool = true, inside: Bool = true, age: TimeInterval = 3,
                      raw: String? = nil) -> LiveRoadEvidence {
        LiveRoadEvidence(wayID: way, limitKmh: limit, raw: raw ?? limit.map(String.init) ?? "sin dato", roadName: "Real \(way ?? 0)",
                         confident: confident, stillOnIdentifiedRoad: inside, ageSeconds: age)
    }

    private func resolve(_ r: RouteSpeedEvidence?, _ l: LiveRoadEvidence?, _ loc: LocationEvidence? = nil) -> SpeedLimitDecision {
        SpeedLimitResolver.resolve(route: r, live: l, location: loc ?? good)
    }

    // 1. Cambio de límite dentro de una misma vía (en OSM, al cambiar maxspeed la vía se divide): manda la vía real.
    func testLimitChangeAlongTheRoadFollowsTheRealWay() {
        XCTAssertEqual(resolve(route(50, way: 1), live(50, way: 1)).display, .limit(kmh: 50))
        XCTAssertEqual(resolve(route(50, way: 1), live(30, way: 2)).display, .limit(kmh: 30), "ya en el tramo siguiente")
    }

    // 2. Autopista con calle paralela: la ruta dice 120 pero vas por la vía de servicio.
    func testParallelServiceRoadNeverGetsTheMotorwayLimit() {
        let onService = resolve(route(120, way: 10, distance: 15), live(50, way: 11))
        XCTAssertEqual(onService.display, .limit(kmh: 50))
        XCTAssertEqual(onService.source, .liveTrace)
        XCTAssertTrue(onService.reason.contains("distinta"))
        // Sin comprobar el recorrido, a 15 m de la ruta no se da la cifra por buena.
        XCTAssertEqual(resolve(route(120, way: 10, distance: 15), nil).display, .uncertainRoad)
        XCTAssertEqual(resolve(route(120, way: 10, distance: 4), nil).display, .limit(kmh: 120), "pegado a la ruta")
    }

    // 3. Salida e incorporación: al tomar la salida manda el ramal (con o sin dato), no la autopista.
    func testExitRampUsesTheRampNotTheMotorway() {
        XCTAssertEqual(resolve(route(120, way: 20), live(60, way: 21)).display, .limit(kmh: 60))
        XCTAssertEqual(resolve(route(120, way: 20), live(nil, way: 21)).display, .unavailable, "ramal sin dato: «—», no 120")
    }

    // 4. Cruce a distinto nivel: la identidad de la vía decide, no la cercanía.
    func testGradeSeparatedCrossingUsesTheIdentifiedLevel() {
        let bridge = resolve(route(50, way: 30, distance: 2), live(90, way: 31))
        XCTAssertEqual(bridge.display, .limit(kmh: 90))
        XCTAssertEqual(bridge.wayID, 31)
    }

    // 5. Cambio de sentido: misma vía con límite distinto por sentido → el del sentido real.
    func testDirectionSpecificLimitComesFromTheRealDirection() {
        let decision = resolve(route(50, way: 40), live(30, way: 40))
        XCTAssertEqual(decision.display, .limit(kmh: 30))
        XCTAssertTrue(decision.reason.contains("sentido"))
    }

    // 6. Desvío de la ruta: la ruta deja de valer.
    func testDeviationDropsTheRouteLimit() {
        XCTAssertEqual(resolve(route(80, way: 50, offRoute: true), nil).display, .uncertainRoad)
        XCTAssertEqual(resolve(route(80, way: 50, offRoute: true), live(40, way: 51)).display, .limit(kmh: 40))
    }

    // 7. GPS impreciso o antiguo.
    func testImpreciseOrStaleLocationShowsNoFigure() {
        XCTAssertEqual(resolve(route(50, way: 1), live(50, way: 1), LocationEvidence(accuracy: 50, age: 1)).display, .insufficientLocation)
        XCTAssertEqual(resolve(route(50, way: 1), live(50, way: 1), LocationEvidence(accuracy: -1, age: 1)).display, .insufficientLocation)
        XCTAssertEqual(resolve(route(50, way: 1), live(50, way: 1), LocationEvidence(accuracy: 5, age: 20)).display, .insufficientLocation)
        // Precisión media (25 m): sin comprobación no se fía de la ruta.
        XCTAssertEqual(resolve(route(50, way: 1), nil, LocationEvidence(accuracy: 25, age: 1)).display, .uncertainRoad)
    }

    // 8. Falta de dato y «sin límite general» explícito: nunca una cifra ni «sin límite».
    func testMissingDataAndUnlimitedAreNotNumbers() {
        XCTAssertEqual(resolve(nil, live(nil, way: 60)).display, .unavailable)
        let autobahn = resolve(nil, live(nil, way: 61, raw: "unlimited"))
        XCTAssertEqual(autobahn.display, .unavailable)
        XCTAssertTrue(autobahn.reason.contains("sin límite general"))
    }

    // 9. Condición no evaluable: un valor condicional o no numérico no se convierte en cifra.
    func testConditionalOrTextValuesAreNotConfirmedFigures() {
        XCTAssertNil(SpeedLimitParser.limit(from: "30 @ (Mo-Fr 07:00-09:00)"))
        XCTAssertNil(SpeedLimitParser.limit(from: "ES:urban"))
        XCTAssertNil(SpeedLimitParser.limit(from: "unlimited"))
        XCTAssertNil(SpeedLimitParser.limit(from: "signals"))
    }

    // 11. Respuesta antigua y tramo incierto según el proveedor.
    func testOldOrUncertainLiveEvidenceIsNotTrusted() {
        XCTAssertEqual(resolve(route(50, way: 1, distance: 15), live(30, way: 2, age: 200)).display, .uncertainRoad,
                       "evidencia caducada: no vale y la ruta a 15 m tampoco")
        XCTAssertEqual(resolve(route(50, way: 1, distance: 2), live(30, way: 2, confident: false)).display, .uncertainRoad,
                       "el proveedor no sabe la vía: no se usa la ruta aunque pase cerca")
        XCTAssertEqual(resolve(route(50, way: 1, distance: 2), live(30, way: 2, inside: false)).display, .limit(kmh: 50),
                       "ya fuera de la vía identificada: vuelve el criterio estricto de la ruta")
    }

    // Estado E: el proveedor falló y no hay otra base.
    func testProviderErrorIsItsOwnState() {
        XCTAssertEqual(resolve(route(nil, way: nil, state: .failed), nil).display, .providerError)
        XCTAssertEqual(resolve(route(nil, way: nil, state: .loading), nil).display, .unavailable)
    }

    // Diagnóstico: sin coordenadas, con motivo y cambio de vía.
    func testDiagnosticExplainsSourceAndChanges() {
        let first = SpeedLimitDiagnostic.make(resolve(route(120, way: 10), live(120, way: 10)), previous: nil, dataAge: 2,
                                              accuracy: 6, metric: true)
        XCTAssertEqual(first.source, "ruta")
        XCTAssertEqual(first.interpreted, "120 km/h")
        XCTAssertEqual(first.wayID, 10)
        let second = SpeedLimitDiagnostic.make(resolve(route(120, way: 10), live(60, way: 21)), previous: first, dataAge: 1,
                                               accuracy: 6, metric: false)
        XCTAssertEqual(second.change, "cambio de vía 10 → 21")
        XCTAssertEqual(second.interpreted, "37 mph (de 60 km/h)")
        XCTAssertEqual(second.raw, "60")
    }

    // Parser: identificador de vía, nombre y valor original.
    func testParserKeepsWayIdentityNamesAndRawValue() throws {
        let json = #"{"units":"kilometers","edges":[{"speed_limit":"unlimited","length":1.0,"way_id":286344110,"names":["A 9","E 45"]},{"speed_limit":50,"length":0.2,"way_id":24253745,"names":["Paseo de la Castellana"]}],"matched_points":[]}"#
        let match = try SpeedLimitParser.match(from: Data(json.utf8))
        XCTAssertNil(match.edges[0].limitKmh)
        XCTAssertEqual(match.edges[0].raw, "unlimited")
        XCTAssertEqual(match.edges[0].wayID, 286_344_110)
        XCTAssertEqual(match.edges[0].roadName, "A 9")
        XCTAssertEqual(match.edges[1].limitKmh, 50)
        XCTAssertEqual(match.edges[1].raw, "50")
    }

    func testRequestAsksForWayIdentity() throws {
        let request = ValhallaSpeedLimitService.request(endpoint: URL(string: "https://example.test/x")!,
                                                        shape: [CLLocationCoordinate2D(latitude: 1, longitude: 1),
                                                                CLLocationCoordinate2D(latitude: 1.1, longitude: 1)])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let attributes = Set((body["filters"] as? [String: Any])?["attributes"] as? [String] ?? [])
        XCTAssertTrue(attributes.isSuperset(of: ["edge.way_id", "edge.names", "edge.speed_limit"]))
    }

    // Recorrido de navegación completo: la ruta va por la autopista y el recorrido real toma la vía de servicio.
    @MainActor
    func testNavigationUsesTheRealRoadWhenTheTraceDisagreesWithTheRoute() async {
        let points = [CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000), CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000)]
        let route = Route(name: "Prueba", coordinates: points, distanceMeters: 1110, durationSeconds: 60, steps: [
            RouteStep(instruction: "Sal", distanceMeters: 1110, symbol: "arrow.up", streetName: ""),
            RouteStep(instruction: "Has llegado", distanceMeters: 0, symbol: "flag", streetName: ""),
        ])
        struct Profiles: SpeedLimitProviding {
            func profile(for coordinates: [CLLocationCoordinate2D]) async throws -> SpeedLimitProfile {
                SpeedLimitProfile(segments: [SpeedLimitSegment(startMeters: 0, endMeters: 1200, limitKmh: 120, wayID: 10)], routeMeters: 1200)
            }
        }
        struct NoRoutes: RouteServiceProtocol {
            func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] { [] }
        }
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "res-\(UUID().uuidString)")!, synthesizer: FakeSynthesizer(),
                                    session: FakeSession(), voices: { [] }, observeSystemEvents: false)
        let navigation = ActiveNavigationViewModel(route: route, destinationName: "X", destination: points[1], mode: .driving,
                                                   routeService: NoRoutes(), speech: voice, useMetric: true,
                                                   speedLimitService: Profiles(), showsSpeedLimit: true)
        var real: LiveRoadEvidence? = nil
        navigation.liveRoad = { _ in real }
        navigation.start()
        for _ in 0..<6 { await Task.yield(); try? await Task.sleep(for: .milliseconds(3)) }
        func read() {
            navigation.update(with: CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.4020, longitude: -3.7000), altitude: 0,
                                               horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, courseAccuracy: 5,
                                               speed: 20, speedAccuracy: 1, timestamp: Date()))
        }
        read()
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 120), "sin comprobación aún: pegado a la ruta")
        real = LiveRoadEvidence(wayID: 11, limitKmh: 50, raw: "50", roadName: "Vía de servicio", confident: true,
                                stillOnIdentifiedRoad: true, ageSeconds: 1)
        read()
        read()
        XCTAssertEqual(navigation.speedLimit, .limit(kmh: 50), "manda la vía real (tras confirmar el cambio)")
        XCTAssertEqual(navigation.speedLimitDiagnostic?.source, "recorrido real")
        real = LiveRoadEvidence(wayID: nil, limitKmh: nil, raw: "—", roadName: nil, confident: false,
                                stillOnIdentifiedRoad: true, ageSeconds: 1)
        read()
        XCTAssertEqual(navigation.speedLimit, .uncertainRoad, "tramo incierto: la cifra desaparece al momento")
    }
}
