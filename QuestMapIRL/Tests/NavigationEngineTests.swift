import XCTest
import CoreLocation
@testable import QuestMapIRL

final class NavigationEngineTests: XCTestCase {
    // Ruta recta de ~1,1 km hacia el norte (Madrid, aprox.).
    private let points = [
        CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.7000),
        CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000)
    ]

    private func makeEngine() -> NavigationEngine {
        NavigationEngine(
            points: points,
            steps: [RouteStepInfo(instruction: "Continúa recto", distanceMeters: 555),
                    RouteStepInfo(instruction: "Has llegado", distanceMeters: 555)],
            expectedSeconds: 120
        )
    }

    func testStartHasFullRemainingDistance() {
        let snapshot = makeEngine().update(with: points[0])
        XCTAssertEqual(snapshot.progress, 0, accuracy: 0.01)
        XCTAssertEqual(snapshot.remainingMeters, 1110, accuracy: 20)
        XCTAssertEqual(snapshot.stepIndex, 0)
        XCTAssertFalse(snapshot.isOffRoute)
        XCTAssertFalse(snapshot.hasArrived)
    }

    func testMidpointAdvancesToSecondStep() {
        let mid = CLLocationCoordinate2D(latitude: 40.4075, longitude: -3.7000)
        let snapshot = makeEngine().update(with: mid)
        XCTAssertEqual(snapshot.progress, 0.75, accuracy: 0.02)
        XCTAssertEqual(snapshot.stepIndex, 1)
        XCTAssertEqual(snapshot.remainingSeconds, 30, accuracy: 3)
    }

    func testUpcomingManeuverIsTheNextStep() {
        // Al inicio se está en el paso 0; la maniobra a anunciar es la del paso 1.
        let start = makeEngine().update(with: points[0])
        XCTAssertEqual(start.stepIndex, 0)
        XCTAssertEqual(start.upcomingIndex, 1)
        // En el último paso no hay más maniobras: se queda en la última (la llegada).
        let mid = makeEngine().update(with: CLLocationCoordinate2D(latitude: 40.4075, longitude: -3.7000))
        XCTAssertEqual(mid.upcomingIndex, 1)
    }

    func testArrival() {
        let snapshot = makeEngine().update(with: points[2])
        XCTAssertTrue(snapshot.hasArrived)
        XCTAssertEqual(snapshot.remainingMeters, 0, accuracy: 1)
    }

    func testOffRouteDetection() {
        // 0,002° de longitud ≈ 170 m hacia el este.
        let aside = CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.6980)
        let snapshot = makeEngine().update(with: aside)
        XCTAssertTrue(snapshot.isOffRoute)
        XCTAssertEqual(snapshot.distanceFromRoute, 170, accuracy: 15)
    }
}
