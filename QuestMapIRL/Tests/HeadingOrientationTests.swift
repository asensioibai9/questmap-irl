import CoreLocation
import UIKit
import XCTest
@testable import QuestMapIRL

/// Girar el iPhone NO es girar el vehículo. Pruebas con datos simulados (sin sensores reales).
@MainActor
final class HeadingOrientationTests: XCTestCase {
    // MARK: Referencia de la brújula según la interfaz

    func testCompassReferenceFollowsTheInterfaceOnBothLandscapeSides() {
        XCTAssertEqual(HeadingReference.deviceOrientation(forInterface: .portrait), .portrait)
        // Nombres invertidos entre interfaz y dispositivo: es la equivalencia oficial de UIKit.
        XCTAssertEqual(HeadingReference.deviceOrientation(forInterface: .landscapeLeft), .landscapeRight)
        XCTAssertEqual(HeadingReference.deviceOrientation(forInterface: .landscapeRight), .landscapeLeft)
        XCTAssertEqual(HeadingReference.deviceOrientation(forInterface: .portraitUpsideDown), .portraitUpsideDown)
        XCTAssertNil(HeadingReference.deviceOrientation(forInterface: .unknown), "desconocida: se conserva la anterior")
    }

    func testRotatingPortraitLeftPortraitRightUpdatesCoreLocationEachTime() {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager, diagnostics: DiagnosticsLog(), servicesEnabledProvider: { true },
                                      startTimer: false)
        XCTAssertEqual(manager.headingOrientation, .portrait)
        service.setInterfaceOrientation(.landscapeLeft)
        XCTAssertEqual(manager.headingOrientation, .landscapeRight)
        service.setInterfaceOrientation(.portrait)
        XCTAssertEqual(manager.headingOrientation, .portrait)
        service.setInterfaceOrientation(.landscapeRight)
        XCTAssertEqual(manager.headingOrientation, .landscapeLeft)
        service.setInterfaceOrientation(.unknown)
        XCTAssertEqual(manager.headingOrientation, .landscapeLeft)
    }

    func testRotationDoesNotChangeTheShownHeadingUntilANewCompassReading() {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager, diagnostics: DiagnosticsLog(), servicesEnabledProvider: { true },
                                      startTimer: false)
        service.ingestCompass(30, accuracy: 10)                 // parado, con el móvil en vertical
        XCTAssertEqual(service.displayHeading, 30)
        service.setInterfaceOrientation(.landscapeLeft)
        XCTAssertEqual(service.displayHeading, 30, "girar el móvil no inventa un giro ni salta")
        service.ingestCompass(30, accuracy: 10)                 // iOS ya mide respecto al nuevo borde superior
        XCTAssertEqual(service.displayHeading, 30, "mismo rumbo real = misma flecha")
    }

    // MARK: Política de rumbo

    func testWhileMovingTheGPSCourseRulesAndScreenRotationCannotAffectIt() {
        var selector = HeadingSourceSelector()
        selector.ingestCompass(10, accuracy: 10)
        XCTAssertEqual(selector.ingestFix(speed: 12, course: 270, courseAccuracy: 5), 270)
        selector.referenceChanged()                              // giro de la interfaz en marcha
        XCTAssertEqual(selector.ingestFix(speed: 12, course: 270, courseAccuracy: 5), 270)
        XCTAssertNil(selector.ingestCompass(0, accuracy: 10), "en marcha la brújula no manda")
    }

    func testStoppedWithUnreliableCompassKeepsTheLastReliableHeading() {
        var selector = HeadingSourceSelector()
        selector.ingestCompass(80, accuracy: 15)
        XCTAssertNil(selector.ingestCompass(200, accuracy: 70), "brújula con mucho error: no mueve la flecha")
        XCTAssertNil(selector.ingestCompass(200, accuracy: -1), "sin calibrar: no mueve la flecha")
        XCTAssertEqual(selector.ingestFix(speed: 0, course: -1, courseAccuracy: -1), 80, "parado sin course: rumbo estable")
    }

    func testNoHeadingIsInventedBeforeAnyValidReading() {
        var selector = HeadingSourceSelector()
        XCTAssertNil(selector.ingestFix(speed: 0, course: -1, courseAccuracy: -1))
        XCTAssertNil(selector.heading)
    }

    // MARK: Paso 359° → 0° y relación flecha / cámara

    func testCameraTurnsTheShortWayFrom359To1() {
        let smoother = FollowCameraSmoother()
        let center = CLLocationCoordinate2D(latitude: 43.29, longitude: -2.35)
        var state = FollowCameraSmoother.State(center: center, zoom: 16, pitch: 0, direction: 359)
        let target = FollowCameraSmoother.State(center: center, zoom: 16, pitch: 0, direction: 1)
        for _ in 0..<60 {
            state = smoother.step(state, toward: target, dt: 1.0 / 60, immediate: false)
            let fromTarget = abs(HeadingMath.shortestDelta(from: state.direction, to: 1))
            XCTAssertLessThanOrEqual(fromTarget, 2.0001, "nunca da la vuelta larga")
        }
        XCTAssertLessThan(abs(HeadingMath.shortestDelta(from: state.direction, to: 1)), 0.1)
    }

    func testHeadingUpKeepsTheArrowUpAndNorthUpShowsTheRealDirection() {
        // La flecha se dibuja girada «heading» respecto al MAPA; en pantalla apunta a heading − bearing.
        func screenAngle(heading: Double, bearing: Double) -> Double { HeadingMath.normalized(heading - bearing) }
        for heading in [0.0, 45, 90, 181, 359] {
            XCTAssertEqual(screenAngle(heading: heading, bearing: heading), 0, "rumbo arriba: flecha arriba")
            XCTAssertEqual(screenAngle(heading: heading, bearing: 0), HeadingMath.normalized(heading), "norte arriba: rumbo real")
        }
        XCTAssertEqual(screenAngle(heading: 90, bearing: 30), 60, "exploración manual: respecto al mapa girado")
    }
}
