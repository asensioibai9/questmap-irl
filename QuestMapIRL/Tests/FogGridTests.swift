import XCTest
import CoreLocation
@testable import QuestMapIRL

final class FogGridTests: XCTestCase {
    func testSameCellForNearbyPoints() {
        let a = FogGrid.key(latitude: 40.4000, longitude: -3.7000)
        let b = FogGrid.key(latitude: 40.4005, longitude: -3.7005)
        XCTAssertEqual(a, b)
    }

    func testDifferentCellAcrossBoundary() {
        let a = FogGrid.key(latitude: 40.4000, longitude: -3.7000)
        let b = FogGrid.key(latitude: 40.4030, longitude: -3.7000)
        XCTAssertNotEqual(a, b)
    }

    func testPolylineRevealsIntermediateCells() {
        let keys = FogGrid.keys(along: [
            CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000),
            CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000)
        ])
        // ~1,1 km con celdas de ~220 m → al menos 5 celdas.
        XCTAssertGreaterThanOrEqual(keys.count, 5)
    }
}
